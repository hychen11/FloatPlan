import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import UserNotifications

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // 编辑模式下能输入文字
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = TaskStore()
    let ui = UIState()

    private var panel: OverlayPanel!
    private var hosting: NSHostingView<OverlayView>!
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var reminderTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var danmakuPanels: [NSPanel] = []

    private let defaults = UserDefaults.standard
    private var reminderMinutes: Int {
        get { defaults.object(forKey: "reminderMinutes") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "reminderMinutes"); scheduleReminder() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 不显示 Dock 图标
        ui.toggleEdit = { [weak self] in self?.toggleEdit() }
        setupPanel()
        setupStatusItem()
        registerHotKey()
        scheduleReminder()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 悬浮层

    private func setupPanel() {
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 324, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true          // 平时点穿，不会误触
        panel.appearance = NSAppearance(named: .aqua)
        panel.delegate = self

        hosting = NSHostingView(rootView: OverlayView(store: store, ui: ui))
        panel.contentView = hosting

        // 恢复上次的位置（按左上角记）
        let size = hosting.fittingSize
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let left = defaults.object(forKey: "panelLeft") as? Double ?? Double(vf.maxX - size.width - 24)
        let top = defaults.object(forKey: "panelTop") as? Double ?? Double(vf.maxY - 24)
        panel.setFrame(NSRect(x: left, y: top - Double(size.height), width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()

        // 内容变化时自动调整大小，保持左上角不动
        store.$tasks.map { _ in () }
            .merge(with: ui.$editing.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.resizeToFit() } }
            .store(in: &cancellables)
    }

    private func resizeToFit() {
        let size = hosting.fittingSize
        var f = panel.frame
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        panel.setFrame(f, display: true)
    }

    func windowDidMove(_ notification: Notification) {
        defaults.set(Double(panel.frame.minX), forKey: "panelLeft")
        defaults.set(Double(panel.frame.maxY), forKey: "panelTop")
    }

    @objc func toggleEdit() {
        ui.editing.toggle()
        if ui.editing {
            panel.ignoresMouseEvents = false
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            store.removeEmpty()
            panel.makeFirstResponder(nil)
            panel.ignoresMouseEvents = true
            NSApp.deactivate()
            panel.orderFrontRegardless()
        }
    }

    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    // MARK: - 全局快捷键 ⌥⌘P（Carbon RegisterEventHotKey，沙盒里也能用）

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.toggleEdit() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x464C_5054), id: 1) // 'FLPT'
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "checklist", accessibilityDescription: "FloatPlan") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "☑︎"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let edit = NSMenuItem(title: ui.editing ? "完成编辑" : "编辑任务", action: #selector(toggleEdit), keyEquivalent: "p")
        edit.keyEquivalentModifierMask = [.command, .option]
        edit.target = self
        menu.addItem(edit)

        let vis = NSMenuItem(title: panel.isVisible ? "隐藏悬浮层" : "显示悬浮层", action: #selector(toggleVisible), keyEquivalent: "")
        vis.target = self
        menu.addItem(vis)

        let now = NSMenuItem(title: "立即弹一条提醒", action: #selector(fireReminder), keyEquivalent: "")
        now.target = self
        menu.addItem(now)

        menu.addItem(.separator())

        let remind = NSMenuItem(title: "定时提醒", action: nil, keyEquivalent: "")
        let rSub = NSMenu()
        for (title, m) in [("关闭", 0), ("每 15 分钟", 15), ("每 30 分钟", 30), ("每 60 分钟", 60)] {
            let it = NSMenuItem(title: title, action: #selector(setReminder(_:)), keyEquivalent: "")
            it.target = self
            it.tag = m
            it.state = (m == reminderMinutes) ? .on : .off
            rSub.addItem(it)
        }
        remind.submenu = rSub
        menu.addItem(remind)

        menu.addItem(.separator())
        let (bgItem, bgLabel) = sliderItem(value: ui.bgOpacity, min: 0, action: #selector(bgSliderChanged(_:)))
        bgSliderLabel = bgLabel
        updateSliderLabels()
        menu.addItem(bgItem)
        let (txItem, txLabel) = sliderItem(value: ui.textOpacity, min: 0.15, action: #selector(textSliderChanged(_:)))
        textSliderLabel = txLabel
        updateSliderLabels()
        menu.addItem(txItem)

        menu.addItem(.separator())
        let coffee = NSMenuItem(title: "☕ 请作者喝杯咖啡", action: #selector(openDonate), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)
        let gh = NSMenuItem(title: "GitHub 主页 / 反馈问题", action: #selector(openRepo), keyEquivalent: "")
        gh.target = self
        menu.addItem(gh)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 FloatPlan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func setReminder(_ sender: NSMenuItem) { reminderMinutes = sender.tag }

    // 链接统一放在 Links.swift，改用户名只需改那一个文件
    @objc private func openDonate() { if let u = URL(string: Links.donate) { NSWorkspace.shared.open(u) } }
    @objc private func openRepo() { if let u = URL(string: Links.repo) { NSWorkspace.shared.open(u) } }

    // MARK: - 透明度滑块（嵌在菜单里，拖动时悬浮层实时变化）

    private weak var bgSliderLabel: NSTextField?
    private weak var textSliderLabel: NSTextField?

    private func sliderItem(value: Double, min: Double, action: Selector) -> (NSMenuItem, NSTextField) {
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 26, width: 200, height: 16)
        let slider = NSSlider(value: value, minValue: min, maxValue: 1, target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 18, y: 4, width: 204, height: 20)
        box.addSubview(label)
        box.addSubview(slider)
        let item = NSMenuItem()
        item.view = box
        return (item, label)
    }

    private func updateSliderLabels() {
        bgSliderLabel?.stringValue = "背景浓度  \(Int((ui.bgOpacity * 100).rounded()))%"
        textSliderLabel?.stringValue = "文字浓度  \(Int((ui.textOpacity * 100).rounded()))%"
    }

    @objc private func bgSliderChanged(_ s: NSSlider) {
        ui.bgOpacity = s.doubleValue
        updateSliderLabels()
    }

    @objc private func textSliderChanged(_ s: NSSlider) {
        ui.textOpacity = s.doubleValue
        updateSliderLabels()
    }

    // MARK: - 定时提醒：弹幕飘过 + 系统通知

    private func scheduleReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        let m = reminderMinutes
        guard m > 0 else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(m * 60), repeats: true) { [weak self] _ in
            self?.fireReminder()
        }
    }

    @objc func fireReminder() {
        guard let task = store.currentTask else {
            showDanmaku("🎉 今天的任务全部完成了！")
            return
        }
        let prefix = task.status == .doing ? "⏰ 正在做" : "⏰ 该开始"
        showDanmaku("\(prefix)：\(task.title)   （\(store.doneCount)/\(store.tasks.count)）")

        let content = UNMutableNotificationContent()
        content.title = prefix
        content.body = task.title
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func showDanmaku(_ text: String) {
        guard let screen = NSScreen.main else { return }
        let host = NSHostingView(rootView: DanmakuText(text: text))
        let size = host.fittingSize
        let sf = screen.frame
        let y = sf.minY + sf.height * CGFloat.random(in: 0.55...0.8)

        let p = NSPanel(contentRect: NSRect(x: sf.maxX, y: y, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = host
        p.orderFrontRegardless()
        danmakuPanels.append(p)

        let end = NSRect(x: sf.minX - size.width, y: y, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 9
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self, weak p] in
            p?.orderOut(nil)
            self?.danmakuPanels.removeAll { $0 === p }
        })
    }
}

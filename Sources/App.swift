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
        setupDayRollover()
        setupMainMenu()
        ui.$lang.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.languageChanged() } }
            .store(in: &cancellables)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 按天切换

    private var dayTimer: Timer?

    private func setupDayRollover() {
        store.onNewDay = { [weak self] carried in
            self?.showDanmaku(carried > 0
                ? tr("🌅 新的一天！有 \(carried) 项没做完的任务顺延到今天",
                     "🌅 A new day! \(carried) unfinished task\(carried == 1 ? "" : "s") carried over")
                : tr("🌅 新的一天！", "🌅 A new day!"))
        }
        store.checkNewDay()   // 启动时（比如隔天才开电脑）

        // 每分钟检查一次；从睡眠唤醒时也检查
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.store.checkNewDay() }
        RunLoop.main.add(t, forMode: .common)
        dayTimer = t
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.store.checkNewDay() }
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
            .merge(with: ui.$lang.map { _ in () })
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
        guard (notification.object as? NSWindow) === panel else { return }
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

        let edit = NSMenuItem(title: ui.editing ? tr("完成编辑", "Done Editing") : tr("编辑任务", "Edit Tasks"), action: #selector(toggleEdit), keyEquivalent: "p")
        edit.keyEquivalentModifierMask = [.command, .option]
        edit.target = self
        menu.addItem(edit)

        let vis = NSMenuItem(title: panel.isVisible ? tr("隐藏悬浮层", "Hide Overlay") : tr("显示悬浮层", "Show Overlay"), action: #selector(toggleVisible), keyEquivalent: "")
        vis.target = self
        menu.addItem(vis)

        let now = NSMenuItem(title: tr("立即弹一条提醒", "Remind Me Now"), action: #selector(fireReminder), keyEquivalent: "")
        now.target = self
        menu.addItem(now)

        menu.addItem(.separator())

        let remind = NSMenuItem(title: tr("定时提醒", "Reminders"), action: nil, keyEquivalent: "")
        let rSub = NSMenu()
        for (title, m) in [(tr("关闭", "Off"), 0), (tr("每 15 分钟", "Every 15 Minutes"), 15),
                           (tr("每 30 分钟", "Every 30 Minutes"), 30), (tr("每 60 分钟", "Every 60 Minutes"), 60)] {
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

        let dayStart = NSMenuItem(title: tr("新的一天开始于", "New Day Starts At"), action: nil, keyEquivalent: "")
        let dSub = NSMenu()
        for h in [0, 3, 4, 5, 6] {
            let it = NSMenuItem(title: h == 0 ? tr("零点", "Midnight") : tr("凌晨 \(h) 点", "\(h) AM"), action: #selector(setDayStart(_:)), keyEquivalent: "")
            it.target = self
            it.tag = h
            it.state = (h == DayClock.startHour) ? .on : .off
            dSub.addItem(it)
        }
        dayStart.submenu = dSub
        menu.addItem(dayStart)

        historyItems().forEach { menu.addItem($0) }

        // 语言：标题两种语言都写，切错了也找得回来
        let langItem = NSMenuItem(title: "语言 / Language", action: nil, keyEquivalent: "")
        let lSub = NSMenu()
        for (title, l) in [("中文", Lang.zh), ("English", Lang.en)] {
            let it = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = l.rawValue
            it.state = (ui.lang == l) ? .on : .off
            lSub.addItem(it)
        }
        langItem.submenu = lSub
        menu.addItem(langItem)

        menu.addItem(.separator())
        let gh = NSMenuItem(title: tr("GitHub 主页 / 反馈问题", "GitHub / Report an Issue"), action: #selector(openRepo), keyEquivalent: "")
        gh.target = self
        menu.addItem(gh)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("退出 FloatPlan", "Quit FloatPlan"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func setReminder(_ sender: NSMenuItem) { reminderMinutes = sender.tag }

    @objc private func openRepo() { if let u = URL(string: Links.repo) { NSWorkspace.shared.open(u) } }

    // MARK: - 历史窗口

    private var historyWindow: NSWindow?

    @objc func openHistory() {
        if historyWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.contentViewController = NSHostingController(rootView: HistoryView(store: store, ui: ui))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 900, height: 620))
            if !w.setFrameUsingName("FloatPlanHistory") { w.center() }
            w.setFrameAutosaveName("FloatPlanHistory")
            historyWindow = w
        }
        historyWindow?.title = tr("历史计划", "Plan History")
        // 窗口打开时出现在 Dock 和 ⌘Tab 里，关掉后恢复成只在菜单栏
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === historyWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func languageChanged() {
        setupMainMenu()
        historyWindow?.title = tr("历史计划", "Plan History")
    }

    // MARK: - 主菜单（窗口里的 ⌘C ⌘V ⌘Z ⌘A ⌘W 靠它生效）

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("历史计划…", "Plan History…"), action: #selector(openHistory), keyEquivalent: "y").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("退出 FloatPlan", "Quit FloatPlan"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("编辑", "Edit"))
        edit.addItem(withTitle: tr("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: tr("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: tr("窗口", "Window"))
        win.addItem(withTitle: tr("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: tr("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let l = Lang(rawValue: raw) { ui.lang = l }
    }

    @objc private func setDayStart(_ sender: NSMenuItem) {
        DayClock.startHour = sender.tag
        store.checkNewDay()
    }

    /// 历史：一个打开完整窗口的菜单项 + 一个悬停浏览最近 14 天的子菜单
    private func historyItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: tr("历史计划…", "Plan History…"), action: #selector(openHistory), keyEquivalent: "y")
        open.target = self
        return [open, recentItem()]
    }

    private func recentItem() -> NSMenuItem {
        let item = NSMenuItem(title: tr("最近 14 天", "Last 14 Days"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if store.history.isEmpty {
            sub.addItem(NSMenuItem(title: tr("还没有历史记录（明天开始会有）", "No history yet (starts tomorrow)"), action: nil, keyEquivalent: ""))
        }
        for d in store.history.prefix(14) {
            let dayItem = NSMenuItem(
                title: "\(DayClock.display(d.date, short: true))    \(tr("完成", "done")) \(d.doneCount)/\(d.tasks.count)",
                action: nil, keyEquivalent: "")
            let tasksMenu = NSMenu()
            for t in d.tasks {
                tasksMenu.addItem(NSMenuItem(title: "\(statusSymbol(t.status))  \(t.title)", action: nil, keyEquivalent: ""))
            }
            dayItem.submenu = tasksMenu
            sub.addItem(dayItem)
        }
        item.submenu = sub
        return item
    }

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
        bgSliderLabel?.stringValue = "\(tr("背景浓度", "Background"))  \(Int((ui.bgOpacity * 100).rounded()))%"
        textSliderLabel?.stringValue = "\(tr("文字浓度", "Text"))  \(Int((ui.textOpacity * 100).rounded()))%"
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
            showDanmaku(tr("🎉 今天的任务全部完成了！", "🎉 All done for today!"))
            return
        }
        let prefix = task.status == .doing ? tr("⏰ 正在做", "⏰ Now doing") : tr("⏰ 该开始", "⏰ Up next")
        let progress = "\(store.doneCount)/\(store.tasks.count)"
        showDanmaku(tr("\(prefix)：\(task.title)   （\(progress)）",
                       "\(prefix): \(task.title)   (\(progress))"))

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

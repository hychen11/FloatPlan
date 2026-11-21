import SwiftUI
import AppKit

// 三种状态的颜色：完成=灰，进行中=黑，未开始=蓝
func statusColor(_ s: TaskStatus) -> Color {
    switch s {
    case .done: return Color(white: 0.55)
    case .dropped: return Color(red: 0.80, green: 0.42, blue: 0.42)
    case .doing: return .black
    case .todo: return Color(red: 0.10, green: 0.42, blue: 0.95)
    }
}

func statusSymbol(_ s: TaskStatus) -> String {
    switch s {
    case .done: return "✓"
    case .dropped: return "⊘"
    case .doing: return "▶"
    case .todo: return "○"
    }
}

struct OverlayView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: UIState
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(store.tasks) { task in
                if ui.editing { editRow(task) } else { viewRow(task) }
            }
            if ui.editing { addRow; hint }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(ui.editing ? 0.94 : ui.bgOpacity))
        )
        .overlay(
            // 细边：编辑时深一点；平时有背景时是一圈淡白色高光
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ui.editing ? Color.black.opacity(0.18)
                              : Color.white.opacity(ui.bgOpacity > 0.05 ? 0.45 : 0), lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
    }

    private var progress: Double {
        store.countable == 0 ? 0 : Double(store.doneCount) / Double(store.countable)
    }

    // MARK: 标题栏

    @ViewBuilder private var header: some View {
        if ui.editing {
            HStack {
                Text("⠿ \(DayClock.display(store.day))  ·  \(tr("拖动移动位置", "drag to move"))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(DragHandle())
                Button(tr("完成", "Done")) { ui.toggleEdit() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(DayClock.display(store.day))
                    Spacer()
                    Text("\(store.doneCount)/\(store.countable)").monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.32))
                .shadow(color: .white, radius: 1)

                // 今日进度条
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.55))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1.0),
                                                          Color(red: 0.20, green: 0.78, blue: 0.55)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * progress)
                    }
                }
                .frame(height: 3)
                .padding(.bottom, 2)
            }
            .opacity(ui.textOpacity)
        }
    }

    // MARK: 平时的样子（只看，不能点）

    private func viewRow(_ task: PlanTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(statusSymbol(task.status))
                .frame(width: 14)
            Text(task.title)
                .strikethrough(task.status.isClosed)
                .fixedSize(horizontal: false, vertical: true)
            if task.repeatDaily {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
            if task.carriedFrom != nil {
                CarriedTag(days: store.carriedDays(task))
            }
        }
        .font(.system(size: task.status == .doing ? 16 : 14,
                      weight: task.status == .doing ? .bold : .regular))
        .foregroundColor(statusColor(task.status))
        // 白色描边，深色壁纸上也看得清
        .shadow(color: .white.opacity(0.9), radius: 0.8)
        .shadow(color: .white.opacity(0.6), radius: 2)
        .opacity(ui.textOpacity)
    }

    // MARK: 编辑模式

    private func editRow(_ task: PlanTask) -> some View {
        HStack(spacing: 6) {
            Button { setStatus(task.id, task.status.next) } label: {
                Text(statusSymbol(task.status))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(statusColor(task.status))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("点击切换：未开始 → 进行中 → 已完成", "Click to change: to do → in progress → done"))

            TextField(tr("任务", "Task"), text: titleBinding(task.id))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: task.status == .doing ? .bold : .regular))
                .foregroundColor(statusColor(task.status))

            if task.carriedFrom != nil {
                Button { store.acceptCarried(task.id) } label: {
                    CarriedTag(days: store.carriedDays(task))
                }
                .buttonStyle(.plain)
                .help(tr("点击变成今天的待办（未开始）", "Click to make it a to-do for today"))
            }

            Button { store.toggleRepeat(task.id) } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(task.repeatDaily ? statusColor(.todo) : Color.gray.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(task.repeatDaily
                  ? tr("每日重复：已开启", "Repeats daily: on")
                  : tr("设为每日重复（每天自动出现）", "Repeat daily (shows up every day)"))

            iconButton("chevron.up") { store.move(task.id, by: -1) }
            iconButton("chevron.down") { store.move(task.id, by: 1) }
            iconButton("xmark.circle.fill") { store.remove(task.id) }
        }
        .contextMenu { statusMenu(task) }
    }

    /// 右键菜单：直接设成某个状态（“放弃”只在这里）
    @ViewBuilder private func statusMenu(_ task: PlanTask) -> some View {
        Button(tr("✓ 标为已完成", "✓ Mark as Done")) { setStatus(task.id, .done) }
        Button(tr("▶ 标为进行中", "▶ Mark as In Progress")) { setStatus(task.id, .doing) }
        Button(tr("○ 标为未开始", "○ Mark as To Do")) { setStatus(task.id, .todo) }
        Button(tr("⊘ 放弃", "⊘ Give Up")) { setStatus(task.id, .dropped) }
        Divider()
        Button(tr("删除", "Delete")) { store.remove(task.id) }
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            Text("+").font(.system(size: 14, weight: .bold))
                .foregroundColor(.secondary).frame(width: 18)
            TextField(tr("添加任务，回车确认", "Add a task, press Return"), text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit {
                    store.add(newTitle)
                    newTitle = ""
                }
        }
        .padding(.top, 2)
    }

    private var hint: some View {
        Text(tr("⌥⌘P 退出编辑 · 点左侧图标切换状态 · 右键可放弃 · 🔁 每日重复",
                "⌥⌘P to finish · click the left icon to change state · right-click to give up · 🔁 repeat daily"))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.top, 2)
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
    }

    // 用 id 取绑定，删除时不会越界崩溃
    private func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.tasks.first { $0.id == id }?.title ?? "" },
            set: { v in
                if let i = store.tasks.firstIndex(where: { $0.id == id }) { store.tasks[i].title = v }
            }
        )
    }

    private func setStatus(_ id: UUID, _ s: TaskStatus) {
        if let i = store.tasks.firstIndex(where: { $0.id == id }) { store.tasks[i].status = s }
    }
}

/// 顺延提醒：橙色小标签
struct CarriedTag: View {
    let days: Int
    var body: some View {
        Text(days <= 1 ? tr("↪ 顺延", "↪ carried over") : tr("↪ 顺延 \(days) 天", "↪ carried \(days) days"))
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange))
            .fixedSize()
    }
}

/// 编辑模式下拖动窗口用
struct DragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 弹幕文字
/// 弹幕的几种样子：标签文字 + 颜色
enum DanmakuKind {
    case doing, upNext, newDay, allDone

    var label: String {
        switch self {
        case .doing: return tr("正在做", "Now")
        case .upNext: return tr("下一项", "Up next")
        case .newDay: return tr("新的一天", "New day")
        case .allDone: return tr("完成", "Done")
        }
    }

    var color: Color {
        switch self {
        case .doing: return Color(red: 1.0, green: 0.58, blue: 0.15)
        case .upNext: return Color(red: 0.22, green: 0.52, blue: 1.0)
        case .newDay: return Color(red: 0.45, green: 0.40, blue: 0.95)
        case .allDone: return Color(red: 0.20, green: 0.75, blue: 0.45)
        }
    }
}

/// 弹幕：半透明深色胶囊，左边彩色标签，中间文字，右边进度
struct DanmakuText: View {
    let kind: DanmakuKind
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(kind.label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(kind.color))
            Text(text)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(16)          // 给阴影留空间
        .fixedSize()
    }
}

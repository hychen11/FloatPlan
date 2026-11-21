import SwiftUI
import AppKit

// 三种状态的颜色：完成=灰，进行中=黑，未开始=蓝
func statusColor(_ s: TaskStatus) -> Color {
    switch s {
    case .done: return Color(white: 0.55)
    case .doing: return .black
    case .todo: return Color(red: 0.10, green: 0.42, blue: 0.95)
    }
}

func statusSymbol(_ s: TaskStatus) -> String {
    switch s {
    case .done: return "✓"
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
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(ui.editing ? 0.92 : ui.bgOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(ui.editing ? 0.25 : 0), lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
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
            Text("\(DayClock.display(store.day))  ·  \(store.doneCount)/\(store.tasks.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.35))
                .shadow(color: .white, radius: 1)
                .opacity(ui.textOpacity)
        }
    }

    // MARK: 平时的样子（只看，不能点）

    private func viewRow(_ task: PlanTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(statusSymbol(task.status))
                .frame(width: 14)
            Text(task.title)
                .strikethrough(task.status == .done)
                .fixedSize(horizontal: false, vertical: true)
            if task.repeatDaily {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
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
        Text(tr("⌥⌘P 退出编辑 · 点左侧图标切换状态 · 🔁 每日重复",
                "⌥⌘P to finish · click the left icon to change state · 🔁 repeat daily"))
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

/// 编辑模式下拖动窗口用
struct DragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 弹幕文字
struct DanmakuText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1.5)
            .shadow(color: .black, radius: 3)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .fixedSize()
    }
}

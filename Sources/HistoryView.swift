import SwiftUI
import AppKit

/// 按日 / 月 / 年看
enum Granularity: String, CaseIterable {
    case day, month, year

    var title: String {
        switch self {
        case .day: return tr("日", "Day")
        case .month: return tr("月", "Month")
        case .year: return tr("年", "Year")
        }
    }

    /// yyyy-MM-dd 取前几位：日 10、月 7、年 4
    var prefixLength: Int {
        switch self {
        case .day: return 10
        case .month: return 7
        case .year: return 4
        }
    }
}

/// 按状态筛选（左上角四个方块）
enum StatusFilter: String, CaseIterable {
    case all, done, doing, todo

    var title: String {
        switch self {
        case .all: return tr("全部", "All")
        case .done: return tr("已完成", "Done")
        case .doing: return tr("进行中", "In Progress")
        case .todo: return tr("未开始", "To Do")
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .done: return "checkmark.circle.fill"
        case .doing: return "play.circle.fill"
        case .todo: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .all: return .indigo
        case .done: return .gray
        case .doing: return .orange
        case .todo: return .blue
        }
    }

    func matches(_ s: TaskStatus) -> Bool {
        switch self {
        case .all: return true
        case .done: return s == .done
        case .doing: return s == .doing
        case .todo: return s == .todo
        }
    }
}

private func statusIcon(_ s: TaskStatus) -> String {
    switch s {
    case .done: return "checkmark.circle.fill"
    case .doing: return "play.circle.fill"
    case .todo: return "circle"
    }
}

private func statusTint(_ s: TaskStatus) -> Color {
    switch s {
    case .done: return .gray
    case .doing: return .orange
    case .todo: return .blue
    }
}

/// 历史窗口：左边筛选 + 时间列表，右边按天分组的任务，可直接编辑
struct HistoryView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: UIState   // 语言切换时刷新

    @State private var granularity: Granularity
    @State private var period: String?               // "*" = 全部时间
    @State private var filter: StatusFilter
    @State private var search = ""
    @State private var newTitle = ""

    init(store: TaskStore, ui: UIState,
         granularity: Granularity = .day, period: String = "", filter: StatusFilter = .all) {
        self.store = store
        self.ui = ui
        _granularity = State(initialValue: granularity)
        _period = State(initialValue: period.isEmpty ? "*" : period)
        _filter = State(initialValue: filter)
    }

    private var periodKey: String { let p = period ?? "*"; return p == "*" ? "" : p }
    private var days: [DayPlan] { store.allDays }
    private var periodDays: [DayPlan] {
        periodKey.isEmpty ? days : days.filter { $0.date.hasPrefix(periodKey) }
    }
    private var isSingleDay: Bool { granularity == .day && !periodKey.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(SidebarMaterial())
            Divider()
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 480)
        .onChange(of: granularity) { _ in period = "*" }
    }

    // MARK: - 左边

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(StatusFilter.allCases, id: \.self) { tile($0) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Picker("", selection: $granularity) {
                ForEach(Granularity.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    periodRow(key: "*", title: tr("全部时间", "All Time"), plans: days)
                    Text(tr("按\(granularity.title)", "By \(granularity.title)"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(periods, id: \.key) { p in
                        periodRow(key: p.key, title: periodTitle(p.key), plans: p.plans)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private func tile(_ f: StatusFilter) -> some View {
        let n = periodDays.reduce(0) { $0 + $1.tasks.filter { f.matches($0.status) }.count }
        let on = filter == f
        return Button { filter = f } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: f.icon)
                        .font(.system(size: 17))
                        .foregroundColor(on ? .white : f.color)
                    Spacer()
                    Text("\(n)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(on ? .white : .primary)
                }
                Text(f.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(on ? .white.opacity(0.9) : .secondary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(on ? f.color : Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 按当前粒度分组：[(2026-11, [那个月的每天]), ...]，从新到旧
    private var periods: [(key: String, plans: [DayPlan])] {
        var order: [String] = []
        var map: [String: [DayPlan]] = [:]
        for d in days {
            let k = String(d.date.prefix(granularity.prefixLength))
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(d)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func periodTitle(_ key: String) -> String {
        switch granularity {
        case .day: return DayClock.display(key) + (key == store.day ? tr("  今天", "  Today") : "")
        case .month: return DayClock.monthTitle(key)
        case .year: return DayClock.yearTitle(key)
        }
    }

    private func periodRow(key: String, title: String, plans: [DayPlan]) -> some View {
        let total = plans.reduce(0) { $0 + $1.tasks.count }
        let done = plans.reduce(0) { $0 + $1.doneCount }
        let on = (period ?? "*") == key
        return Button { period = key } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundColor(on ? .white : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(done)/\(total)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(on ? .white.opacity(0.85) : .secondary)
                }
                // 完成进度条
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(on ? Color.white.opacity(0.3) : Color.primary.opacity(0.1))
                        Capsule().fill(on ? Color.white : Color.accentColor.opacity(0.7))
                            .frame(width: total == 0 ? 0 : g.size.width * CGFloat(done) / CGFloat(total))
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右边

    /// 要显示的天和任务（已按状态和搜索过滤）
    private var visible: [(day: DayPlan, tasks: [PlanTask])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return periodDays.compactMap { d in
            let ts = d.tasks.filter { filter.matches($0.status) && (q.isEmpty || $0.title.lowercased().contains(q)) }
            if ts.isEmpty && !(isSingleDay && filter == .all && q.isEmpty) { return nil }
            return (d, ts)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if visible.isEmpty {
                Text(tr("没有符合条件的任务", "No matching tasks"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visible, id: \.day.date) { entry in
                        Section {
                            ForEach(entry.tasks) { t in row(t, day: entry.day.date) }
                            if isSingleDay && filter == .all && search.isEmpty { addRow(day: entry.day.date) }
                        } header: {
                            dayHeader(entry.day)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        let ts = periodDays.flatMap(\.tasks)
        let done = ts.filter { $0.status == .done }.count
        let rate = ts.isEmpty ? 0 : Double(done) / Double(ts.count)
        let periodName = periodKey.isEmpty ? tr("全部时间", "All Time") : periodTitle(periodKey)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(periodName + (filter == .all ? "" : " · " + filter.title))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(filter == .all ? .primary : filter.color)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(tr("搜索任务", "Search tasks"), text: $search)
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            HStack(spacing: 16) {
                stat(tr("完成率", "Completion"), "\(Int((rate * 100).rounded()))%", .primary)
                stat(StatusFilter.done.title, "\(done)", StatusFilter.done.color)
                stat(StatusFilter.doing.title, "\(ts.filter { $0.status == .doing }.count)", StatusFilter.doing.color)
                stat(StatusFilter.todo.title, "\(ts.filter { $0.status == .todo }.count)", StatusFilter.todo.color)
            }
            ProgressView(value: rate).progressViewStyle(.linear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
        }
    }

    private func dayHeader(_ d: DayPlan) -> some View {
        HStack {
            Text(DayClock.display(d.date)).font(.system(size: 13, weight: .semibold))
            if d.date == store.day {
                Text(tr("今天", "Today"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
            }
            Spacer()
            Text("\(d.doneCount)/\(d.tasks.count)").monospacedDigit().foregroundColor(.secondary)
        }
    }

    // MARK: - 一行任务

    private func row(_ t: PlanTask, day: String) -> some View {
        let isToday = day == store.day
        return HStack(spacing: 8) {
            Button { store.updateTask(on: day, id: t.id) { $0.status = $0.status.next } } label: {
                Image(systemName: statusIcon(t.status))
                    .font(.system(size: 16))
                    .foregroundColor(statusTint(t.status))
            }
            .buttonStyle(.plain)
            .help(tr("点击切换：未开始 → 进行中 → 已完成", "Click to change: to do → in progress → done"))

            TextField(tr("任务", "Task"), text: Binding(
                get: { t.title },
                set: { v in store.updateTask(on: day, id: t.id) { $0.title = v } }))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: t.status == .doing ? .semibold : .regular))
                .foregroundColor(t.status == .done ? .secondary : .primary)

            if isToday && t.carriedFrom != nil {
                Button { store.acceptCarried(t.id) } label: { CarriedTag(days: store.carriedDays(t)) }
                    .buttonStyle(.plain)
                    .help(tr("点击变成今天的待办（未开始）", "Click to make it a to-do for today"))
            }

            // 过去没做完的任务：一键加到今天
            if !isToday && t.status != .done {
                if store.isInToday(t.id) {
                    Text(tr("已在今天", "In today"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Button(tr("→ 今天", "→ Today")) { store.copyToToday(from: day, id: t.id) }
                        .controlSize(.small)
                        .help(tr("加到今天，作为未开始的待办", "Add to today as a to-do"))
                }
            }

            Button { store.updateTask(on: day, id: t.id) { $0.repeatDaily.toggle() } } label: {
                Image(systemName: "repeat")
                    .foregroundColor(t.repeatDaily ? .blue : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(tr("每日重复", "Repeat daily"))

            Button { store.removeTask(on: day, id: t.id) } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(tr("删除", "Delete"))
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(tr("标为已完成", "Mark as Done")) { store.updateTask(on: day, id: t.id) { $0.status = .done } }
            Button(tr("标为进行中", "Mark as In Progress")) { store.updateTask(on: day, id: t.id) { $0.status = .doing } }
            Button(tr("标为未开始", "Mark as To Do")) { store.updateTask(on: day, id: t.id) { $0.status = .todo } }
            if !isToday && t.status != .done && !store.isInToday(t.id) {
                Divider()
                Button(tr("加到今天", "Add to Today")) { store.copyToToday(from: day, id: t.id) }
            }
            Divider()
            Button(t.repeatDaily ? tr("取消每日重复", "Stop Repeating") : tr("设为每日重复", "Repeat Daily")) {
                store.updateTask(on: day, id: t.id) { $0.repeatDaily.toggle() }
            }
            Divider()
            Button(tr("删除", "Delete")) { store.removeTask(on: day, id: t.id) }
        }
    }

    private func addRow(day: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundColor(.secondary).font(.system(size: 16))
            TextField(tr("添加任务，回车确认", "Add a task, press Return"), text: $newTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    store.addTask(on: day, title: newTitle)
                    newTitle = ""
                }
        }
        .padding(.vertical, 3)
    }
}

/// 侧栏的毛玻璃背景
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

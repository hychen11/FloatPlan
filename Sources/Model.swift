import Foundation
import Combine

enum TaskStatus: String, Codable {
    case todo, doing, done

    /// 点击状态图标时的循环顺序：未开始 → 进行中 → 已完成 → 未开始
    var next: TaskStatus {
        switch self {
        case .todo: return .doing
        case .doing: return .done
        case .done: return .todo
        }
    }
}

struct PlanTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var status: TaskStatus = .todo
    /// 每日重复：每天自动出现在新清单里，状态重置为未开始
    var repeatDaily = false
    /// 从哪天顺延过来的（最早那天）；nil 表示是今天的正常任务
    var carriedFrom: String?

    init(title: String, status: TaskStatus = .todo, repeatDaily: Bool = false) {
        self.title = title
        self.status = status
        self.repeatDaily = repeatDaily
    }

    enum CodingKeys: String, CodingKey { case id, title, status, repeatDaily, carriedFrom }

    // 兼容旧版数据：缺少的字段用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        repeatDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatDaily) ?? false
        carriedFrom = try c.decodeIfPresent(String.self, forKey: .carriedFrom)
    }
}

/// 某一天的清单
struct DayPlan: Codable, Equatable {
    var date: String          // yyyy-MM-dd
    var tasks: [PlanTask]
    var doneCount: Int { tasks.filter { $0.status == .done }.count }
}

/// 日期工具。“一天从几点开始”可设置，熬夜时清单不会在零点突然换掉
enum DayClock {
    static var startHour: Int {
        get { UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "dayStartHour") }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 某个时刻属于哪一天（扣掉“一天开始的小时数”）
    static func key(for date: Date = Date()) -> String {
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date.addingTimeInterval(TimeInterval(-startHour * 3600)))
    }

    /// 2026.11.20 周五 / 11.20 周五（英文：2026.11.20 Fri）
    static func display(_ key: String, short: Bool = false) -> String {
        guard let d = keyFormatter.date(from: key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.lang == .zh ? "zh_CN" : "en_US")
        f.dateFormat = short ? "M.d EEE" : "yyyy.MM.dd EEE"
        return f.string(from: d)
    }

    /// "2026-11" → 2026年11月 / November 2026
    static func monthTitle(_ month: String) -> String {
        guard let d = keyFormatter.date(from: month + "-01") else { return month }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.lang == .zh ? "zh_CN" : "en_US")
        f.dateFormat = L10n.lang == .zh ? "yyyy年M月" : "MMMM yyyy"
        return f.string(from: d)
    }

    /// 两个日期之间差几天
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = keyFormatter.date(from: a), let db = keyFormatter.date(from: b) else { return 0 }
        return max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: da, to: db).day ?? 0)
    }

    /// "2026" → 2026年 / 2026
    static func yearTitle(_ year: String) -> String {
        L10n.lang == .zh ? "\(year)年" : year
    }
}

/// 任务数据，保存在 ~/Library/Application Support/FloatPlan/plans.json
/// （测试时可用环境变量 FLOATPLAN_DATA_DIR 指定别的目录）
final class TaskStore: ObservableObject {
    /// 今天的任务
    @Published var tasks: [PlanTask] = [] {
        didSet { save() }
    }
    /// 今天是哪一天（yyyy-MM-dd）
    @Published private(set) var day: String
    /// 过去的清单，最新的在前
    @Published private(set) var history: [DayPlan] = []

    /// 切换到新的一天时回调，参数是带过来的任务数
    var onNewDay: ((Int) -> Void)?

    private struct SaveFile: Codable {
        var version = 2
        var today: DayPlan
        var history: [DayPlan]
    }

    private let fileURL: URL
    private static let historyLimit = 365

    init() {
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["FLOATPLAN_DATA_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FloatPlan", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("plans.json")
        let legacyURL = dir.appendingPathComponent("tasks.json")

        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(SaveFile.self, from: data) {
            day = file.today.date
            tasks = file.today.tasks
            history = file.history
        } else if let data = try? Data(contentsOf: legacyURL),
                  let old = try? JSONDecoder().decode([PlanTask].self, from: data) {
            // 从 v0.1 迁移：旧清单变成今天的清单（旧文件保留作备份）
            day = DayClock.key()
            tasks = old
        } else {
            day = DayClock.key()
            // 第一次打开时的示例任务，按当时的语言
            tasks = [
                PlanTask(title: tr("回复邮件", "Reply to emails"), status: .done),
                PlanTask(title: tr("整理会议纪要", "Tidy up meeting notes"), status: .done),
                PlanTask(title: tr("写方案初稿", "Write the first draft"), status: .doing),
                PlanTask(title: tr("跑步 30 分钟", "Run for 30 minutes"), repeatDaily: true),
                PlanTask(title: tr("读书 20 页", "Read 20 pages"), repeatDaily: true),
            ]
        }
        save()
    }

    /// 检查是否到了新的一天；是的话归档昨天，带上未完成和每日重复的任务
    @discardableResult
    func checkNewDay(now: Date = Date()) -> Bool {
        let today = DayClock.key(for: now)
        // 只往前走；改了系统时间或“一天开始时间”导致日期往回时不处理
        guard today > day else { return false }

        if !tasks.isEmpty {
            history.removeAll { $0.date == day }
            history.insert(DayPlan(date: day, tasks: tasks), at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }

        let yesterday = day
        let carried: [PlanTask] = tasks.compactMap { t in
            if t.repeatDaily {
                var n = t
                n.status = .todo
                n.carriedFrom = nil
                return n
            }
            guard t.status != .done else { return nil }   // 完成的不顺延
            var n = t
            n.carriedFrom = t.carriedFrom ?? yesterday      // 进行中、未开始的顺延，记下最早是哪天的
            return n
        }

        day = today
        tasks = carried          // 触发保存
        onNewDay?(carried.filter { $0.carriedFrom != nil }.count)
        return true
    }

    // MARK: 历史窗口用：按日期编辑任意一天

    /// 今天 + 过去，按日期从新到旧
    var allDays: [DayPlan] { [DayPlan(date: day, tasks: tasks)] + history }

    func updateTask(on date: String, id: UUID, _ change: (inout PlanTask) -> Void) {
        if date == day {
            if let i = tasks.firstIndex(where: { $0.id == id }) { change(&tasks[i]) }
            return
        }
        guard let d = history.firstIndex(where: { $0.date == date }),
              let i = history[d].tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&history[d].tasks[i])
        save()
    }

    func removeTask(on date: String, id: UUID) {
        if date == day { remove(id); return }
        guard let d = history.firstIndex(where: { $0.date == date }) else { return }
        history[d].tasks.removeAll { $0.id == id }
        if history[d].tasks.isEmpty { history.remove(at: d) }   // 过去某天删空了就不再显示
        save()
    }

    func addTask(on date: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if date == day { tasks.append(PlanTask(title: t)); return }
        guard let d = history.firstIndex(where: { $0.date == date }) else { return }
        history[d].tasks.append(PlanTask(title: t))
        save()
    }

    /// 顺延任务点一下：变成今天的普通待办（未开始，去掉顺延标记）
    func acceptCarried(_ id: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].carriedFrom = nil
            tasks[i].status = .todo
        }
    }

    /// 某个任务是否已经在今天的清单里（顺延的任务和原任务 id 相同）
    func isInToday(_ id: UUID) -> Bool { tasks.contains { $0.id == id } }

    /// 把过去某天的任务加到今天，作为未开始的待办
    func copyToToday(from date: String, id: UUID) {
        guard date != day, !isInToday(id),
              let d = history.first(where: { $0.date == date }),
              var t = d.tasks.first(where: { $0.id == id }) else { return }
        t.status = .todo
        t.carriedFrom = nil
        tasks.append(t)
    }

    /// 顺延了几天
    func carriedDays(_ t: PlanTask) -> Int {
        guard let from = t.carriedFrom else { return 0 }
        return DayClock.daysBetween(from, day)
    }

    /// 当前任务：第一条“进行中”，没有的话就是第一条“未开始”
    var currentTask: PlanTask? {
        tasks.first { $0.status == .doing } ?? tasks.first { $0.status == .todo }
    }

    var doneCount: Int { tasks.filter { $0.status == .done }.count }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tasks.append(PlanTask(title: t))
    }

    func remove(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func toggleRepeat(_ id: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].repeatDaily.toggle() }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard tasks.indices.contains(j) else { return }
        tasks.swapAt(i, j)
    }

    func removeEmpty() {
        let cleaned = tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if cleaned.count != tasks.count { tasks = cleaned }
    }

    private func save() {
        let file = SaveFile(today: DayPlan(date: day, tasks: tasks), history: history)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// 界面状态 + 偏好设置
final class UIState: ObservableObject {
    @Published var editing = false
    /// 界面语言，切换时界面自动刷新
    @Published var lang: Lang = L10n.lang {
        didSet { L10n.lang = lang }
    }
    @Published var bgOpacity: Double {
        didSet { UserDefaults.standard.set(bgOpacity, forKey: "bgOpacity") }
    }
    /// 文字不透明度（只影响平时的样子，编辑模式始终清晰）
    @Published var textOpacity: Double {
        didSet { UserDefaults.standard.set(textOpacity, forKey: "textOpacity") }
    }
    var toggleEdit: () -> Void = {}

    init() {
        let d = UserDefaults.standard
        bgOpacity = d.object(forKey: "bgOpacity") as? Double ?? 0.35
        textOpacity = d.object(forKey: "textOpacity") as? Double ?? 1.0
    }
}

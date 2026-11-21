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

    init(title: String, status: TaskStatus = .todo, repeatDaily: Bool = false) {
        self.title = title
        self.status = status
        self.repeatDaily = repeatDaily
    }

    enum CodingKeys: String, CodingKey { case id, title, status, repeatDaily }

    // 兼容旧版数据：缺少的字段用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        repeatDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatDaily) ?? false
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

    /// 2026.11.20 周五 / 11.20 周五
    static func display(_ key: String, short: Bool = false) -> String {
        guard let d = keyFormatter.date(from: key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = short ? "M.d EEE" : "yyyy.MM.dd EEE"
        return f.string(from: d)
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
            tasks = [
                PlanTask(title: "回复邮件", status: .done),
                PlanTask(title: "整理会议纪要", status: .done),
                PlanTask(title: "写方案初稿", status: .doing),
                PlanTask(title: "跑步 30 分钟", repeatDaily: true),
                PlanTask(title: "读书 20 页", repeatDaily: true),
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

        let carried: [PlanTask] = tasks.compactMap { t in
            if t.repeatDaily {
                var n = t
                n.status = .todo
                return n
            }
            return t.status == .done ? nil : t
        }

        day = today
        tasks = carried          // 触发保存
        onNewDay?(carried.count)
        return true
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

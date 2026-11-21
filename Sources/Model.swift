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
}

/// 任务数据，保存在 ~/Library/Application Support/FloatPlan/tasks.json
final class TaskStore: ObservableObject {
    @Published var tasks: [PlanTask] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatPlan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([PlanTask].self, from: data) {
            tasks = saved
        } else {
            tasks = [
                PlanTask(title: "回复邮件", status: .done),
                PlanTask(title: "整理会议纪要", status: .done),
                PlanTask(title: "写方案初稿", status: .doing),
                PlanTask(title: "跑步 30 分钟"),
                PlanTask(title: "读书 20 页"),
            ]
            save()
        }
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
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(tasks) {
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

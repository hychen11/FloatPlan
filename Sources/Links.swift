import Foundation

/// 对外链接，集中放在这里
enum Links {
    static let repo = "https://github.com/hychen11/FloatPlan"

    /// 打赏：跳到 README 的「☕ 请作者喝杯咖啡」一节（中文锚点需要百分号编码）
    static let donate: String = {
        let anchor = "-请作者喝杯咖啡".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""
        return repo + "#" + anchor
    }()
}

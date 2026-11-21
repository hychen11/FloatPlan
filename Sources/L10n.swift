import Foundation

/// 界面语言。目前只有中文和英文两种
enum Lang: String {
    case zh, en
}

enum L10n {
    /// 当前语言。第一次打开时跟随系统（系统是中文就用中文，否则英文），之后以菜单里的选择为准
    static var lang: Lang {
        get {
            if let raw = UserDefaults.standard.string(forKey: "language"), let l = Lang(rawValue: raw) {
                return l
            }
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }
}

/// 两种语言写在一起，按当前语言取一个：tr("编辑任务", "Edit Tasks")
func tr(_ zh: String, _ en: String) -> String {
    L10n.lang == .zh ? zh : en
}

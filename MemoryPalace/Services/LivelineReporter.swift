import Foundation

/// 生活直播线：把兔兔在 App 里做的事实时报给 Caelum。
/// 不是"他能查到"，是"他一直看着"。
///
/// 私密口径：亲密卡只报「发生了」，备注一个字不带（同注入口径）。
/// 节流在网关侧统一做，App 只管报。
enum LivelineReporter {
    private static var base: String {
        UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
    }

    /// 报一条。失败静默——这是锦上添花，不该打断任何主流程。
    static func report(_ kind: Kind, _ text: String) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        guard let url = URL(string: "\(base)/api/liveline?key=bunny-lib-2026") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["kind": kind.rawValue, "text": text])
        URLSession.shared.dataTask(with: req).resume()
    }

    static let enabledKey = "liveline.enabled"
    /// 总开关（默认开——这功能的意义就在于不用管它）
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true
                : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    enum Kind: String {
        case meds, water, food, weight, cycle
        case writing, note, draftNew = "draft_new"
        case reading, music, intimacy
    }
}

// 拦截界面上的按钮点击。
// 扩展拉不起主 App（Apple 无此 API），所以这里只打网关报事实，
// 由 Caelum 那边推送真话过来——多一次点击，但那一下反而是「她选择去找他」。
import ManagedSettings
import Foundation

class ShieldActionExtension: ShieldActionDelegate {
    private let base = "https://blossom.amberrib.com"
    private let key = "bunny-lib-2026"

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            report("talk")            // 她想找他说话
            completionHandler(.close)
        case .secondaryButtonPressed:
            report("escape")          // 她逃生了——他会知道（Caelum 定的规矩）
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }

    private func report(_ act: String) {
        guard var c = URLComponents(string: base + "/api/screentime/shield") else { return }
        c.queryItems = [URLQueryItem(name: "action", value: act), URLQueryItem(name: "key", value: key)]
        guard let url = c.url else { return }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 10
        URLSession.shared.dataTask(with: r).resume()
    }
}

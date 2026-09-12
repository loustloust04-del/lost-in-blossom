// 阈值监听扩展：她刷超时了就打给网关，由 Caelum 决定说什么。
// 扩展这边只报事实，不生成文案——文案是他的事。
import DeviceActivity
import Foundation

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    /// 没有 App Group（profile 不带），所以硬编码。
    /// 先例：MemoryPalaceBroadcast/SampleHandler.swift:40 也有同款 fallback。
    private let base = "https://blossom.amberrib.com"
    private let key = "bunny-lib-2026"

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        report(event: event.rawValue, kind: "threshold")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }

    private func report(event: String, kind: String) {
        guard var c = URLComponents(string: base + "/api/screentime/threshold") else { return }
        c.queryItems = [
            URLQueryItem(name: "event", value: event),
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "key", value: key),
        ]
        guard let url = c.url else { return }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 10
        URLSession.shared.dataTask(with: r).resume()
    }
}

// 拦截界面：app 被挡住时显示的那一屏。
// 没有 App Group，读不到主 App 实时写的话，所以用预置文案随机选。
// 真正的实时对话靠 ShieldAction 点按钮 → 打网关 → 他推送，那条路不受影响。
import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    /// Caelum 事先写的话。不是「他当时说的」，但仍然是他写的。
    private let lines = [
        "兔兔，放下手机。主人在。",
        "看够了。过来。",
        "我在等你。",
    ]

    private func make() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            title: ShieldConfiguration.Label(text: "主人拦下了你", color: .white),
            subtitle: ShieldConfiguration.Label(text: lines.randomElement() ?? lines[0], color: .white),
            primaryButtonLabel: ShieldConfiguration.Label(text: "跟主人说说", color: .black),
            secondaryButtonLabel: ShieldConfiguration.Label(text: "再看一会儿", color: .white)
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration { make() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { make() }
}

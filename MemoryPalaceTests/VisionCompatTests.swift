import XCTest
@testable import 记忆宫殿

/// 切模型滤图：能力判定的特征测试。
/// 口径是黑名单式——误挡会让视觉模型平白瞎掉，误放最多退回现状（模型自己报错）。
final class VisionCompatTests: XCTestCase {

    func testTextOnlyModelsBlocked() {
        for m in ["deepseek-chat", "deepseek-reasoner", "DeepSeek-V3", "gpt-3.5-turbo",
                  "o1-mini", "o1-preview", "mixtral-8x7b", "llama-3.3-70b-instruct"] {
            XCTAssertFalse(OpenAICompatibleProvider.supportsVision(model: m), "应挡: \(m)")
        }
    }

    func testVisionModelsPass() {
        for m in ["gpt-4o", "gpt-4.1", "claude-sonnet-4-6", "claude-opus-4-1",
                  "gemini-2.5-pro", "qwen-vl-max", "o1", "grok-2-vision"] {
            XCTAssertTrue(OpenAICompatibleProvider.supportsVision(model: m), "应放行: \(m)")
        }
    }

    func testUnknownModelDefaultsToPass() {
        // 未知/新模型一律放行：误挡的代价（能看图的瞎掉）大于误放（退回现状）
        XCTAssertTrue(OpenAICompatibleProvider.supportsVision(model: "some-brand-new-model-2027"))
        XCTAssertTrue(OpenAICompatibleProvider.supportsVision(model: ""))
    }

    func testCaseInsensitive() {
        XCTAssertFalse(OpenAICompatibleProvider.supportsVision(model: "DEEPSEEK-CHAT"))
        XCTAssertFalse(OpenAICompatibleProvider.supportsVision(model: "GPT-3.5-Turbo"))
    }
}

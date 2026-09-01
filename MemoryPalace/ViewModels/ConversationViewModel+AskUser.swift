import Foundation
import SwiftUI

// MARK: - 选择卡（ask_user）状态机
//
// 2026-08-24 自粟粟 ask-user 线搬入骨架（她 08-04 做的，对齐官端 AskUserQuestion）。
//
// 设计要点：**双源，UI 无感**。
// 题面/答案/收卡/关卡四个接口对 sheet 只暴露一套，内部按挂起源分流：
//   · API 通路（pendingUserQuestion）——模型调 ask_user 工具，工具循环停在本轮，
//     答完走 tool_result 回灌继续跑。恢复参数必须整轮打包，见下面结构体。
//   · CC 桥通路（pendingCCQuestion）——hub 推来的题面，答案发 WS 帧回去驱动 tmux TUI。
//     无恢复参数：CC 那边自己在等按键，我们只负责把下标送回去。
//
// 兔兔主要用 CC，所以 CC 通路才是她日常真正会碰到的那条；
// 但两条共用这一层，先立起来 API 侧才有地基接 CC。
// MARK: - 挂起态

/// API 选择卡：模型调 ask_user 工具，ToolCallLoop 挂起在 AskUserGate 等答案。
/// 无恢复参数——循环上下文在挂起的 continuation 里原地活着（AskUserGate 详注）。
struct PendingAPIQuestion {
    let questions: [AskUserTool.ParsedQuestion]
    var collectedAnswers: [AskUserTool.AnswerValue?]

    init(questions: [AskUserTool.ParsedQuestion]) {
        self.questions = questions
        self.collectedAnswers = Array(repeating: nil, count: questions.count)
    }
}

/// CC 桥选择卡：hub 推来的 AskUserQuestion 题面。
/// 无恢复参数——CC 那头自己在 tmux 里等按键，我们只负责把选中的下标送回去。
struct PendingCCQuestion {
    let chatId: String
    let toolUseId: String
    let questions: [AskUserTool.ParsedQuestion]
    /// 与 questions 按下标对齐；nil = 跳过
    var collectedAnswers: [AskUserTool.AnswerValue?]

    init(chatId: String, toolUseId: String, questions: [AskUserTool.ParsedQuestion]) {
        self.chatId = chatId
        self.toolUseId = toolUseId
        self.questions = questions
        self.collectedAnswers = Array(repeating: nil, count: questions.count)
    }
}

extension ConversationViewModel {

    /// sheet 的统一题面源。API 优先——两边同时挂起时 API 卡先出，CC 卡排队等它收。
    var activeAskQuestions: [AskUserTool.ParsedQuestion]? {
        pendingAPIQuestion?.questions ?? pendingCCQuestion?.questions
    }

    /// sheet 记录单题答案。index 跨题面平铺按序对齐。
    @MainActor
    func recordUserAnswer(_ answer: AskUserTool.AnswerValue?, at index: Int) {
        if pendingAPIQuestion != nil {
            guard pendingAPIQuestion?.collectedAnswers.indices.contains(index) == true else { return }
            pendingAPIQuestion?.collectedAnswers[index] = answer
            return
        }
        guard pendingCCQuestion?.collectedAnswers.indices.contains(index) == true else { return }
        pendingCCQuestion?.collectedAnswers[index] = answer
    }

    /// 全部答完的出口：答案帧回 hub → 驱动 tmux TUI 键序。
    @MainActor
    func completeActiveAskCard() {
        if let api = pendingAPIQuestion {
            pendingAPIQuestion = nil
            let answers = zip(api.questions, api.collectedAnswers).map { q, v in
                v?.displayString(options: q.options)
            }
            AskUserGate.shared.resolve(answers)
            return
        }
        guard let cc = pendingCCQuestion else { return }
        pendingCCQuestion = nil
        // 用下标而非文本——CC 那头是方向键+回车选的，要的是位置不是内容。
        let answers: [[String: Any]] = cc.collectedAnswers.map { v in
            switch v {
            case .options(let idxs): return ["indices": idxs]
            case .text(let s):       return ["text": s]
            case nil:                return [:]   // 正常不出现；hub 侧有校验兜底
            }
        }
        CCBridgeWebSocketClient.shared.sendAskUserAnswer(toolUseId: cc.toolUseId, answers: answers)
    }

    /// sheet 的 X / 下拽提前关。CC 侧是「整卡跳过」发 Esc——
    /// 不是「把没答的按跳过、已答的保留」，TUI 语义只支持整卡撤销。
    /// 必须回这一帧，否则 tmux 那头会一直等按键。
    @MainActor
    func dismissActiveAskCard() {
        if let api = pendingAPIQuestion {
            // API 侧语义（方案 a）：已答的保留、没答的按跳过回灌
            pendingAPIQuestion = nil
            let answers = zip(api.questions, api.collectedAnswers).map { q, v in
                v?.displayString(options: q.options)
            }
            AskUserGate.shared.resolve(answers)
            return
        }
        guard let cc = pendingCCQuestion else { return }
        pendingCCQuestion = nil
        CCBridgeWebSocketClient.shared.sendAskUserAnswer(toolUseId: cc.toolUseId, answers: nil, skip: true)
    }
}

// （2026-08-31 API 通路已接：ToolCallLoop 认出 ask_user → AskUserGate 挂起 continuation
// 等 sheet 答案——循环上下文原地活着，不需要下面设想的整轮恢复参数打包。TODO 留档：）
// 原 TODO(ask-user API 侧)：API 通路的暂停/恢复。
// 需要在 provider 的工具循环里认出 ask_user 调用后中断本轮，
// 把整轮恢复参数打包进 PendingUserQuestion（messages/systemPrompt/sampling/
// assistantNode/preset/toolTurns/round/calls/otherResults...），
// 用户答完再原样接着跑，答案走 tool_result 回灌。
// 粟粟的实现在 ConversationViewModel.swift:1480-1620，结构可参照。
// 兔兔主要用 CC，故本刀先通 CC 侧；API 侧另起一刀。

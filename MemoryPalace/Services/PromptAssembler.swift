import Foundation

// MARK: - Prompt Assembler

struct PromptAssembler {

    /// 组装最终发给 API 的 system prompt + messages
    ///
    /// 逻辑：
    /// 1. 遍历 preset.prompts，按 injectionOrder 排序
    /// 2. 跳过 isEnabled=false 的插槽
    /// 3. marker 插槽用 profile/memories/history 填充
    /// 4. 世界书关键词扫描 + 按 position 注入
    /// 5. injectionDepth > 0 的插槽插入到对话历史指定位置
    /// 6. role=system 拼成 system prompt；role=user/assistant 插入 messages
    static func assemble(
        preset: Preset,
        profile: Profile,
        memories: [Memory],
        chatHistory: [(role: String, content: String)],
        worldBooks: [WorldBook] = [],
        globalEntries: [WorldBookEntry] = [],
        contextSummary: String? = nil
    ) -> (systemPrompt: String?, messages: [(role: String, content: String)]) {

        let contextDepth = preset.sampling.contextDepth
        let trimmedHistory = chatHistory.count > contextDepth
            ? Array(chatHistory.suffix(contextDepth))
            : chatHistory

        // 按 injectionOrder 排序，过滤禁用的
        let activeSlots = preset.prompts
            .filter { $0.isEnabled || $0.isSystemPrompt }
            .sorted { $0.injectionOrder < $1.injectionOrder }

        // tagged system parts：追踪每个 part 的来源 slot id，世界书需要按 position 插入
        var systemParts: [(tag: String, content: String)] = []
        var preHistoryMessages: [(role: String, content: String)] = []
        var postHistoryInjections: [(depth: Int, role: String, content: String)] = []

        for slot in activeSlots {
            let content = resolveSlotContent(
                slot, profile: profile, preset: preset,
                memories: memories, chatHistory: trimmedHistory
            )

            // chatHistory marker 特殊处理：不拼到 system prompt
            if slot.isMarker && slot.id == PromptSlot.chatHistoryId {
                continue
            }

            // dialogueExamples marker：解析为 messages
            if slot.isMarker && slot.id == PromptSlot.dialogueExamplesId {
                if let examples = content {
                    // 标记对话示例位置，方便世界书 beforeExamples/afterExamples 插入
                    preHistoryMessages.append((role: "_examples_marker_", content: ""))
                    preHistoryMessages += parseChatExamples(examples, profile: profile)
                    preHistoryMessages.append((role: "_examples_end_marker_", content: ""))
                }
                continue
            }

            guard let resolved = content, !resolved.isEmpty else { continue }

            // injection_depth > 0：插入到对话历史指定深度
            if slot.injectionDepth > 0 {
                postHistoryInjections.append((depth: slot.injectionDepth, role: slot.role, content: resolved))
                continue
            }

            // role=system 拼到 system prompt（带 tag）
            if slot.role == "system" {
                systemParts.append((tag: slot.id, content: resolved))
            } else {
                preHistoryMessages.append((role: slot.role, content: resolved))
            }
        }

        // ── 世界书注入 ──
        if !worldBooks.isEmpty || !globalEntries.isEmpty {
            let recentTexts = trimmedHistory.map { $0.content }
            let resolved = WorldBookScanner.scan(
                worldBooks: worldBooks,
                recentMessages: recentTexts,
                profile: profile,
                globalEntries: globalEntries
            )

            for entry in resolved {
                switch entry.position {
                case .beforeCharDef:
                    // 插到 charDescriptionId 之前
                    if let idx = systemParts.firstIndex(where: { $0.tag == PromptSlot.charDescriptionId }) {
                        systemParts.insert((tag: "wb", content: entry.content), at: idx)
                    } else {
                        systemParts.append((tag: "wb", content: entry.content))
                    }

                case .afterCharDef:
                    // 插到 charDescriptionId 之后
                    if let idx = systemParts.firstIndex(where: { $0.tag == PromptSlot.charDescriptionId }) {
                        systemParts.insert((tag: "wb", content: entry.content), at: systemParts.index(after: idx))
                    } else {
                        systemParts.append((tag: "wb", content: entry.content))
                    }

                case .beforeExamples:
                    // 插到对话示例 marker 之前
                    if let idx = preHistoryMessages.firstIndex(where: { $0.role == "_examples_marker_" }) {
                        preHistoryMessages.insert((role: entry.role, content: entry.content), at: idx)
                    } else {
                        preHistoryMessages.append((role: entry.role, content: entry.content))
                    }

                case .afterExamples:
                    // 插到对话示例 end marker 之后
                    if let idx = preHistoryMessages.firstIndex(where: { $0.role == "_examples_end_marker_" }) {
                        preHistoryMessages.insert((role: entry.role, content: entry.content), at: preHistoryMessages.index(after: idx))
                    } else {
                        preHistoryMessages.append((role: entry.role, content: entry.content))
                    }

                case .atDepth:
                    postHistoryInjections.append((depth: entry.depth, role: entry.role, content: entry.content))

                case .authorNoteTop:
                    // jailbreak 之前
                    if let idx = systemParts.firstIndex(where: { $0.tag == PromptSlot.jailbreakId }) {
                        systemParts.insert((tag: "wb", content: entry.content), at: idx)
                    } else {
                        systemParts.append((tag: "wb", content: entry.content))
                    }

                case .authorNoteBot:
                    // jailbreak 之后
                    if let idx = systemParts.firstIndex(where: { $0.tag == PromptSlot.jailbreakId }) {
                        systemParts.insert((tag: "wb", content: entry.content), at: systemParts.index(after: idx))
                    } else {
                        systemParts.append((tag: "wb", content: entry.content))
                    }
                }
            }
        }

        // 清理 marker 占位符
        preHistoryMessages.removeAll { $0.role == "_examples_marker_" || $0.role == "_examples_end_marker_" }

        // 上下文摘要注入（记忆之后、对话历史之前）
        if let summary = contextSummary, !summary.isEmpty {
            systemParts.append((tag: "contextSummary", content: "[对话历史摘要]\n\(summary)"))
        }

        let systemPrompt = systemParts.isEmpty ? nil : systemParts.map(\.content).joined(separator: "\n\n")

        // 组装 messages：pre-history + chat history + injections at depth
        var messages = preHistoryMessages + trimmedHistory

        // 插入 injection_depth > 0 的内容
        for injection in postHistoryInjections.sorted(by: { $0.depth > $1.depth }) {
            let insertIndex = max(0, messages.count - injection.depth)
            messages.insert((role: injection.role, content: injection.content), at: insertIndex)
        }

        return (systemPrompt: systemPrompt, messages: messages)
    }

    /// 生成完整 prompt 预览（raw view 用）
    static func preview(
        preset: Preset,
        profile: Profile,
        memories: [Memory],
        chatHistory: [(role: String, content: String)] = [],
        worldBooks: [WorldBook] = [],
        contextSummary: String? = nil
    ) -> String {
        let result = assemble(preset: preset, profile: profile, memories: memories, chatHistory: chatHistory, worldBooks: worldBooks, contextSummary: contextSummary)

        var lines: [String] = []

        if let sys = result.systemPrompt {
            lines.append("═══ SYSTEM ═══")
            lines.append(sys)
            lines.append("")
        }

        for msg in result.messages {
            let label = msg.role.uppercased()
            lines.append("─── \(label) ───")
            lines.append(msg.content)
            lines.append("")
        }

        if chatHistory.isEmpty {
            lines.append("─── (对话历史将在这里，当前深度: \(preset.sampling.contextDepth) 条) ───")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// 解析插槽内容：
    /// - 普通插槽用自身 content
    /// - marker 插槽：如果自身有 content 优先用（导入的预设），否则 fallback 到 profile 数据
    private static func resolveSlotContent(
        _ slot: PromptSlot,
        profile: Profile,
        preset: Preset,
        memories: [Memory],
        chatHistory: [(role: String, content: String)]
    ) -> String? {
        guard slot.isMarker else {
            return applyMacros(slot.content, profile: profile)
        }

        // Marker 但自身有内容（如导入的酒馆预设）→ 优先用自身 content
        if !slot.content.isEmpty {
            switch slot.id {
            case PromptSlot.chatHistoryId:
                return nil // 对话历史永远不拼到 system prompt
            case PromptSlot.memoryInjectionId:
                break // 记忆始终动态生成
            default:
                return applyMacros(slot.content, profile: profile)
            }
        }

        // Marker fallback：从 profile 数据填充
        switch slot.id {
        case PromptSlot.mainId:
            return profile.systemPrompt.isEmpty ? nil : applyMacros(profile.systemPrompt, profile: profile)

        case PromptSlot.personaDescriptionId:
            guard !profile.userPersona.isEmpty else { return nil }
            let formatted = preset.personaFormat
                .replacingOccurrences(of: "{{persona}}", with: profile.userPersona)
            return applyMacros(formatted, profile: profile)

        case PromptSlot.charDescriptionId:
            guard !profile.characterDescription.isEmpty else { return nil }
            let formatted = preset.characterFormat
                .replacingOccurrences(of: "{{description}}", with: profile.characterDescription)
                .replacingOccurrences(of: "{{personality}}", with: profile.characterPersonality)
            return applyMacros(formatted, profile: profile)

        case PromptSlot.charPersonalityId:
            return nil

        case PromptSlot.scenarioId:
            guard !profile.scenario.isEmpty else { return nil }
            let formatted = preset.scenarioFormat
                .replacingOccurrences(of: "{{scenario}}", with: profile.scenario)
            return applyMacros(formatted, profile: profile)

        case PromptSlot.memoryInjectionId:
            let injection = MemoryInjector.buildInjection(memories: memories)
            return injection.isEmpty ? nil : "[关于用户]\n\(injection)"

        case PromptSlot.dialogueExamplesId:
            return profile.chatExamples.isEmpty ? nil : profile.chatExamples

        case PromptSlot.chatHistoryId:
            return nil

        default:
            return nil
        }
    }

    /// 宏替换：{{user}} / {{char}}
    private static func applyMacros(_ text: String, profile: Profile) -> String {
        MacroExpander.expand(text, userName: profile.userName, charName: profile.assistantName)
    }

    /// 解析对话示例为 user/assistant 消息对
    ///
    /// 格式支持：
    /// - `{{user}}: 内容` / `{{char}}: 内容`
    /// - `用户: 内容` / `AI: 内容`
    /// - `<START>` 分隔符（忽略）
    private static func parseChatExamples(_ text: String, profile: Profile) -> [(role: String, content: String)] {
        let lines = text.components(separatedBy: "\n")
        var messages: [(role: String, content: String)] = []

        let userPrefixes = ["{{user}}:", "\(profile.userName):", "用户:"]
        let charPrefixes = ["{{char}}:", "\(profile.assistantName):", "AI:"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "<START>" || trimmed.hasPrefix("[Start") { continue }

            var matched = false
            for prefix in userPrefixes {
                if trimmed.hasPrefix(prefix) {
                    let content = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty { messages.append((role: "user", content: content)) }
                    matched = true
                    break
                }
            }
            if matched { continue }

            for prefix in charPrefixes {
                if trimmed.hasPrefix(prefix) {
                    let content = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty { messages.append((role: "assistant", content: content)) }
                    matched = true
                    break
                }
            }
        }

        return messages
    }
}

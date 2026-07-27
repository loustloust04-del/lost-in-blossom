import XCTest
import SwiftData
@testable import 记忆宫殿

/// 亲密卡接线特征测试：store toggle/upsert 语义 / 注入口径（闸默认关+只报当天+note 不注）
/// / writer 落库+结果行不复述 / chatEntryHint 闸门。
final class HealthIntimacyTests: XCTestCase {

    let pid = "xctest-intimacy"
    var container: ModelContainer!
    var context: ModelContext!

    private let gateKeys = [
        HealthLogStore.weightGateKey, HealthLogStore.medsGateKey,
        HealthLogStore.cycleGateKey, HealthLogStore.intimacyGateKey,
        HealthLogStore.intimacyShowKey,
    ]

    override func setUp() {
        super.setUp()
        container = try! ModelContainer(
            for: ProfileManager.fullSchema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        gateKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        gateKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        container = nil
        super.tearDown()
    }

    private func yesterday(_ now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: now)!
    }

    // MARK: - Store

    func testToggleTodayRecordAndCancel() {
        XCTAssertTrue(HealthLogStore.toggleIntimacyToday(context: context, profileId: pid))
        XCTAssertNotNil(HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date()))
        XCTAssertFalse(HealthLogStore.toggleIntimacyToday(context: context, profileId: pid))
        XCTAssertNil(HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date()))
    }

    func testUpsertNoteSemantics() {
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: Date(), note: "第一笔")
        // note 传 nil = 不动已有备注
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: Date(), note: nil)
        XCTAssertEqual(HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date())?.note, "第一笔")
        // 非 nil = 覆盖；且一天仍只一条
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: Date(), note: "改了")
        XCTAssertEqual(HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date())?.note, "改了")
        let all = try! context.fetch(FetchDescriptor<IntimacyEntry>(
            predicate: #Predicate { $0.profileId == "xctest-intimacy" }))
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - 注入口径

    func testInjectionGateDefaultOff() {
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: Date(), note: "私密")
        let s = HealthLogStore.composedHealthSummary(context: context, profileId: pid)
        XCTAssertFalse(s.contains("亲密"), "闸默认关：今天有记录也一字不注")
    }

    func testInjectionOnlyTodayAndNoNote() {
        HealthLogStore.intimacyGateEnabled = true
        // 负向锚：闸开、昨天有今天没有 = 空
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: yesterday(), note: "昨天的")
        var s = HealthLogStore.composedHealthSummary(context: context, profileId: pid)
        XCTAssertFalse(s.contains("亲密"))
        // 今天有 = 只报一句，note 永不注入
        HealthLogStore.upsertIntimacy(context: context, profileId: pid, date: Date(), note: "绝密备注")
        s = HealthLogStore.composedHealthSummary(context: context, profileId: pid)
        XCTAssertTrue(s.contains("今天有亲密记录"))
        XCTAssertFalse(s.contains("绝密备注"))
    }

    // MARK: - Writer（```health-log 块 → 落库 → 结果行）

    private func makeAssistantNode(_ content: String) -> MessageNode {
        let node = MessageNode(
            id: UUID().uuidString, role: "assistant", content: content, contentType: "text",
            createTime: Date(), parentId: nil, childrenIds: [], conversationId: "c-test",
            profileId: pid
        )
        context.insert(node)
        try? context.save()
        return node
    }

    func testWriterIntimacyBlockLandsAndDoesNotEcho() {
        let node = makeAssistantNode(
            "好的～\n```health-log\n{\"type\": \"intimacy\", \"note\": \"绝密内容\"}\n```\n记好了"
        )
        HealthLogIntentWriter.processChatIntents(nodeId: node.id, context: context)
        // 落库：今天一条，note 进库
        let entry = HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date())
        XCTAssertEqual(entry?.note, "绝密内容")
        // 块变结果行：不复述 note、不残留块
        XCTAssertTrue(node.content.contains("♥ 已记下了"))
        XCTAssertFalse(node.content.contains("绝密内容"), "结果行不复述内容")
        XCTAssertFalse(node.content.contains("```health-log"))
    }

    func testWriterRejectsFutureDate() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let future = f.string(from: Calendar.current.date(byAdding: .day, value: 3, to: Date())!)
        let node = makeAssistantNode(
            "```health-log\n{\"type\": \"intimacy\", \"date\": \"\(future)\"}\n```"
        )
        HealthLogIntentWriter.processChatIntents(nodeId: node.id, context: context)
        XCTAssertNil(HealthLogStore.fetchIntimacy(context: context, profileId: pid, date: Date()))
        XCTAssertTrue(node.content.contains("未来的日期记不了"))
    }

    // MARK: - chatEntryHint 闸门

    func testChatEntryHintGates() {
        // 全闸关/无数据 = 一字不注
        HealthLogStore.medsGateEnabled = false
        XCTAssertEqual(HealthLogStore.chatEntryHint(context: context, profileId: pid), "")
        // 亲密闸单开 = 教 intimacy，且不教别家
        HealthLogStore.intimacyGateEnabled = true
        let hint = HealthLogStore.chatEntryHint(context: context, profileId: pid)
        XCTAssertTrue(hint.contains("health-log"))
        XCTAssertTrue(hint.contains("intimacy"))
        XCTAssertFalse(hint.contains("月经打点"))
    }
}

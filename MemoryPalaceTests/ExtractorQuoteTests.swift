import XCTest
import SwiftData
@testable import 记忆宫殿

/// SC-B2 提取器改造特征测试：quote 机械校验 / 解析带 quote / supersede 软失效 / 钉住保护。
final class ExtractorQuoteTests: XCTestCase {

    let pid = "xctest-extractor"
    var container: ModelContainer!
    var context: ModelContext!
    let store = SwiftDataMemoryStore()

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Memory.self, configurations: config)
        context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: "mem_supersede_soft")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "mem_supersede_soft")
        container = nil
        super.tearDown()
    }

    private var window: [(id: String, role: String, content: String)] {
        [
            (id: "n1", role: "user", content: "我最近养了一只橘猫，名字叫年糕，特别黏人"),
            (id: "n2", role: "assistant", content: "年糕这个名字好可爱！"),
            (id: "n3", role: "user", content: "对了我下个月要搬去杭州工作了"),
        ]
    }

    private var windowText: String { window.map(\.content).joined(separator: "\n") }

    // MARK: - 机械校验纯函数

    func testValidQuotePasses() {
        XCTAssertTrue(MemoryExtractor.validateQuote("养了一只橘猫，名字叫年糕", windowText: windowText))
    }

    func testWhitespaceDifferenceStillPasses() {
        // norm 去空白后匹配（模型常吐多余空格）
        XCTAssertTrue(MemoryExtractor.validateQuote("养了一只橘猫， 名字叫 年糕", windowText: windowText))
    }

    func testTooShortQuoteRejected() {
        XCTAssertFalse(MemoryExtractor.validateQuote("橘猫年糕", windowText: windowText), "norm 后 <8 字拒绝")
    }

    func testParaphrasedQuoteRejected() {
        XCTAssertFalse(MemoryExtractor.validateQuote("用户养了一只叫年糕的橘色猫咪", windowText: windowText), "改写不是逐字，拒绝")
    }

    func testNilQuoteRejected() {
        XCTAssertFalse(MemoryExtractor.validateQuote(nil, windowText: windowText))
    }

    func testLocateQuoteFindsMessage() {
        XCTAssertEqual(MemoryExtractor.locateQuote("下个月要搬去杭州", in: window), "n3")
        XCTAssertNil(MemoryExtractor.locateQuote("完全不存在的话", in: window))
    }

    // MARK: - 解析带 quote

    func testParseActionsReadsQuote() {
        let json = """
        {"actions": [
          {"type": "add", "content": "用户养了橘猫年糕", "category": "fact", "keywords": ["猫"], "quote": "养了一只橘猫，名字叫年糕"},
          {"type": "add", "content": "无出处条目", "category": "fact", "keywords": []}
        ]}
        """
        let actions = MemoryExtractor.parseActions(json)
        XCTAssertEqual(actions.count, 2)
        if case .add(_, _, _, let quote) = actions[0] {
            XCTAssertEqual(quote, "养了一只橘猫，名字叫年糕")
        } else { XCTFail("第一条应为 add") }
        if case .add(_, _, _, let quote) = actions[1] {
            XCTAssertNil(quote)
        } else { XCTFail("第二条应为 add") }
    }

    // MARK: - executeActions：quote 拦截与锚定

    func testAddWithoutValidQuoteBlocked() throws {
        let actions: [MemoryAction] = [
            .add(content: "无出处的记忆", category: "fact", keywords: [], quote: nil),
            .add(content: "改写出处的记忆", category: "fact", keywords: [], quote: "完全编造的引用内容啊"),
        ]
        try MemoryExtractor.executeActions(actions, store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: nil,
                                           recentMessages: window, context: context)
        XCTAssertEqual(store.listAll(profileId: pid, context: context).count, 0, "quoteRequiredForAdd=true 时无效 quote 整条拦截")
    }

    func testAddWithValidQuoteStoresAnchor() throws {
        let actions: [MemoryAction] = [
            .add(content: "用户要搬去杭州工作", category: "context", keywords: ["杭州"], quote: "下个月要搬去杭州工作"),
        ]
        try MemoryExtractor.executeActions(actions, store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: "conv1",
                                           recentMessages: window, context: context)
        let all = store.listAll(profileId: pid, context: context)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].sourceQuote, "下个月要搬去杭州工作")
        XCTAssertEqual(all[0].sourceNodeId, "n3")
    }

    // MARK: - supersede 软失效

    func testDeleteBecomesSupersedeWhenFlagOn() throws {
        let mem = try store.add(content: "用户喝乌龙茶", category: "preference", keywords: [],
                                profileId: pid, isUserExplicit: false, extractedBy: "test",
                                sourceConversationId: nil, context: context)
        try MemoryExtractor.executeActions([.delete(id: mem.id)], store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: nil,
                                           recentMessages: [], context: context)
        let all = store.listAll(profileId: pid, context: context)
        XCTAssertEqual(all.count, 1, "软失效：出排名不出库")
        XCTAssertNotNil(all[0].supersededAt)
        XCTAssertTrue(store.listHot(profileId: pid, context: context).isEmpty, "listHot 过滤已失效")
        XCTAssertTrue(store.listHotAndWarm(profileId: pid, context: context).isEmpty, "listHotAndWarm 过滤已失效")
    }

    func testDeleteIsPhysicalWhenFlagOff() throws {
        UserDefaults.standard.set(false, forKey: "mem_supersede_soft")
        let mem = try store.add(content: "用户喝乌龙茶", category: "preference", keywords: [],
                                profileId: pid, isUserExplicit: false, extractedBy: "test",
                                sourceConversationId: nil, context: context)
        try MemoryExtractor.executeActions([.delete(id: mem.id)], store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: nil,
                                           recentMessages: [], context: context)
        XCTAssertTrue(store.listAll(profileId: pid, context: context).isEmpty, "开关关 = 物理删除（现状行为）")
    }

    func testPinnedMemoryRefusesSupersedeAndDelete() throws {
        let mem = try store.add(content: "钉住的重要记忆", category: "fact", keywords: [],
                                profileId: pid, isUserExplicit: true, extractedBy: "test",
                                sourceConversationId: nil, context: context)
        // 软模式
        try MemoryExtractor.executeActions([.delete(id: mem.id)], store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: nil,
                                           recentMessages: [], context: context)
        XCTAssertNil(store.listAll(profileId: pid, context: context).first?.supersededAt, "钉住拒失效")
        // 硬模式
        UserDefaults.standard.set(false, forKey: "mem_supersede_soft")
        try MemoryExtractor.executeActions([.delete(id: mem.id)], store: store, profileId: pid,
                                           extractedBy: "test", sourceConversationId: nil,
                                           recentMessages: [], context: context)
        XCTAssertEqual(store.listAll(profileId: pid, context: context).count, 1, "钉住拒物理删除")
    }

    func testSupersededExcludedFromExtractorCandidates() throws {
        // 已失效不再喂提取器（listHotAndWarm 是提取器的"当前记忆"来源），防反复 delete 同一条
        let mem = try store.add(content: "旧偏好", category: "preference", keywords: [],
                                profileId: pid, isUserExplicit: false, extractedBy: "test",
                                sourceConversationId: nil, context: context)
        try store.supersede(id: mem.id, context: context)
        XCTAssertTrue(store.listHotAndWarm(profileId: pid, context: context).isEmpty)
    }

    // MARK: - update 出处语义

    func testUpdateKeepsQuoteWhenNoNewQuote() throws {
        let mem = try store.add(content: "旧内容", category: "fact", keywords: [],
                                profileId: pid, isUserExplicit: false, extractedBy: "test",
                                sourceConversationId: nil, sourceQuote: "原始出处引用片段啊", sourceNodeId: "n9",
                                context: context)
        try MemoryExtractor.executeActions(
            [.update(id: mem.id, content: "新内容", keywords: [], quote: nil)],
            store: store, profileId: pid, extractedBy: "test", sourceConversationId: nil,
            recentMessages: window, context: context)
        let m = store.listAll(profileId: pid, context: context)[0]
        XCTAssertEqual(m.content, "新内容")
        XCTAssertEqual(m.sourceQuote, "原始出处引用片段啊", "无新 quote 时保留原始出处")
        XCTAssertEqual(m.sourceNodeId, "n9")
    }
}

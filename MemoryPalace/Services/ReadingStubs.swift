import Foundation
import SwiftData
import PDFKit

// MARK: - 共读系统 no-op 替身（TASK-READER：本次只搬「能看书」）
// 批注抽屉 / 问 AI / 在场信号 / 生词本 / OCR 划词的真身后续从粟粟单独搬，
// 届时删掉本文件、恢复 BookReaderSheet 里注释掉的 UI 入口即可。
// 这些替身让阅读器核心（书架/翻章/进度/书签/笔记/高亮）不用大改保持原结构。

/// 在场信号（共读心跳/事件上报）——替身：静默丢弃
enum ReadingSignals {
    static func logTick(bookSafeName: String, bookDisplayName: String, chapter: Int, profileId: String) {}
    static func logEvent(type: String, book: String, chapter: Int, word: String? = nil, profileId: String) {}
    static func buildPersonaPackage(profile: Profile, context: ModelContext) -> String { "" }
}

/// 生词本——替身：不收集、无已收词（阅读器里生词虚线不出现）
enum VocabCollector {
    static func collectedWords(context: ModelContext) -> [String] { [] }
    static func collect(rawText: String, bookSafeName: String, chapter: Int, anchorStart: Int, context: ModelContext) -> String? { nil }
}

/// 扫描版 PDF 的 OCR 划词——替身：识别不到任何行（框选提示"框里没认出文字"，纯翻页阅读不受影响）
final class OCRStore {
    static let shared = OCRStore()
    struct Line { let text: String; let rect: CGRect }
    func pageLines(safeName: String, profileId: String, page: Int, document: PDFDocument) async -> [Line] { [] }
    static func selection(from lines: [Line], in box: CGRect) -> (quote: String, rects: [CGRect])? { nil }
    func pageText(safeName: String, profileId: String, page: Int, document: PDFDocument) async -> String { "" }
    func prefetch(safeName: String, profileId: String, around page: Int, document: PDFDocument) async {}
    static func cachedLines(safeName: String, profileId: String, page: Int) -> [Line]? { nil }
}

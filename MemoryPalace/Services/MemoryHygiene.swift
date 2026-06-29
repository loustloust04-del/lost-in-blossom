import Foundation
import SwiftData

// MARK: - 记忆卫生工具（简化版，仅 pair 配对去重）
// 原版（粟粟）还有 DreamConsolidator 做梦合并 + 碎片毕业，
// 我们暂缺 DreamConsolidator，先做最有效的 pair 去重。

enum MemoryHygiene {

    static let pairThreshold: Float = MemoryExtractor.dedupSimilarityThreshold   // 0.75
    static let maxScanCount = 10000

    struct Report {
        let merged: Int        // pair 配对合并对数
        let remaining: Int     // 流程结束后总数
    }

    enum Failure: Error, LocalizedError {
        case tooManyMemories(Int)
        case noMemories

        var errorDescription: String? {
            switch self {
            case .tooManyMemories(let n): return "记忆条数过多（\(n) > \(MemoryHygiene.maxScanCount)），先手动整理再试"
            case .noMemories:           return "记忆库为空，无需整理"
            }
        }
    }

    /// 一次性清洗：pair 配对去重（sim > 0.75 保新去旧）
    @MainActor
    static func sweep(
        profileId: String,
        context: ModelContext
    ) async throws -> Report {
        // 1. 拉全量记忆
        let pid = profileId
        var desc = FetchDescriptor<Memory>(predicate: #Predicate<Memory> { $0.profileId == pid })
        desc.sortBy = [SortDescriptor(\Memory.updateTime, order: .reverse)]
        let all = (try? context.fetch(desc)) ?? []

        guard !all.isEmpty else { throw Failure.noMemories }
        guard all.count <= maxScanCount else { throw Failure.tooManyMemories(all.count) }

        // 2. pair 配对去重：O(n²)，按 updateTime 倒序，保新去旧
        var toDelete: Set<String> = []
        for i in 0..<all.count {
            let a = all[i]
            guard !toDelete.contains(a.id) else { continue }
            guard let vecA = a.embedding, !vecA.isEmpty else { continue }
            for j in (i+1)..<all.count {
                let b = all[j]
                guard !toDelete.contains(b.id) else { continue }
                guard let vecB = b.embedding, !vecB.isEmpty else { continue }
                let sim = cosineSimilarity(vecA, vecB)
                if sim > pairThreshold {
                    // 保 a（更新）删 b（更旧）
                    toDelete.insert(b.id)
                }
            }
        }

        // 3. 执行删除
        for id in toDelete {
            if let m = all.first(where: { $0.id == id }) {
                context.delete(m)
            }
        }
        if !toDelete.isEmpty {
            try? context.save()
        }

        let remaining = all.count - toDelete.count
        return Report(merged: toDelete.count, remaining: remaining)
    }

    // MARK: - 向量工具

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, magA: Float = 0, magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = sqrt(magA) * sqrt(magB)
        return denom > 0 ? dot / denom : 0
    }
}

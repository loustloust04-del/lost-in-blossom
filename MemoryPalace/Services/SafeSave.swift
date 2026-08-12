import Foundation
import SwiftData

/// 存盘失败不再无声无息。
///
/// 审查报告 2026-08-12 的头号发现：`try? context.save()` 遍布 8 个文件 15+ 处，
/// 写失败时**完全没人知道** —— 药物同步产生重复、聊天数据可能丢、记忆存不进去，
/// 用户侧一点提示都没有。这也是我们今天被咬三次的同一个模式
/// （门铃看着在工作其实一条没发、歌隔天点就哑、健康数据超期被删）。
///
/// 用法：`context.saveOrReport("吃药打卡")`
/// - 成功：什么都不发生（和 try? 一样安静）
/// - 失败：控制台留下带上下文的错误 + 给用户一个 toast，不再静默
extension ModelContext {

    /// 存盘，失败时报告而不是吞掉。
    /// - Parameters:
    ///   - what: 这次存的是什么（出错时给用户看，比如「吃药打卡」「刻痕」）
    ///   - notifyUser: 是否弹 toast。后台同步类的传 false，只记日志。
    @discardableResult
    func saveOrReport(_ what: String, notifyUser: Bool = true) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            let detail = (error as NSError).localizedDescription
            print("⚠️ [SafeSave] \(what) 存盘失败：\(detail)")
            if notifyUser {
                Task { @MainActor in
                    ToastCenter.shared.show("\(what)没存上，再试一次？")
                }
            }
            return false
        }
    }
}

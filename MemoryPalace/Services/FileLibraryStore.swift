import Foundation

/// app 自包含的 .md 文件库。每楼层一库：App Support/MemoryPalace/fileLibrary/{profileId}/
/// 纯文件 IO，不依赖 SwiftData。路径一律相对（允许子目录），禁止逃出库根。
enum FileLibraryStore {
    struct FileMeta { let path: String; let bytes: Int; let modifiedAt: Date }

    static func libraryRoot(profileId: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MemoryPalace/fileLibrary/\(profileId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把相对路径解析成库内绝对 URL，拒绝 ../ 越狱与绝对路径。返回 nil = 非法。
    /// 粟粟侧同功能函数叫 absoluteURL——语音条等搬运件按这个名字调，转发到 resolve。
    static func absoluteURL(_ relPath: String, profileId: String) -> URL? {
        resolve(relPath, profileId: profileId)
    }

    static func resolve(_ relPath: String, profileId: String) -> URL? {
        let root = libraryRoot(profileId: profileId).standardizedFileURL
        let cleaned = relPath.trimmingCharacters(in: .init(charactersIn: "/ "))
        guard !cleaned.isEmpty else { return nil }
        let target = root.appendingPathComponent(cleaned).standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") || target.path == root.path else { return nil }
        return target
    }

    static func list(profileId: String) -> [FileMeta] {
        let root = libraryRoot(profileId: profileId)
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return [] }
        var out: [FileMeta] = []
        for case let url as URL in en where url.pathExtension == "md" {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let rel = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            out.append(.init(path: rel, bytes: v?.fileSize ?? 0, modifiedAt: v?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { $0.path < $1.path }
    }

    static func read(_ relPath: String, profileId: String) throws -> String {
        guard let url = resolve(relPath, profileId: profileId) else { throw err("非法路径: \(relPath)") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func write(_ relPath: String, content: String, profileId: String) throws {
        guard let url = resolve(relPath, profileId: profileId) else { throw err("非法路径: \(relPath)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    /// old→new 局部替换；old 必须唯一命中，否则报错（仿 CC Edit 语义）。
    static func edit(_ relPath: String, oldString: String, newString: String, profileId: String) throws {
        let body = try read(relPath, profileId: profileId)
        let occurrences = body.components(separatedBy: oldString).count - 1
        guard occurrences == 1 else { throw err(occurrences == 0 ? "未找到要替换的文本" : "要替换的文本命中 \(occurrences) 处，需更具体") }
        try write(relPath, content: body.replacingOccurrences(of: oldString, with: newString), profileId: profileId)
    }

    static func delete(_ relPath: String, profileId: String) throws {
        guard let url = resolve(relPath, profileId: profileId) else { throw err("非法路径: \(relPath)") }
        try FileManager.default.removeItem(at: url)
    }

    /// 跨文件关键词搜索，返回 [(path, 命中行)]。大小写不敏感。
    static func search(_ keyword: String, profileId: String) -> [(path: String, line: String)] {
        guard !keyword.isEmpty else { return [] }
        var hits: [(path: String, line: String)] = []
        for meta in list(profileId: profileId) {
            guard let body = try? read(meta.path, profileId: profileId) else { continue }
            for line in body.split(separator: "\n", omittingEmptySubsequences: false)
                where line.range(of: keyword, options: .caseInsensitive) != nil {
                hits.append((meta.path, String(line)))
            }
        }
        return hits
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "FileLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: m])
    }
}

#if DEBUG
extension FileLibraryStore {
    static func _selfCheck() {
        let pid = "selfcheck"
        try? write("a.md", content: "hello\nworld", profileId: pid)
        assert((try? read("a.md", profileId: pid)) == "hello\nworld", "read 回读失败")
        assert(resolve("../escape.md", profileId: pid) == nil, "../ 越狱未拦截")
        assert(resolve("/etc/passwd", profileId: pid) == nil, "绝对路径未拦截")
        try? edit("a.md", oldString: "world", newString: "susu", profileId: pid)
        assert((try? read("a.md", profileId: pid)) == "hello\nsusu", "edit 替换失败")
        assert(search("HELLO", profileId: pid).count == 1, "search 大小写不敏感失败")
        try? delete("a.md", profileId: pid)
        print("[FileLibraryStore] selfCheck ✅")
    }
}
#endif

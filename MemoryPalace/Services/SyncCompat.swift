import Foundation

// MARK: - Compatibility stubs for upstream sync dependencies

/// Stub: SyncProbe — upstream cherry-pick dependency
struct SyncProbe {
    var localCount: Int = 0
    var remoteCount: Int = 0
    var needsSync: Bool { localCount != remoteCount }
    
    static func run() async -> SyncProbe {
        SyncProbe()
    }
}

/// Stub: LocalMode — upstream cherry-pick dependency
enum LocalMode {
    case local
    case iCloud
}

/// Stub: FileLibraryStore — upstream dependency not yet cherry-picked
class FileLibraryStore {
    static func primeICloudContainer(completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    
    static func iCloudDocumentsRoot() -> URL? {
        nil
    }
}

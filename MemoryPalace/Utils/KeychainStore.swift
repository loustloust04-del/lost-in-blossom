import Foundation
import Security

/// 薄封装 Keychain 通用密码条目，支持可选 iCloud 同步。
/// Service 统一；account 就是 providerId。
enum KeychainStore {
    static let service = "com.susu.MemoryPalace.apikey"

    /// 写入/更新/删除（value == nil 等价于 remove）。成功返回 true。
    /// 为保证一致性：写入前先删除同 account 的所有条目（本机+云），再按 sync 写一份。
    @discardableResult
    static func set(_ value: String?, account: String, sync: Bool) -> Bool {
        guard let value, !value.isEmpty else {
            remove(account: account)
            return true
        }

        // 先清掉同 account 的旧条目（不管同步模式）
        _ = SecItemDelete(anyQuery(account: account) as CFDictionary)

        let data = Data(value.utf8)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: sync ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainStore] set failed account=\(account) sync=\(sync) status=\(status)")
            return false
        }
        return true
    }

    static func get(account: String) -> String? {
        var query = anyQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound {
                print("[KeychainStore] get failed account=\(account) status=\(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func remove(account: String) {
        let status = SecItemDelete(anyQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[KeychainStore] remove failed account=\(account) status=\(status)")
        }
    }

    /// 列出当前 service 下所有 account（本机+云）。用于开关同步时统一迁移。
    static func allAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: kCFBooleanTrue!,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let items = out as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// 一次性读出当前 service 下所有 account→value 映射。
    /// 一次 SecItemCopyMatching 只触发一次 Keychain 授权弹窗，避免循环调 get 导致狂弹。
    static func getAll() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: kCFBooleanTrue!,
            kSecReturnData as String: kCFBooleanTrue!,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let items = out as? [[String: Any]] else {
            if status != errSecItemNotFound {
                print("[KeychainStore] getAll failed status=\(status)")
            }
            return [:]
        }

        var result: [String: String] = [:]
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else { continue }
            result[account] = value
        }
        return result
    }

    // MARK: - Private

    private static func anyQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}

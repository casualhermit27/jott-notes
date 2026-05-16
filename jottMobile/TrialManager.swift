import Foundation
import Security

final class TrialManager {
    static let shared = TrialManager()

    private let keychainService = "com.casualhermit.jott"
    private let keychainAccount = "trial_start"
    private let udKey           = "jott_trial_start"
    private let trialDays       = 7

    private init() {
        // Keychain is the source of truth — survives reinstalls.
        // If neither exists yet, record now in both stores.
        if keychainDate == nil {
            let date = (UserDefaults.standard.object(forKey: udKey) as? Date) ?? Date()
            saveToKeychain(date)
            UserDefaults.standard.set(date, forKey: udKey)
        }
    }

    private var startDate: Date {
        keychainDate ?? (UserDefaults.standard.object(forKey: udKey) as? Date) ?? Date()
    }

    var daysElapsed: Int {
        max(0, Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0)
    }

    var daysRemaining: Int { max(0, trialDays - daysElapsed) }
    var isActive: Bool     { daysElapsed < trialDays }
    var hasExpired: Bool   { !isActive }

    // MARK: - Keychain

    private var keychainDate: Date? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    private func saveToKeychain(_ date: Date) {
        guard let data = try? JSONEncoder().encode(date) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}

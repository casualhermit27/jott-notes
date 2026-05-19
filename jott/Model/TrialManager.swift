import Foundation
import Security

final class TrialManager {
    static let shared = TrialManager()

    private let keychainService  = "com.casualhermit.jott"
    private let keychainAccount  = "trial_start"
    private let keychainHWM      = "trial_hwm"       // high-water mark
    private let udKey            = "jott_trial_start"
    private let trialDays        = 7

    private init() {
        if keychainDate(account: keychainAccount) == nil {
            let date = (UserDefaults.standard.object(forKey: udKey) as? Date) ?? Date()
            saveToKeychain(date, account: keychainAccount)
            UserDefaults.standard.set(date, forKey: udKey)
        }
        // Initialise high-water mark to start date if missing.
        if keychainDate(account: keychainHWM) == nil {
            let start = keychainDate(account: keychainAccount) ?? Date()
            saveToKeychain(start, account: keychainHWM)
        }
    }

    private var startDate: Date {
        keychainDate(account: keychainAccount)
            ?? (UserDefaults.standard.object(forKey: udKey) as? Date)
            ?? Date()
    }

    // The furthest point in time we have ever observed.
    private var highWaterMark: Date {
        keychainDate(account: keychainHWM) ?? startDate
    }

    var daysElapsed: Int {
        let now = Date()
        // Advance the watermark if time has moved forward.
        let effective = max(now, highWaterMark)
        if effective > highWaterMark { saveToKeychain(effective, account: keychainHWM) }
        // Keychain tamper or impossible state — expire.
        guard effective >= startDate else { return trialDays }
        return max(0, Calendar.current.dateComponents([.day], from: startDate, to: effective).day ?? 0)
    }

    var daysRemaining: Int { max(0, trialDays - daysElapsed) }
    var isActive: Bool     { daysElapsed < trialDays }
    var hasExpired: Bool   { !isActive }

    // MARK: - Keychain

    private func keychainDate(account: String) -> Date? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    private func saveToKeychain(_ date: Date, account: String) {
        guard let data = try? JSONEncoder().encode(date) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}

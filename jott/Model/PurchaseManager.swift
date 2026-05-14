import Foundation
import Combine
import RevenueCat

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published private(set) var isProActive: Bool = false
    @Published private(set) var isInTrial: Bool = false
    @Published private(set) var offerings: Offerings?

    private let entitlementID = "pro"
    private static var didConfigure = false

    private init() {}

    func configure(apiKey: String) {
        guard !Self.didConfigure else { return }
        Self.didConfigure = true
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = PurchaseDelegate.shared
        Task { await refresh() }
    }

    func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    func fetchOfferings() async {
        offerings = try? await Purchases.shared.offerings()
    }

    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        apply(result.customerInfo)
    }

    func restore() async throws {
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
    }

    func showPaywall() {
        NotificationCenter.default.post(name: .jottShowPaywall, object: nil)
    }

    func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[entitlementID]
        isProActive = entitlement?.isActive == true
        isInTrial = entitlement?.periodType == .trial
    }
}

// Delegate lives off main actor to satisfy RevenueCat protocol
private final class PurchaseDelegate: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegate()
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in PurchaseManager.shared.apply(customerInfo) }
    }
}

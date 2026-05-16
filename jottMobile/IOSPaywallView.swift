import SwiftUI
import RevenueCat

struct IOSPaywallView: View {
    @StateObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private let purple      = Color(red: 0.486, green: 0.361, blue: 0.961) // #7C5CF5
    private let purpleLight = Color(red: 0.663, green: 0.549, blue: 0.961) // #A98CF5

    private let features = [
        "Unlimited notes",
        "Folders, pins & search",
        "Rich markdown blocks",
        "iCloud sync across devices",
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    Spacer().frame(height: 64)

                    // App icon
                    Image("JottAppIcon")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .shadow(color: .black.opacity(0.40), radius: 20, y: 10)

                    Spacer().frame(height: 32)

                    // Wordmark + PRO pill
                    HStack(alignment: .center, spacing: 8) {
                        Text("jott")
                            .font(.system(size: 36, weight: .semibold))
                            .tracking(-1.44)
                            .foregroundStyle(.white)

                        Text("PRO")
                            .font(.system(size: 11, design: .monospaced).weight(.regular))
                            .tracking(2.64)
                            .foregroundStyle(purpleLight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(purpleLight.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer().frame(height: 24)

                    // Tagline
                    (
                        Text("Your notes. ")
                            .foregroundColor(.white.opacity(0.55))
                        + Text("Yours forever.")
                            .italic()
                            .foregroundColor(purpleLight)
                    )
                    .font(.system(size: 16, weight: .regular))
                    .multilineTextAlignment(.center)

                    Spacer().frame(height: 28)

                    // Trial status
                    if TrialManager.shared.isActive {
                        Text("\(TrialManager.shared.daysRemaining) days left in your free trial")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(purpleLight.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(purpleLight.opacity(0.10), in: Capsule())
                    } else {
                        Text("Your 7-day free trial has ended")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.40))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }

                    Spacer().frame(height: 48)

                    // Feature list
                    VStack(spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.offset) { i, label in
                            if i > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.07))
                                    .frame(height: 0.5)
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(purpleLight)
                                Text(label)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.vertical, 13)
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer().frame(height: 64)

                    // Price block
                    VStack(spacing: 3) {
                        Text(purchases.offerings?.current?.lifetime?.localizedPriceString ?? "$12.99")
                            .font(.system(size: 36, weight: .semibold))
                            .tracking(-1.26)
                            .foregroundStyle(.white)

                        Text("ONE TIME · NO SUBSCRIPTION")
                            .font(.system(size: 11, design: .monospaced).weight(.regular))
                            .tracking(3.08)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .multilineTextAlignment(.center)

                    Spacer().frame(height: 28)

                    // CTA
                    Button {
                        Task { await buyLifetime() }
                    } label: {
                        ZStack {
                            if isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Get Lifetime Access")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(purple, in: Capsule())
                        .shadow(color: purple.opacity(0.45), radius: 25, y: 10)
                    }
                    .padding(.horizontal, 28)
                    .disabled(isPurchasing || isRestoring)

                    Spacer().frame(height: 18)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 8)
                    }

                    // Restore
                    Button {
                        Task { await restore() }
                    } label: {
                        if isRestoring {
                            ProgressView().tint(.white.opacity(0.42))
                                .scaleEffect(0.8)
                        } else {
                            Text("Restore Purchase")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                    .disabled(isPurchasing || isRestoring)

                    Spacer().frame(height: 50)
                }
            }

            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .preferredColorScheme(.dark)
        .onChange(of: purchases.isProActive) { active in
            if active { dismiss() }
        }
        .task {
            await purchases.fetchOfferings()
        }
    }

    private func buyLifetime() async {
        errorMessage = nil
        guard let offerings = try? await Purchases.shared.offerings(),
              let package = offerings.current?.lifetime else {
            errorMessage = "Product unavailable. Try again later."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchases.purchase(package)
        } catch {
            if (error as NSError).code != 2 {
                errorMessage = "Purchase failed. Please try again."
            }
        }
    }

    private func restore() async {
        errorMessage = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await purchases.restore()
            if !purchases.isProActive {
                errorMessage = "No previous purchase found."
            }
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }
}

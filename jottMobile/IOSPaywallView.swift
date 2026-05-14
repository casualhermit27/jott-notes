import SwiftUI
import RevenueCat

struct IOSPaywallView: View {
    @StateObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }

    private let features: [(String, String)] = [
        ("note.text",       "Unlimited notes"),
        ("folder",          "Folders & organisation"),
        ("magnifyingglass", "Full-text search"),
        ("paintbrush",      "Rich block formatting"),
        ("icloud",          "iCloud sync across devices"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ds.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Icon + headline
                    VStack(spacing: 14) {
                        Image("JottControlIcon")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

                        VStack(spacing: 6) {
                            Text("Jott Pro")
                                .font(.jottTitle(28, weight: .bold))
                                .foregroundColor(ds.ink)

                            Text("One-time purchase. No subscription, ever.")
                                .font(.jottBody(15))
                                .foregroundColor(ds.inkMute)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 32)

                    // Feature list
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(features, id: \.0) { icon, label in
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(ds.accentSoft)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(ds.accent)
                                }
                                Text(label)
                                    .font(.jottBody(16))
                                    .foregroundColor(ds.ink)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(.jottCaption(13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 12)
                    }

                    // CTA
                    VStack(spacing: 14) {
                        Button {
                            Task { await buyLifetime() }
                        } label: {
                            ZStack {
                                if isPurchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    VStack(spacing: 3) {
                                        Text("Get Lifetime Access")
                                            .font(.jottTitle(17, weight: .bold))
                                        if let price = purchases.offerings?.current?.lifetime?.localizedPriceString {
                                            Text("One-time \(price) — no subscription, ever")
                                                .font(.jottCaption(12))
                                                .opacity(0.82)
                                        }
                                    }
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.52, green: 0.38, blue: 0.98),
                                        Color(red: 0.30, green: 0.18, blue: 0.82)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color(red: 0.38, green: 0.22, blue: 0.85).opacity(0.4), radius: 14, y: 6)
                        }
                        .disabled(isPurchasing || isRestoring)

                        Button {
                            Task { await restore() }
                        } label: {
                            if isRestoring {
                                ProgressView().tint(ds.inkFaint)
                            } else {
                                Text("Restore Purchase")
                                    .font(.jottCaption(14))
                                    .foregroundColor(ds.inkFaint)
                            }
                        }
                        .disabled(isPurchasing || isRestoring)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }

            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ds.inkFaint)
                    .frame(width: 30, height: 30)
                    .background(ds.surfaceAlt, in: Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
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

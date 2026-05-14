import SwiftUI
import RevenueCat

struct PaywallView: View {
    @StateObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private let features: [(String, String)] = [
        ("note.text", "Unlimited notes"),
        ("folder", "Folders & organisation"),
        ("magnifyingglass", "Full-text search"),
        ("paintbrush", "Rich block formatting"),
        ("icloud", "iCloud sync across devices"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image("JottControlIcon")
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Jott Pro")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text("One-time purchase. No subscription.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 20)

            // Feature list
            VStack(alignment: .leading, spacing: 11) {
                ForEach(features, id: \.0) { icon, label in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(width: 18)
                        Text(label)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()
                .padding(.horizontal, 20)

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            // CTA
            VStack(spacing: 10) {
                Button {
                    Task { await buyLifetime() }
                } label: {
                    ZStack {
                        if isPurchasing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            VStack(spacing: 2) {
                                Text("Get Lifetime Access")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                if let price = purchases.offerings?.current?.lifetime?.localizedPriceString {
                                    Text("One-time \(price) — no subscription")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .opacity(0.82)
                                }
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
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
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: Color(red: 0.38, green: 0.22, blue: 0.85).opacity(0.45), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isRestoring)

                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Restore Purchase")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isRestoring)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: purchases.isProActive) { active in
            if active { dismiss() }
        }
        .task {
            await purchases.fetchOfferings()
        }

        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
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
            if (error as NSError).code != 2 { // 2 = user cancelled
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

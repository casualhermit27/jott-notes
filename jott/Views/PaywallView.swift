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
                    HStack {
                        if isPurchasing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Get Lifetime Access — $12.99")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

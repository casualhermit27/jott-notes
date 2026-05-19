import SwiftUI
import RevenueCat

struct PaywallView: View {
    @StateObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var loadingTimedOut = false
    @State private var retryCount = 0
    @State private var timeoutTask: DispatchWorkItem?

    private let features: [(String, String)] = [
        ("note.text",       "Unlimited notes"),
        ("folder",          "Folders & organisation"),
        ("magnifyingglass", "Full-text search"),
        ("paintbrush",      "Rich block formatting"),
        ("icloud",          "iCloud sync across devices"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {

                // Header
                VStack(spacing: 12) {
                    Image("JottAppIcon")
                        .resizable()
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)

                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("jott")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("PRO")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .offset(y: -2)
                        }

                        Text("One-time purchase. No subscription.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 22)

                Divider().padding(.horizontal, 20)

                // Features
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(features, id: \.0) { icon, label in
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .light))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(label)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 8)

                Divider().padding(.horizontal, 20)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // CTA
                if loadingTimedOut && purchases.offerings == nil {
                    VStack(spacing: 9) {
                        Text("Couldn't load pricing")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Check your connection and try again.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            loadingTimedOut = false
                            retryCount += 1
                            startTimeout()
                            Task { await purchases.fetchOfferings() }
                        } label: {
                            Text("Try Again")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await restore() }
                        } label: {
                            if isRestoring {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Restore Purchase")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoring)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                } else {
                    VStack(spacing: 9) {
                        Button {
                            Task { await buyLifetime() }
                        } label: {
                            ZStack {
                                if isPurchasing {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else if purchases.offerings == nil {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    VStack(spacing: 2) {
                                        Text("Get Lifetime Access")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        if let price = purchases.offerings?.current?.lifetime?.localizedPriceString {
                                            Text("One-time \(price) — no subscription")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .opacity(0.82)
                                        }
                                    }
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing || isRestoring || purchases.offerings == nil)

                        Button {
                            Task { await restore() }
                        } label: {
                            if isRestoring {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Restore Purchase")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing || isRestoring)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
            }
            .frame(width: 300)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: purchases.isProActive) { _, active in
                if active { dismiss() }
            }
            .onChange(of: purchases.offerings) { _, offerings in
                if offerings != nil {
                    timeoutTask?.cancel()
                    timeoutTask = nil
                }
            }
            .task {
                startTimeout()
                await purchases.fetchOfferings()
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        let work = DispatchWorkItem {
            if purchases.offerings == nil {
                loadingTimedOut = true
            }
        }
        timeoutTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func buyLifetime() async {
        errorMessage = nil
        guard let offerings = try? await Purchases.shared.offerings(),
              let package = offerings.current?.lifetime else {
            errorMessage = "Pricing unavailable right now. You may be offline — connect and try again."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await purchases.purchase(package)
        } catch {
            if (error as NSError).code != 2 {
                errorMessage = "Purchase didn't go through. Please try again."
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
                errorMessage = "No purchase found. Make sure you're signed in to the Apple ID used to buy Jott."
            }
        } catch {
            errorMessage = "Restore didn't complete. Check your connection and try again."
        }
    }
}

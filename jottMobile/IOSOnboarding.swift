#if os(iOS)
import SwiftUI

// MARK: - Tokens

private let lavender  = Color(red: 0.710, green: 0.549, blue: 0.965) // #b58cf6
private let ctaPurple = Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6

// MARK: - Entry point

struct JottOnboardingV2: View {
    let onDone: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $step) {
                OnbScreen1(onContinue: { withAnimation(.easeInOut(duration: 0.30)) { step = 1 } })
                    .tag(0)
                OnbScreen2(onDone: onDone)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

// MARK: ── Screen 1 — Notes list preview ─────────────────────────────────────

private struct OnbScreen1: View {
    let onContinue: () -> Void

    private let chips: [(String, Color)] = [
        ("Ideas",   Color(red: 0.25, green: 0.75, blue: 0.40)),
        ("Reading", Color(red: 0.60, green: 0.40, blue: 1.00)),
        ("Recipes", Color(red: 1.00, green: 0.65, blue: 0.20)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 64)

            // Icon
            Image("JottAppIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 28)

            // Big headline
            Text("A quiet place\nfor fast thoughts.")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            // Tagline
            (
                Text("Your notes. ")
                    .foregroundColor(.white.opacity(0.40))
                + Text("Yours forever.")
                    .italic()
                    .foregroundColor(lavender)
            )
            .font(.system(size: 16, weight: .regular))
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 28)

            // Folder chip row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Solid "All"
                    Text("All")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(ctaPurple, in: Capsule())

                    ForEach(chips, id: \.0) { name, color in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: 9, height: 9)
                            Text(name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer().frame(height: 14)

            // Note cards
            VStack(spacing: 10) {
                OnbNoteCard(
                    date: "18 MAY",
                    pinLabel: "PINNED",
                    time: "JUST NOW",
                    title: "Sunday plans",
                    preview: "Coffee at the new place on 4th, bookshop after, write to dad before it gets late..."
                )
                OnbNoteCard(
                    date: "17 MAY",
                    pinLabel: nil,
                    time: "1 DAY AGO",
                    title: "Movie idea — the courier whose packages arrive a day early",
                    preview: nil
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            // Progress dots
            OnbDots(total: 2, active: 0)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            // CTA
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(ctaPurple, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 48)
        }
    }
}

// MARK: ── Screen 2 — Welcome + trial CTA ────────────────────────────────────

private struct OnbScreen2: View {
    let onDone: () -> Void

    private let features = [
        "Unlimited notes",
        "Folders, pins & search",
        "iCloud sync across devices",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 64)

            // Icon
            Image("JottAppIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: lavender.opacity(0.20), radius: 24, y: 8)

            Spacer().frame(height: 24)

            // Wordmark
            Text("jott")
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.76)
                .foregroundStyle(.white)

            Spacer().frame(height: 10)

            // Tagline
            (
                Text("Your notes. ")
                    .foregroundColor(.white.opacity(0.40))
                + Text("Yours forever.")
                    .italic()
                    .foregroundColor(lavender)
            )
            .font(.system(size: 16, weight: .regular))

            Spacer().frame(height: 48)

            // Feature list
            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { i, label in
                    if i > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 0.5)
                            .padding(.horizontal, 4)
                    }
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(lavender)
                            .frame(width: 16)
                        Text(label)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.88))
                        Spacer()
                    }
                    .padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 36)

            Spacer()

            // Progress dots
            OnbDots(total: 2, active: 1)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            // "FREE · NO SIGN UP"
            Text("FREE  ·  NO SIGN UP")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.26))
                .padding(.bottom, 14)

            // Trial CTA
            Button(action: onDone) {
                VStack(spacing: 5) {
                    Text("Start Free 7-Day Trial")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("then $12.99  ·  one time")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(.white.opacity(0.60))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(ctaPurple, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 48)
        }
    }
}

// MARK: ── Sub-components ─────────────────────────────────────────────────────

private struct OnbNoteCard: View {
    let date: String
    let pinLabel: String?
    let time: String
    let title: String
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Meta row
            HStack(spacing: 0) {
                Text(date)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.28))

                if let pin = pinLabel {
                    Text("   \(pin)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(lavender)
                }

                Spacer()

                Text(time)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.28))
            }

            // Title
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Preview
            if let preview {
                Text(preview)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

private struct OnbDots: View {
    let total: Int
    let active: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == active ? lavender : Color.white.opacity(0.20))
                    .frame(width: i == active ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: active)
            }
        }
    }
}

// MARK: - V1 (single-screen fallback, keep for reference)

struct JottOnboardingV1: View {
    let onDone: () -> Void

    private let features = [
        "Unlimited notes",
        "Folders, pins & search",
        "iCloud sync across devices",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                Image("JottAppIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: lavender.opacity(0.22), radius: 28, y: 10)

                Spacer().frame(height: 28)

                Text("jott")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.76)
                    .foregroundStyle(.white)

                Spacer().frame(height: 10)

                (
                    Text("Your notes. ")
                        .foregroundColor(.white.opacity(0.38))
                    + Text("Yours forever.")
                        .italic()
                        .foregroundColor(lavender)
                )
                .font(.system(size: 16, weight: .regular))

                Spacer().frame(height: 52)

                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.offset) { i, label in
                        if i > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 0.5)
                        }
                        HStack(spacing: 16) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(lavender)
                                .frame(width: 16)
                            Text(label)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                        }
                        .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 36)

                Spacer().frame(height: 60)

                Text("FREE  ·  NO SIGN UP")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.26))
                    .padding(.bottom, 14)

                Button(action: onDone) {
                    Text("Start writing")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(ctaPurple, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 48)
            }
        }
    }
}
#endif

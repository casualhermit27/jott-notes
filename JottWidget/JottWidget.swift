import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Intent

struct JottQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "New Note"
    static var description = IntentDescription("Open Jott to quick capture.")
    static var openAppWhenRun = true

    private let appGroupID = "group.com.casualhermit.jott"
    private let pendingKey = "jott_mobile_pendingQuickCapture"

    @MainActor
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(UUID().uuidString, forKey: pendingKey)
        return .result()
    }
}

// MARK: - Data model

struct JottWidgetEntry: TimelineEntry {
    let date: Date
    let pinnedTitle: String?
    let pinnedBody: String?
    let pinnedDate: Date?

    var hasPinnedNote: Bool { pinnedTitle != nil }
}

// MARK: - Provider

struct JottWidgetProvider: TimelineProvider {
    private let appGroupID = "group.com.casualhermit.jott"
    private let titleKey   = "jott_widget_pinned_title"
    private let bodyKey    = "jott_widget_pinned_body"
    private let dateKey    = "jott_widget_pinned_date"
    private let hasNoteKey = "jott_widget_has_pinned"

    private func readEntry(for date: Date) -> JottWidgetEntry {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              defaults.bool(forKey: hasNoteKey) else {
            return JottWidgetEntry(date: date, pinnedTitle: nil, pinnedBody: nil, pinnedDate: nil)
        }
        let title = defaults.string(forKey: titleKey)
        let body  = defaults.string(forKey: bodyKey)
        let ts    = defaults.double(forKey: dateKey)
        let noteDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return JottWidgetEntry(date: date, pinnedTitle: title, pinnedBody: body, pinnedDate: noteDate)
    }

    func placeholder(in context: Context) -> JottWidgetEntry {
        JottWidgetEntry(date: Date(), pinnedTitle: "Meeting notes", pinnedBody: "Follow up with team · Review PR · Update docs", pinnedDate: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (JottWidgetEntry) -> Void) {
        completion(readEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JottWidgetEntry>) -> Void) {
        let entry = readEntry(for: Date())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Views

struct JottWidgetEntryView: View {
    var entry: JottWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .systemSmall:
            systemSmallView
        case .systemMedium:
            systemMediumView
        default:
            circularView
        }
    }

    // ── Lock screen circular ─────────────────────────────────────────────────
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image("JottIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .widgetAccentable()
        }
        .widgetURL(URL(string: "jott://new"))
    }

    // ── Lock screen rectangular ──────────────────────────────────────────────
    private var rectangularView: some View {
        Group {
            if entry.hasPinnedNote {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .widgetAccentable()
                        Text(entry.pinnedTitle ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                    if let body = entry.pinnedBody, !body.isEmpty {
                        Text(body)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .opacity(0.75)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .widgetURL(URL(string: "jott://open"))
            } else {
                HStack(spacing: 10) {
                    Image("JottIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .widgetAccentable()
                    Text("New Note")
                        .font(.system(size: 15, weight: .semibold))
                        .widgetAccentable()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "jott://new"))
            }
        }
    }

    // ── Lock screen inline ───────────────────────────────────────────────────
    private var inlineView: some View {
        Group {
            if entry.hasPinnedNote {
                Label(entry.pinnedTitle ?? "", systemImage: "pin.fill")
                    .widgetAccentable()
                    .widgetURL(URL(string: "jott://open"))
            } else {
                Label("Capture", systemImage: "square.and.pencil")
                    .widgetAccentable()
                    .widgetURL(URL(string: "jott://new"))
            }
        }
    }

    // ── Home screen small ────────────────────────────────────────────────────
    private var systemSmallView: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)

            VStack(alignment: .leading, spacing: 0) {
                if entry.hasPinnedNote {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("PINNED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }

                        Text(entry.pinnedTitle ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let body = entry.pinnedBody, !body.isEmpty {
                            Text(body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .widgetURL(URL(string: "jott://open"))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Image("JottIcon")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Text("Jott")
                            .font(.system(size: 14, weight: .semibold))
                        Text("No pinned note")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // ── Capture strip ──────────────────────────────────────────
                Link(destination: URL(string: "jott://new")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Capture")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 8)
                }
            }
            .padding(14)
        }
    }

    // ── Home screen medium ───────────────────────────────────────────────────
    private var systemMediumView: some View {
        ZStack {
            Color(.systemBackground)

            HStack(spacing: 0) {
                // Left: pinned note
                VStack(alignment: .leading, spacing: 6) {
                    if entry.hasPinnedNote {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("PINNED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }

                        Text(entry.pinnedTitle ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)

                        if let body = entry.pinnedBody, !body.isEmpty {
                            Text(body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        Spacer(minLength: 0)

                        if let date = entry.pinnedDate {
                            Text(date, style: .relative)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Image("JottIcon")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("No pinned note")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
                .widgetURL(entry.hasPinnedNote ? URL(string: "jott://open") : URL(string: "jott://new"))

                Divider()
                    .padding(.vertical, 12)

                // Right: quick capture
                Link(destination: URL(string: "jott://new")!) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                        Text("Capture")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .frame(width: 80)
                }
            }
        }
    }
}

// MARK: - Widget Configuration

struct JottPinnedWidget: Widget {
    let kind = "JottPinnedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JottWidgetProvider()) { entry in
            JottWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Jott")
        .description("See your pinned note and capture new ones instantly.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Lock Screen Intent

struct JottQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "New Note"
    static var description = IntentDescription("Open Jott directly to quick capture.")
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

// MARK: - Lock Screen Widget

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries: [SimpleEntry] = [SimpleEntry(date: Date())]
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct JottWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image("JottIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .widgetAccentable()
            }
            .widgetURL(URL(string: "jott://new"))
        case .accessoryRectangular:
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
        default:
            Label("Capture", systemImage: "square.and.pencil")
                .widgetAccentable()
                .widgetURL(URL(string: "jott://new"))
        }
    }
}

struct JottWidget: Widget {
    let kind: String = "JottWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            JottWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Jott Capture")
        .description("Quick capture a new note from your lock screen.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

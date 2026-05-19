import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum JottWidgetBridge {
    private static let appGroupID  = "group.com.casualhermit.jott"
    private static let titleKey    = "jott_widget_pinned_title"
    private static let bodyKey     = "jott_widget_pinned_body"
    private static let dateKey     = "jott_widget_pinned_date"
    private static let hasNoteKey  = "jott_widget_has_pinned"

    static func update(pinnedTitle: String?, pinnedBody: String?, modifiedAt: Date?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let title = pinnedTitle {
            defaults.set(title, forKey: titleKey)
            defaults.set(pinnedBody ?? "", forKey: bodyKey)
            defaults.set(modifiedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970, forKey: dateKey)
            defaults.set(true, forKey: hasNoteKey)
        } else {
            defaults.removeObject(forKey: titleKey)
            defaults.removeObject(forKey: bodyKey)
            defaults.removeObject(forKey: dateKey)
            defaults.set(false, forKey: hasNoteKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func read() -> (title: String?, body: String?, date: Date?) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              defaults.bool(forKey: hasNoteKey) else {
            return (nil, nil, nil)
        }
        let title = defaults.string(forKey: titleKey)
        let body  = defaults.string(forKey: bodyKey)
        let ts    = defaults.double(forKey: dateKey)
        let date  = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return (title, body, date)
    }
}

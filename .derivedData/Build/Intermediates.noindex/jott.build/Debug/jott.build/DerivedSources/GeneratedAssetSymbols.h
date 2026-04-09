#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.casualhermit.jott";

/// The "jott-accent-green" asset catalog color resource.
static NSString * const ACColorNameJottAccentGreen AC_SWIFT_PRIVATE = @"jott-accent-green";

/// The "jott-bar" asset catalog color resource.
static NSString * const ACColorNameJottBar AC_SWIFT_PRIVATE = @"jott-bar";

/// The "jott-border" asset catalog color resource.
static NSString * const ACColorNameJottBorder AC_SWIFT_PRIVATE = @"jott-border";

/// The "jott-cursor" asset catalog color resource.
static NSString * const ACColorNameJottCursor AC_SWIFT_PRIVATE = @"jott-cursor";

/// The "jott-detail-background" asset catalog color resource.
static NSString * const ACColorNameJottDetailBackground AC_SWIFT_PRIVATE = @"jott-detail-background";

/// The "jott-green" asset catalog color resource.
static NSString * const ACColorNameJottGreen AC_SWIFT_PRIVATE = @"jott-green";

/// The "jott-input-text" asset catalog color resource.
static NSString * const ACColorNameJottInputText AC_SWIFT_PRIVATE = @"jott-input-text";

/// The "jott-lavender" asset catalog color resource.
static NSString * const ACColorNameJottLavender AC_SWIFT_PRIVATE = @"jott-lavender";

/// The "jott-link-bg" asset catalog color resource.
static NSString * const ACColorNameJottLinkBg AC_SWIFT_PRIVATE = @"jott-link-bg";

/// The "jott-link-text" asset catalog color resource.
static NSString * const ACColorNameJottLinkText AC_SWIFT_PRIVATE = @"jott-link-text";

/// The "jott-link-underline" asset catalog color resource.
static NSString * const ACColorNameJottLinkUnderline AC_SWIFT_PRIVATE = @"jott-link-underline";

/// The "jott-meeting-accent" asset catalog color resource.
static NSString * const ACColorNameJottMeetingAccent AC_SWIFT_PRIVATE = @"jott-meeting-accent";

/// The "jott-meeting-badge-bg" asset catalog color resource.
static NSString * const ACColorNameJottMeetingBadgeBg AC_SWIFT_PRIVATE = @"jott-meeting-badge-bg";

/// The "jott-meeting-badge-fg" asset catalog color resource.
static NSString * const ACColorNameJottMeetingBadgeFg AC_SWIFT_PRIVATE = @"jott-meeting-badge-fg";

/// The "jott-note-accent" asset catalog color resource.
static NSString * const ACColorNameJottNoteAccent AC_SWIFT_PRIVATE = @"jott-note-accent";

/// The "jott-note-badge-bg" asset catalog color resource.
static NSString * const ACColorNameJottNoteBadgeBg AC_SWIFT_PRIVATE = @"jott-note-badge-bg";

/// The "jott-note-badge-fg" asset catalog color resource.
static NSString * const ACColorNameJottNoteBadgeFg AC_SWIFT_PRIVATE = @"jott-note-badge-fg";

/// The "jott-placeholder" asset catalog color resource.
static NSString * const ACColorNameJottPlaceholder AC_SWIFT_PRIVATE = @"jott-placeholder";

/// The "jott-reminder-accent" asset catalog color resource.
static NSString * const ACColorNameJottReminderAccent AC_SWIFT_PRIVATE = @"jott-reminder-accent";

/// The "jott-reminder-badge-bg" asset catalog color resource.
static NSString * const ACColorNameJottReminderBadgeBg AC_SWIFT_PRIVATE = @"jott-reminder-badge-bg";

/// The "jott-reminder-badge-fg" asset catalog color resource.
static NSString * const ACColorNameJottReminderBadgeFg AC_SWIFT_PRIVATE = @"jott-reminder-badge-fg";

/// The "jott-sage" asset catalog color resource.
static NSString * const ACColorNameJottSage AC_SWIFT_PRIVATE = @"jott-sage";

/// The "jott-tag-blush" asset catalog color resource.
static NSString * const ACColorNameJottTagBlush AC_SWIFT_PRIVATE = @"jott-tag-blush";

/// The "jott-tag-cream" asset catalog color resource.
static NSString * const ACColorNameJottTagCream AC_SWIFT_PRIVATE = @"jott-tag-cream";

/// The "jott-tag-mint" asset catalog color resource.
static NSString * const ACColorNameJottTagMint AC_SWIFT_PRIVATE = @"jott-tag-mint";

/// The "jott-tag-periwinkle" asset catalog color resource.
static NSString * const ACColorNameJottTagPeriwinkle AC_SWIFT_PRIVATE = @"jott-tag-periwinkle";

/// The "JottMenuBar" asset catalog image resource.
static NSString * const ACImageNameJottMenuBar AC_SWIFT_PRIVATE = @"JottMenuBar";

#undef AC_SWIFT_PRIVATE

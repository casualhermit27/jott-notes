import AppKit
import CoreGraphics

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: Unmanaged<HotkeyManager>?
    private var action: (() -> Void)?
    private var resignObserver: Any?

    // Double-tap detection
    private var lastOptionTapTimestamp: TimeInterval?
    private var optionIsDown = false
    private let doubleTapInterval: TimeInterval = 0.65   // max gap between taps
    private let staleOptionResetInterval: TimeInterval = 0.40

    func register(action: @escaping () -> Void) {
        self.action = action
        promptAccessibilityTrustIfNeeded()
        installEventTap()
        installResignObserver()
    }

    private func promptAccessibilityTrustIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        let retained = Unmanaged.passRetained(self)
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                let flags = event.flags
                let timestamp = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [manager] in
                    manager.handleCGFlagsChanged(flags: flags, timestamp: timestamp)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            return
        }

        tapContext = retained
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func installResignObserver() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetTapState() }
        }
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        tapContext?.release()
        eventTap = nil
        runLoopSource = nil
        tapContext = nil
        resignObserver = nil
        resetTapState()
    }

    private func handleCGFlagsChanged(flags: CGEventFlags, timestamp: TimeInterval) {
        let optionNowDown = flags.contains(.maskAlternate)

        if !optionNowDown {
            optionIsDown = false
            return
        }

        if optionIsDown {
            if let lastTap = lastOptionTapTimestamp {
                if timestamp - lastTap > staleOptionResetInterval {
                    optionIsDown = false
                }
            } else {
                optionIsDown = false
            }
        }

        // Only fire when Option is the only modifier down.
        let relevantMask: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        guard flags.intersection(relevantMask) == .maskAlternate else { return }
        guard !optionIsDown else { return }
        optionIsDown = true

        if registerOptionTap(at: timestamp) {
            Task { @MainActor in self.action?() }
        }
    }

    private func registerOptionTap(at timestamp: TimeInterval) -> Bool {
        if let last = lastOptionTapTimestamp, timestamp - last <= doubleTapInterval {
            lastOptionTapTimestamp = nil
            return true
        }
        lastOptionTapTimestamp = timestamp
        return false
    }

    private func resetTapState() {
        optionIsDown = false
        lastOptionTapTimestamp = nil
    }

#if DEBUG
    func registerOptionTapForTesting(at timestamp: TimeInterval) -> Bool {
        registerOptionTap(at: timestamp)
    }
#endif
}

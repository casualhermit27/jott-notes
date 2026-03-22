import AppKit

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var monitor: Any?
    private var action: (() -> Void)?

    // Double-tap detection
    private var lastOptionTap: Date?
    private let doubleTapInterval: TimeInterval = 0.35   // max gap between taps

    func register(action: @escaping () -> Void) {
        self.action = action

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)

        // Watch flagsChanged: Option key fires here when pressed/released alone
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }

            // We want the Option key pressed DOWN (flags now contain option,
            // and no other modifier is held). Key-up fires the same event with
            // option absent — ignore that.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .option else { return }

            let now = Date()
            if let last = self.lastOptionTap, now.timeIntervalSince(last) <= self.doubleTapInterval {
                // Second tap within window → trigger
                self.lastOptionTap = nil
                Task { @MainActor in self.action?() }
            } else {
                self.lastOptionTap = now
            }
        }
    }

    func unregister() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

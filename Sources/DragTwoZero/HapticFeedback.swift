import AppKit

/// Feedback follows changes in selection, not repeated pointer/render updates.
final class CaptureHaptics {
    private var highlighted: [CGRect] = []
    private var destinationReady = false
    private let enabled: () -> Bool
    private let perform: (NSHapticFeedbackManager.FeedbackPattern) -> Void

    init(enabled: @escaping () -> Bool = { CapturePreferences.hapticsEnabled }, perform: @escaping (NSHapticFeedbackManager.FeedbackPattern) -> Void = {
        let pattern = $0
        // Capture actions can arrive inside the low-level event tap, before
        // AppKit has presented the overlay. Submit from the next main-loop turn.
        DispatchQueue.main.async {
            guard CapturePreferences.hapticsEnabled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            // Highlight uses one alignment pulse; drag and drop use two generic pulses.
            if pattern == .generic {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard CapturePreferences.hapticsEnabled else { return }
                    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
                }
            }
            // This records a request, not confirmation of physical actuation.
            DebugLog.shared.record(.haptic(pattern: pattern.rawValue, active: NSApp.isActive, keyWindow: NSApp.keyWindow != nil))
        }
    }) {
        self.enabled = enabled
        self.perform = perform
    }

    func highlight(_ frames: [CGRect]) {
        let added = frames.filter { !highlighted.contains($0) }
        highlighted = frames
        if enabled() { for _ in added { perform(.alignment) } }
    }

    func destination(_ ready: Bool) {
        guard destinationReady != ready else { return }
        destinationReady = ready
        if ready && enabled() { perform(.alignment) }
    }

    func startDrag() {
        destinationReady = false
        highlighted = []
        if enabled() { perform(.generic) }
    }

    func drop() {
        highlighted = []
        if enabled() { perform(.generic) }
    }

    func reposition(_ frames: [CGRect]) { highlighted = frames }

    func reset() { highlighted = []; destinationReady = false }
}

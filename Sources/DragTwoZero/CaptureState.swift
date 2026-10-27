import Foundation

/// Completion locks activation until the physical shortcut is released.
struct CaptureState {
    enum Phase: Equatable { case idle, armed, resolving, selecting, ready, dragging, locked }
    private(set) var phase: Phase = .idle
    mutating func modifiers(held: Bool) {
        if !held && ![.dragging, .selecting, .resolving].contains(phase) { phase = .idle }
        else if phase == .idle { phase = .armed }
    }
    mutating func begin() { if phase == .armed || phase == .ready { phase = .dragging } }
    mutating func prepareSelectedText() { if phase == .armed { phase = .ready } }
    mutating func resolvePress() { if phase == .armed { phase = .resolving } }
    mutating func resolvedPress() { if phase == .resolving { phase = .armed } }
    mutating func select(enabled: Bool = true) { if enabled && phase == .armed { phase = .selecting } }
    mutating func finishSelection(mouseDown: Bool) {
        if phase == .selecting { phase = mouseDown ? .dragging : .ready }
    }
    mutating func preserveSelection() { if phase == .dragging { phase = .ready } }
    mutating func cancel() { if phase != .idle { phase = .locked } }
    /// Delivery verification may outlive a physical release/press cycle. Keep
    /// observing releases and let a fresh press invalidate the old delivery.
    mutating func retryDuringDelivery(held: Bool) -> Bool {
        if !held { modifiers(held: false) }
        return held && phase == .idle
    }
    mutating func drop(valid: Bool) -> Bool {
        let deliver = phase == .dragging && valid
        if phase == .dragging { phase = .locked }
        return deliver
    }
}

struct CapturePayload {
    let title: String
    let url: URL?
    let text: String
    init(title: String, url: URL) {
        self.title = title; self.url = url
        self.text = title.isEmpty || title == url.absoluteString ? url.absoluteString : TextFragment.link(title, url).markdown
    }
    init(title: String, markdown: String) {
        self.title = title; self.url = nil; self.text = markdown
    }
}

/// Coalesce pointer noise without repeatedly walking the same paragraph's AX tree.
struct HoverProbeCadence {
    private var lastProbe: TimeInterval?
    mutating func reset() { lastProbe = nil }
    func delayUntilNextProbe(at time: TimeInterval, sameBlock: Bool) -> TimeInterval {
        guard let lastProbe else { return 0 }
        let interval: TimeInterval = sameBlock ? 0.12 : 1 / 30
        return max(0, lastProbe + interval - time)
    }
    mutating func shouldProbe(at time: TimeInterval, sameBlock: Bool) -> Bool {
        guard delayUntilNextProbe(at: time, sameBlock: sameBlock) <= 0 else { return false }
        lastProbe = time
        return true
    }
}

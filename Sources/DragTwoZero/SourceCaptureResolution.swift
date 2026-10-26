import AppKit

enum SelectedTextLookup {
    case none
    case selected(CaptureCandidate)
    case unavailable
}

struct SourceCaptureLookup {
    let candidate: CaptureCandidate?
    let allowsMarquee: Bool
    var selectionForScroll: CaptureCandidate? = nil

    static func resolve(enabled: Bool, at point: CGPoint, selection: () -> SelectedTextLookup,
                        block: () -> CaptureCandidate?) -> Self {
        resolve(enabled ? selection() : .none, at: point, block: block)
    }

    static func resolve(_ selection: SelectedTextLookup, at point: CGPoint,
                        block: () -> CaptureCandidate?) -> Self {
        switch selection {
        case .none: return Self(candidate: block(), allowsMarquee: true)
        case .selected(let selected):
            if selected.containsVisiblePoint(point) {
                return Self(candidate: selected, allowsMarquee: true, selectionForScroll: selected)
            }
            // The starting point chooses the source. Unselected text remains
            // a whole-block target even inside the selected paragraph.
            let other = block().flatMap { candidate in
                candidate.selectedTextRange == nil && candidate.containsVisiblePoint(point) ? candidate : nil
            }
            return Self(candidate: other, allowsMarquee: true, selectionForScroll: selected)
        case .unavailable: return Self(candidate: nil, allowsMarquee: false)
        }
    }

    static func validate(_ expected: CaptureCandidate, selection: () -> CaptureCandidate?,
                         block: () -> CaptureCandidate?) -> CaptureCandidate? {
        expected.selectedTextRange != nil ? selection() : block()
    }
}

/// Hover discovery is a snapshot for one shortcut gesture. Acceptance always
/// reads fresh data without this cache. Replace the session after scrolling.
final class SelectionCaptureSession {
    private let lock = NSLock()
    private var entries: [(AXUIElement, SelectedTextLookup)] = []

    func resolve(_ owner: AXUIElement, read: () -> SelectedTextLookup) -> SelectedTextLookup {
        lock.lock()
        let cached = entries.first { CFEqual($0.0, owner) }?.1
        lock.unlock()
        if let cached { return cached }
        let result = read()
        if case .unavailable = result { return result }
        lock.lock()
        // Bound retained AX references even when sweeping a large document.
        if entries.count >= 128 { entries.removeFirst() }
        entries.append((owner, result))
        lock.unlock()
        return result
    }
}

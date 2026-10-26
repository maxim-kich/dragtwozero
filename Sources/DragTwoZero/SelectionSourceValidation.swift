import AppKit

/// Visible members need a fresh topmost hit; clipped retained members need the
/// original AX anchor to resolve to the same document and exact content.
enum SelectionSourceValidation {
    static func resolve(_ expected: [CaptureCandidate], adapters: [SourceAdapter], shouldStop: () -> Bool = { false }) -> [CaptureCandidate]? {
        resolve(expected, visibleSource: { point in
            hitTest(point).flatMap { element in
                sourceCandidate(at: element, containing: point, adapters: adapters, shouldStop: shouldStop)
            }
        }, retainedSource: { anchor in
            sourceCandidate(at: anchor, adapters: adapters, shouldStop: shouldStop)
        }, shouldStop: shouldStop)
    }

    static func resolve(_ expected: [CaptureCandidate],
                        visibleSource: (CGPoint) -> CaptureCandidate?,
                        retainedSource: (AXUIElement) -> CaptureCandidate?, shouldStop: () -> Bool = { false }) -> [CaptureCandidate]? {
        var current: [CaptureCandidate] = []
        for block in expected {
            guard !shouldStop() else { return nil }
            let fresh: CaptureCandidate?
            if let frame = block.visibleFrame, !frame.isEmpty {
                fresh = visibleSource(CGPoint(x: frame.midX, y: frame.midY))
            } else if let anchor = block.anchor {
                fresh = retainedSource(anchor)
            } else { return nil }
            guard !shouldStop(), let fresh else { return nil }
            current.append(fresh)
        }
        return matches(expected, current) ? current : nil
    }

    static func matches(_ expected: [CaptureCandidate], _ current: [CaptureCandidate]) -> Bool {
        !expected.isEmpty && expected.count == current.count && zip(expected, current).allSatisfy { old, fresh in
            if let frame = old.visibleFrame, !frame.isEmpty {
                return old.matchesCurrentSource(fresh, at: CGPoint(x: frame.midX, y: frame.midY))
            }
            return old.matchesRetainedSource(fresh)
        }
    }
}

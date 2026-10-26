import AppKit
import ApplicationServices

func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
           width: max(1, abs(end.x - start.x)), height: max(1, abs(end.y - start.y)))
}

/// Inclusive edge contact, not full enclosure, selects a block.
func selectionTouches(_ selection: CGRect, _ block: CGRect) -> Bool {
    selection.minX <= block.maxX && selection.maxX >= block.minX
        && selection.minY <= block.maxY && selection.maxY >= block.minY
}

/// Keep whole blocks, suppress nested link/run duplicates, and preserve spatial order.
func selectedBlocks(_ candidates: [CaptureCandidate], in rect: CGRect) -> [CaptureCandidate] {
    var result: [CaptureCandidate] = []
    for candidate in candidates.filter({ selectionTouches(rect, $0.frame) }).sorted(by: {
        $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
    }) {
        if result.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(candidate.frame) }) { continue }
        result.append(candidate)
    }
    return result.sorted {
        if abs($0.frame.minY - $1.frame.minY) > 4 { return $0.frame.minY < $1.frame.minY }
        return $0.frame.minX < $1.frame.minX
    }
}

func combinedSelection(_ blocks: [CaptureCandidate]) -> CaptureCandidate? {
    guard let first = blocks.first else { return nil }
    if blocks.count == 1 { return first }
    return CaptureCandidate(payload: .init(title: "\(blocks.count) elements", markdown: blocks.map { $0.payload.text }.joined(separator: "\n\n")),
                            frame: blocks.dropFirst().reduce(first.frame) { $0.union($1.frame) })
}

/// Release commits the selection the user can see. A background scan must not
/// add unseen members or discard highlighted members because it is unfinished.
enum SelectionReleaseResolution {
    case captured(CaptureCandidate)
    case finishDiscovery
    case cancel

    static func resolve(_ highlighted: [CaptureCandidate], discoveryComplete: Bool) -> Self {
        if let captured = combinedSelection(highlighted) { return .captured(captured) }
        return discoveryComplete ? .cancel : .finishDiscovery
    }
}

final class SelectionScanControl {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// Stay inside the source window and skip offscreen branches and editable content.
struct MarqueeDiscovery {
    let blocks: [CaptureCandidate]
    let isComplete: Bool
}

func marqueeCandidates(root: AXUIElement, rect: CGRect, adapters: [SourceAdapter], shouldStop: () -> Bool = { false }, near point: CGPoint? = nil, progress: ([CaptureCandidate]) -> Void = { _ in }) -> MarqueeDiscovery {
    var result: [CaptureCandidate] = []
    var visited = 0
    var complete = true
    var lastPublish: TimeInterval = 0
    func walk(_ node: AXUIElement, depth: Int) {
        visited += 1
        guard !shouldStop(), visited <= 2000, depth < 40 else { complete = false; return }
        guard let role = attribute(node, kAXRoleAttribute) as? String else { complete = false; return }
        guard !["AXTextArea", "AXTextField", "AXSecureTextField"].contains(role) else { return }
        if let frame = bounds(node), !selectionTouches(rect, frame) { return }
        if ["AXStaticText", "AXInlineTextBox", "AXLink", "AXHeading", "AXParagraph", "AXListItem"].contains(role),
           let candidate = sourceCandidate(at: node, adapters: adapters, shouldStop: shouldStop) {
            result.append(candidate)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastPublish >= 1 / 60 {
                lastPublish = now
                progress(selectedBlocks(result, in: rect))
            }
            return
        }
        var rawChildren: CFTypeRef?
        let childrenStatus = AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &rawChildren)
        if childrenStatus != .success && childrenStatus != .attributeUnsupported && childrenStatus != .noValue {
            complete = false; return
        }
        let children = rawChildren as? [AXUIElement] ?? []
        // Resolve nearby branches first so visible feedback does not wait for
        // unrelated content earlier in the accessibility tree.
        let ordered: [AXUIElement]
        if let point {
            var distances: [(AXUIElement, CGFloat)] = []
            for child in children {
                guard !shouldStop() else { complete = false; return }
                guard let box = bounds(child) else { distances.append((child, 0)); continue }
                let dx = max(box.minX - point.x, 0, point.x - box.maxX)
                let dy = max(box.minY - point.y, 0, point.y - box.maxY)
                distances.append((child, dx * dx + dy * dy))
            }
            ordered = distances.sorted { $0.1 < $1.1 }.map { $0.0 }
        } else { ordered = children }
        for child in ordered {
            guard !shouldStop(), visited < 2000 else { complete = false; break }
            walk(child, depth: depth + 1)
        }
    }
    walk(root, depth: 0)
    return MarqueeDiscovery(blocks: selectedBlocks(result, in: rect), isComplete: complete && !shouldStop())
}

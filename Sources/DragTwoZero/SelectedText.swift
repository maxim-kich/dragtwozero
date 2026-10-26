import AppKit
import ApplicationServices

enum SelectedTextMarkers {
    static func sameMarker(_ lhs: AXTextMarker, _ rhs: AXTextMarker) -> Bool {
        let count = AXTextMarkerGetLength(lhs)
        guard count > 0, count == AXTextMarkerGetLength(rhs) else { return false }
        let left = AXTextMarkerGetBytePtr(lhs), right = AXTextMarkerGetBytePtr(rhs)
        return UnsafeBufferPointer(start: left, count: count).elementsEqual(UnsafeBufferPointer(start: right, count: count))
    }
    static func sameRange(_ lhs: AXTextMarkerRange?, _ rhs: AXTextMarkerRange?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            return sameMarker(AXTextMarkerRangeCopyStartMarker(lhs), AXTextMarkerRangeCopyStartMarker(rhs))
                && sameMarker(AXTextMarkerRangeCopyEndMarker(lhs), AXTextMarkerRangeCopyEndMarker(rhs))
        default: return false
        }
    }
}

/// Split only the selected UTF-16 range at visual line boundaries. Never use
/// the enclosing paragraph rectangle for a partial or wrapped selection.
enum SelectedTextGeometry {
    /// A line range must agree with a tiny range at its start. AX providers
    /// sometimes return a whole document/window instead of text bounds.
    static func isTextLine(_ frame: CGRect, character: CGRect, length: Int, container: CGRect?) -> Bool {
        guard length > 0, !frame.isNull, !frame.isInfinite, !character.isNull, !character.isInfinite,
              frame.width > 0, frame.height > 0, character.height > 0,
              frame.width.isFinite, frame.height.isFinite, character.width.isFinite, character.height.isFinite,
              frame.height <= character.height * 2 + 2,
              frame.width <= max(character.width, character.height) * min(Double(length) + 1, 32_001),
              frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: character.midX, y: character.midY)) else { return false }
        if let container, container.width > 0, container.height > 0,
           character.width >= container.width * 0.9, character.height >= container.height * 0.9 { return false }
        return true
    }
    static func frames(for selection: CFRange, lineRange: (Int) -> CFRange?,
                       bounds: (CFRange) -> CGRect?, shouldStop: () -> Bool = { false }) -> [CGRect]? {
        guard selection.location >= 0, selection.length > 0,
              selection.location <= Int.max - selection.length else { return nil }
        let end = selection.location + selection.length
        var index = selection.location
        var frames: [CGRect] = []
        var lines = 0
        while index < end {
            guard !shouldStop(), lines < 512 else { return nil }
            var resolved = lineRange(index)
            // AX can assign a boundary index to the preceding visual line.
            // Ask just inside the following line while retaining the original
            // selected start; never skip its first character.
            if let line = resolved, line.location >= 0, line.length >= 0,
               line.location <= Int.max - line.length, line.location + line.length == index,
               index + 1 < end { resolved = lineRange(index + 1) }
            guard let line = resolved,
                  line.location >= 0, line.length > 0, line.location <= index,
                  line.location <= Int.max - line.length, line.location + line.length > index else { return nil }
            let next = min(end, line.location + line.length)
            guard let frame = bounds(CFRange(location: index, length: next - index)),
                  !frame.isNull, !frame.isInfinite,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite else { return nil }
            if frame.width > 0, frame.height > 0 { frames.append(frame) }
            index = next
            lines += 1
        }
        return frames.isEmpty ? nil : frames
    }
    static func mergeGlyphs(_ glyphs: [CGRect]) -> [CGRect] {
        var lines: [CGRect] = []
        for glyph in glyphs {
            if let last = lines.last {
                let overlap = min(last.maxY, glyph.maxY) - max(last.minY, glyph.minY)
                let gap = max(last.minX, glyph.minX) - min(last.maxX, glyph.maxX)
                if overlap >= min(last.height, glyph.height) * 0.7 && gap <= 2 {
                    lines[lines.count - 1] = last.union(glyph)
                    continue
                }
            }
            lines.append(glyph)
        }
        return lines
    }
    static func visibleRange(_ range: CFRange, selection: CFRange, text: [UInt16]) -> CFRange {
        guard text.count == selection.length else { return range }
        var length = range.length
        while length > 0 {
            let offset = range.location - selection.location + length - 1
            guard text.indices.contains(offset), [10, 13, 0x2028, 0x2029].contains(text[offset]) else { break }
            length -= 1
        }
        return CFRange(location: range.location, length: length)
    }
    static func firstGlyphRange(_ range: CFRange, selection: CFRange, text: [UInt16]) -> CFRange {
        let offset = range.location - selection.location
        let pair = range.length >= 2 && text.indices.contains(offset + 1)
            && (0xD800...0xDBFF).contains(text[offset]) && (0xDC00...0xDFFF).contains(text[offset + 1])
        return CFRange(location: range.location, length: pair ? 2 : min(1, range.length))
    }
}

/// An input's local selection must not suppress unrelated blocks in its page.
/// Both opaque marker endpoints must prove the same editable owner; focus or
/// an unreadable selection alone is insufficient evidence to ignore it.
enum EditorSelectionScope {
    static func isOutsideSelectedEditor<Node>(hitChain: [Node], startChain: [Node], endChain: [Node],
                                              webArea: Node, same: (Node, Node) -> Bool,
                                              role: (Node) -> String, shouldStop: () -> Bool = { false }) -> Bool {
        guard !shouldStop() else { return false }
        guard [hitChain, startChain, endChain].allSatisfy({ chain in chain.contains { same($0, webArea) } }) else { return false }
        let editorRoles = ["AXTextArea", "AXTextField", "AXComboBox", "AXSecureTextField"]
        guard let editor = startChain.first(where: { node in
            !shouldStop() && editorRoles.contains(role(node)) && endChain.contains { same($0, node) }
        }) else { return false }
        return !shouldStop() && !hitChain.contains { same($0, editor) }
    }
}

struct AccessibleSelectedTextAdapter {
    func candidate(at hit: AXUIElement, containing point: CGPoint) -> CaptureCandidate? {
        if case let .selected(candidate) = lookup(at: hit), candidate.containsVisiblePoint(point) { return candidate }
        return nil
    }

    func lookup(at hit: AXUIElement, session: SelectionCaptureSession? = nil) -> SelectedTextLookup {
        if let session { return session.resolve(hit) { lookupUncached(at: hit, session: session) } }
        return lookupUncached(at: hit, session: nil)
    }

    private func lookupUncached(at hit: AXUIElement, session: SelectionCaptureSession?) -> SelectedTextLookup {
        let chain = ancestors(hit, limit: 40)
        // Check eligibility before requesting any selected content.
        guard !chain.contains(where: { isSecure($0) }) else { return .unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        let webArea = chain.first { attribute($0, kAXRoleAttribute) as? String == "AXWebArea" }
        // A browser's leaf nodes often advertise local range APIs but cannot
        // resolve a selection spanning nodes. Reach its selection owner first.
        if let webArea {
            if let scoped = selectionOutsideEditor(at: webArea, hitChain: chain, deadline: deadline) { return scoped }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
            let read = { browserLookup(at: webArea, deadline: deadline) }
            return session.map { $0.resolve(webArea, read: read) } ?? read()
        }
        for node in chain {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
            var raw: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(node, kAXSelectedTextRangeAttribute as CFString, &raw)
            if status == .success {
                guard let range = InputTarget.selectedRange(node) else { return .unavailable }
                if range.length > 0 {
                    return candidate(at: node, deadline: deadline).map(SelectedTextLookup.selected) ?? .unavailable
                }
                // Native text owners expose a zero-length caret when nothing is selected.
                let role = attribute(node, kAXRoleAttribute) as? String ?? ""
                if ["AXTextArea", "AXTextField"].contains(role) { return .none }
            } else if status != .attributeUnsupported && status != .noValue {
                return .unavailable
            }
            if attribute(node, kAXRoleAttribute) as? String == "AXWindow" { break }
        }
        return .none
    }

    private func selectionOutsideEditor(at webArea: AXUIElement, hitChain: [AXUIElement],
                                         deadline: TimeInterval) -> SelectedTextLookup? {
        guard let raw = attribute(webArea, "AXSelectedTextMarkerRange"),
              CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        let range = raw as! AXTextMarkerRange
        let start = AXTextMarkerRangeCopyStartMarker(range), end = AXTextMarkerRangeCopyEndMarker(range)
        guard !SelectedTextMarkers.sameMarker(start, end),
              ProcessInfo.processInfo.systemUptime < deadline,
              let startOwner = axElement(parameter(webArea, "AXUIElementForTextMarker", start)),
              let endOwner = axElement(parameter(webArea, "AXUIElementForTextMarker", end)) else { return nil }
        let stop = { ProcessInfo.processInfo.systemUptime >= deadline }
        let startChain = ancestors(startOwner, limit: 40, shouldStop: stop)
        let endChain = ancestors(endOwner, limit: 40, shouldStop: stop)
        guard !stop(), EditorSelectionScope.isOutsideSelectedEditor(hitChain: hitChain,
            startChain: startChain, endChain: endChain, webArea: webArea,
            same: { CFEqual($0, $1) }, role: { attribute($0, kAXRoleAttribute) as? String ?? "" },
            shouldStop: stop) else { return nil }
        guard !stop(), let current = attribute(webArea, "AXSelectedTextMarkerRange"),
              CFGetTypeID(current) == AXTextMarkerRangeGetTypeID(),
              SelectedTextMarkers.sameRange(range, current as! AXTextMarkerRange), !stop() else { return .unavailable }
        // This result belongs to this hit only. Do not store it in the shared
        // web-area cache: moving onto the selected input must still read it.
        return SelectedTextLookup.none
    }

    private func browserLookup(at element: AXUIElement, deadline: TimeInterval) -> SelectedTextLookup {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &raw)
        if status == .noValue || status == .attributeUnsupported {
            // Some web views expose only native ranges. A known selection must
            // never be silently widened just because marker support is absent.
            if let range = InputTarget.selectedRange(element), range.length > 0 { return .unavailable }
            if let text = attribute(element, kAXSelectedTextAttribute) as? String, !text.isEmpty { return .unavailable }
            return .none
        }
        guard status == .success, let raw, CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return .unavailable }
        let range = raw as! AXTextMarkerRange
        if SelectedTextMarkers.sameMarker(AXTextMarkerRangeCopyStartMarker(range), AXTextMarkerRangeCopyEndMarker(range)) { return .none }
        return markerCandidate(at: element, deadline: deadline).map(SelectedTextLookup.selected) ?? .unavailable
    }

    func candidate(at element: AXUIElement) -> CaptureCandidate? {
        guard !ancestors(element, limit: 40).contains(where: { isSecure($0) }) else { return nil }
        return candidate(at: element, deadline: ProcessInfo.processInfo.systemUptime + 0.3)
    }

    private func isSecure(_ node: AXUIElement) -> Bool {
        attribute(node, kAXRoleAttribute) as? String == "AXSecureTextField"
            || attribute(node, kAXSubroleAttribute) as? String == "AXSecureTextField"
    }

    private func parameter(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, value, &result) == .success else { return nil }
        return result
    }

    private func viewportBounds(_ element: AXUIElement) -> CGRect? {
        var node = element
        for _ in 0..<12 {
            if ["AXScrollArea", "AXWindow"].contains(attribute(node, kAXRoleAttribute) as? String ?? "") { return bounds(node) }
            guard let parent = axElement(attribute(node, kAXParentAttribute)) else { break }
            node = parent
        }
        return bounds(element)
    }

    private func candidate(at element: AXUIElement, deadline: TimeInterval) -> CaptureCandidate? {
        if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
            return markerCandidate(at: element, deadline: deadline)
        }
        guard let selection = InputTarget.selectedRange(element), selection.length > 0,
              selection.length <= 32_000, selection.location <= Int.max - selection.length,
              let text = attribute(element, kAXSelectedTextAttribute) as? String,
              text.utf16.count == selection.length else { return nil }
        let container = viewportBounds(element)
        func rangeBounds(_ selected: CFRange) -> CGRect? {
            var range = selected
            guard let value = AXValueCreate(.cfRange, &range),
                  let raw = parameter(element, kAXBoundsForRangeParameterizedAttribute, value), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var frame = CGRect.zero
            return AXValueGetValue(raw as! AXValue, .cgRect, &frame) ? frame : nil
        }
        let units = Array(text.utf16)
        let frames = SelectedTextGeometry.frames(for: selection, lineRange: { index in
            guard let line = parameter(element, kAXLineForIndexParameterizedAttribute, NSNumber(value: index)),
                  let raw = parameter(element, kAXRangeForLineParameterizedAttribute, line),
                  CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
            return range
        }, bounds: { selected in
            let visible = SelectedTextGeometry.visibleRange(selected, selection: selection, text: units)
            if visible.length == 0 { return .zero }
            guard let frame = rangeBounds(visible),
                  let character = rangeBounds(SelectedTextGeometry.firstGlyphRange(visible, selection: selection, text: units)),
                  SelectedTextGeometry.isTextLine(frame, character: character, length: visible.length, container: container) else { return nil }
            return frame
        }, shouldStop: { ProcessInfo.processInfo.systemUptime >= deadline })
        guard let frames else { return nil }
        var selectedRange = selection
        let attributed = AXValueCreate(.cfRange, &selectedRange).flatMap {
            parameter(element, kAXAttributedStringForRangeParameterizedAttribute, $0) as? NSAttributedString
        }
        // A source app can change its selection while the line bounds are read.
        guard let current = InputTarget.selectedRange(element),
              current.location == selection.location, current.length == selection.length,
              let currentText = attribute(element, kAXSelectedTextAttribute) as? String,
              text.utf16.elementsEqual(currentText.utf16) else { return nil }
        let frame = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let markdown = SelectedTextFormatting.markdown(text, attributed: attributed, preserveStructure: CapturePreferences.preserveStructure)
        var candidate = CaptureCandidate(payload: .init(title: "Selected text", markdown: markdown), frame: frame)
        candidate = candidate.anchored(to: element)
        // Selection identity belongs to the range's owner, even when a line
        // happens to have the same bounds as an ancestor.
        candidate.anchor = element
        candidate.anchorFrame = bounds(element)
        candidate.selectedTextRange = selection
        candidate.textFrames = frames
        return candidate
    }

    /// Browser selections span multiple AX nodes. Their owner is the web area,
    /// and their identity is a pair of opaque text markers, not a local CFRange.
    private func markerCandidate(at element: AXUIElement, deadline: TimeInterval) -> CaptureCandidate? {
        guard let raw = attribute(element, "AXSelectedTextMarkerRange"),
              CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        let selected = raw as! AXTextMarkerRange
        guard let text = parameter(element, "AXStringForTextMarkerRange", selected) as? String,
              !text.isEmpty, text.utf16.count <= 32_000 else { return nil }
        let orderedRaw = parameter(element, "AXTextMarkerRangeForUnorderedTextMarkers",
            [AXTextMarkerRangeCopyStartMarker(selected), AXTextMarkerRangeCopyEndMarker(selected)] as CFArray)
        let ordered = orderedRaw.flatMap { CFGetTypeID($0) == AXTextMarkerRangeGetTypeID() ? ($0 as! AXTextMarkerRange) : nil } ?? selected
        let units = Array(text.utf16)
        let container = viewportBounds(element)
        func walk(from start: AXTextMarker, to end: AXTextMarker) -> [CGRect]? {
            var current = start
            var offset = 0, emptyTransitions = 0
            var glyphs: [CGRect] = []
            // Follow opaque positions rather than interpreting node-local offsets.
            while offset < units.count {
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      let rawNext = parameter(element, "AXNextTextMarkerForTextMarker", current),
                      CFGetTypeID(rawNext) == AXTextMarkerGetTypeID() else { return nil }
                let next = rawNext as! AXTextMarker
                guard !SelectedTextMarkers.sameMarker(current, next) else { return nil }
                let segment = AXTextMarkerRangeCreate(kCFAllocatorDefault, current, next)
                guard let fragment = parameter(element, "AXStringForTextMarkerRange", segment) as? String else { return nil }
                let fragmentUnits = Array(fragment.utf16)
                if fragmentUnits.isEmpty {
                    emptyTransitions += 1
                    guard emptyTransitions <= 512 else { return nil }
                    current = next; continue
                }
                guard fragmentUnits.count <= units.count - offset,
                      units[offset..<(offset + fragmentUnits.count)].elementsEqual(fragmentUnits) else { return nil }
                if !fragmentUnits.allSatisfy({ [10, 13, 0x2028, 0x2029].contains($0) }) {
                    guard let raw = parameter(element, "AXBoundsForTextMarkerRange", segment), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
                    var frame = CGRect.zero
                    guard AXValueGetValue(raw as! AXValue, .cgRect, &frame) else { return nil }
                    if frame.width > 0 && frame.height > 0 {
                        guard SelectedTextGeometry.isTextLine(frame, character: frame, length: fragmentUnits.count, container: container) else { return nil }
                        glyphs.append(frame)
                    }
                }
                current = next; offset += fragmentUnits.count
            }
            if !SelectedTextMarkers.sameMarker(current, end) {
                let remainder = AXTextMarkerRangeCreate(kCFAllocatorDefault, current, end)
                guard let tail = parameter(element, "AXStringForTextMarkerRange", remainder) as? String, tail.isEmpty else { return nil }
            }
            let frames = SelectedTextGeometry.mergeGlyphs(glyphs)
            return frames.isEmpty || frames.count > 512 ? nil : frames
        }
        let start = AXTextMarkerRangeCopyStartMarker(ordered), end = AXTextMarkerRangeCopyEndMarker(ordered)
        guard let frames = walk(from: start, to: end) ?? walk(from: end, to: start) else { return nil }
        // Browser selection identity is its opaque range, not node-local offsets.
        let selection = CFRange(location: 0, length: units.count)
        // Modern Chromium advertises the options form; WebKit can also expose
        // the older attribute. Spell checking is unrelated to capture and can
        // make this read substantially slower.
        let options = ["AXTextMarkerRange": selected, "AXSpellCheck": false] as CFDictionary
        let attributed = (parameter(element, "AXAttributedStringForTextMarkerRangeWithOptions", options) as? NSAttributedString)
            ?? (parameter(element, "AXAttributedStringForTextMarkerRange", selected) as? NSAttributedString)
        guard let current = attribute(element, "AXSelectedTextMarkerRange"),
              CFGetTypeID(current) == AXTextMarkerRangeGetTypeID(),
              SelectedTextMarkers.sameRange(selected, (current as! AXTextMarkerRange)),
              let currentText = parameter(element, "AXStringForTextMarkerRange", current) as? String,
              text.utf16.elementsEqual(currentText.utf16) else { return nil }
        let frame = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let markdown = SelectedTextFormatting.markdown(text, attributed: attributed, preserveStructure: CapturePreferences.preserveStructure)
        var candidate = CaptureCandidate(payload: .init(title: "Selected text", markdown: markdown), frame: frame).anchored(to: element)
        candidate.anchor = element; candidate.anchorFrame = bounds(element)
        candidate.selectedTextRange = selection
        candidate.selectedTextMarkerRange = selected
        candidate.textFrames = frames
        return candidate
    }
}

/// A paragraph's union rectangle includes line gaps and trailing blank space.
/// Prefer the actual character under the press when a provider exposes it.
enum SourceTextPoint {
    static func contains(_ point: CGPoint, in hit: AXUIElement) -> Bool? {
        let chain = ancestors(hit, limit: 40)
        func parameter(_ owner: AXUIElement, _ name: String, _ value: CFTypeRef) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyParameterizedAttributeValue(owner, name as CFString, value, &result) == .success ? result : nil
        }
        func rectangle(_ raw: CFTypeRef?) -> CGRect? {
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var frame = CGRect.zero
            return AXValueGetValue(raw as! AXValue, .cgRect, &frame) ? frame : nil
        }
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return nil }
        if let web = chain.first(where: { attribute($0, kAXRoleAttribute) as? String == "AXWebArea" }) {
            guard let first = parameter(web, "AXTextMarkerForPosition", value), CFGetTypeID(first) == AXTextMarkerGetTypeID(),
                  let next = parameter(web, "AXNextTextMarkerForTextMarker", first), CFGetTypeID(next) == AXTextMarkerGetTypeID() else { return nil }
            var segments = [(first as! AXTextMarker, next as! AXTextMarker)]
            if let previous = parameter(web, "AXPreviousTextMarkerForTextMarker", first), CFGetTypeID(previous) == AXTextMarkerGetTypeID() {
                segments.append((previous as! AXTextMarker, first as! AXTextMarker))
            }
            var measured = false
            for (start, end) in segments {
                let range = AXTextMarkerRangeCreate(kCFAllocatorDefault, start, end)
                guard let text = parameter(web, "AXStringForTextMarkerRange", range) as? String,
                      !text.isEmpty, !text.utf16.allSatisfy({ [10, 13, 0x2028, 0x2029].contains($0) }),
                      let frame = rectangle(parameter(web, "AXBoundsForTextMarkerRange", range)) else { continue }
                measured = true
                if !frame.isNull && frame.width > 0 && frame.height > 0 && frame.contains(point) { return true }
            }
            return measured ? false : nil
        }
        for node in chain.prefix(8) {
            guard let range = parameter(node, kAXRangeForPositionParameterizedAttribute, value) else { continue }
            guard let frame = rectangle(parameter(node, kAXBoundsForRangeParameterizedAttribute, range)) else { continue }
            return !frame.isNull && frame.width > 0 && frame.height > 0 && frame.contains(point)
        }
        return nil
    }
}

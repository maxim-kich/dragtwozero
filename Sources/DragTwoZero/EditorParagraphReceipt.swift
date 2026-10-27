import AppKit

/// Chromium's legacy selection indexes and AXValue disagree at paragraph
/// boundaries. Use complete owned paragraph text and opaque marker endpoints
/// for an independent receipt; never reinterpret the authorized legacy range.
enum EditorParagraphReceipt {
    struct Text: Equatable {
        let body: String
        let marker: String
        var prefix: String = ""
        var markup: String? = nil
        var value: String { prefix + body }
        static func == (a: Self, b: Self) -> Bool {
            let sameMarkup: Bool
            switch (a.markup, b.markup) {
            case (nil, nil): sameMarkup = true
            case let (left?, right?): sameMarkup = left.utf16.elementsEqual(right.utf16)
            default: sameMarkup = false
            }
            return a.body.utf16.elementsEqual(b.body.utf16) && a.marker.utf16.elementsEqual(b.marker.utf16)
                && a.prefix.utf16.elementsEqual(b.prefix.utf16)
                && sameMarkup
        }
    }
    struct Boundary {
        let paragraph: Int
        let prefix: String
        let suffix: String
    }
    struct Paragraph {
        let element: AXUIElement
        let range: AXTextMarkerRange
        let text: Text
        let frame: CGRect
    }
    struct Snapshot {
        let value: String
        let range: AXTextMarkerRange
        let markerText: String
        let paragraphs: [Paragraph]
        var text: String { paragraphs.map { $0.text.value }.joined(separator: "\n") }
        var markup: String? {
            guard paragraphs.allSatisfy({ $0.text.markup != nil }) else { return nil }
            return paragraphs.map { $0.text.prefix + ($0.text.markup ?? "") }.joined(separator: "\n")
        }
    }
    struct Before {
        let state: EditorInsertionState
        let plainBeforeMarkup: Bool
        func confirms(_ payload: String, text: String, markup: String?) -> Bool {
            state.confirmsLineNormalizedInsertion(of: payload, observed: text)
                || (plainBeforeMarkup && markup.map { state.confirmsLineNormalizedInsertion(of: payload, observed: $0) } == true)
        }
    }
    struct Receipt {
        let text: String
        let markup: String?
    }

    static func follows(_ frame: CGRect, _ previous: CGRect) -> Bool {
        // AX rounds the 22.5-point line boxes of real Chromium paragraphs to
        // integral rectangles, so neighboring boxes can overlap by one point.
        frame.minY > previous.minY && frame.minY >= previous.maxY - 1
    }

    static func insertionState(_ paragraphs: [Text], start: Boundary, end: Boundary) -> EditorInsertionState? {
        guard !paragraphs.isEmpty, paragraphs.count <= 256, paragraphs.allSatisfy({ block in
            (block.body.isEmpty && block.prefix.isEmpty && block.marker == "\n")
                || block.marker.utf16.elementsEqual(block.body.utf16) || block.marker.utf16.elementsEqual(block.value.utf16)
        }) else { return nil }
        func offset(_ boundary: Boundary) -> Int? {
            guard paragraphs.indices.contains(boundary.paragraph) else { return nil }
            let block = paragraphs[boundary.paragraph]
            guard (boundary.prefix + boundary.suffix).utf16.elementsEqual(block.marker.utf16) else { return nil }
            let local: Int
            if block.body.isEmpty, block.prefix.isEmpty, block.marker == "\n" {
                local = 0 // The empty paragraph's layout marker is not user text.
            } else if block.marker.utf16.elementsEqual(block.value.utf16) {
                local = boundary.prefix.utf16.count
                guard local >= block.prefix.utf16.count else { return nil }
            } else if block.marker.utf16.elementsEqual(block.body.utf16) {
                local = block.prefix.utf16.count + boundary.prefix.utf16.count
            } else { return nil }
            return paragraphs.prefix(boundary.paragraph).reduce(0) { $0 + $1.value.utf16.count + 1 } + local
        }
        guard let first = offset(start), let last = offset(end), last >= first else { return nil }
        let text = paragraphs.map(\.value).joined(separator: "\n")
        guard text.utf16.count <= 1_000_000, !text.utf16.contains(0xFFFC) else { return nil }
        let state = EditorInsertionState(location: first, length: last - first, value: text)
        return state.hasValidRange ? state : nil
    }

    static func selectedRange(_ editor: AXUIElement) -> AXTextMarkerRange? {
        guard let raw = attribute(editor, "AXSelectedTextMarkerRange"),
              CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        let selected = raw as! AXTextMarkerRange
        // A provider may publish the document's selection on an input whose
        // own caret uses only the legacy API. Never bind that foreign range.
        for marker in [AXTextMarkerRangeCopyStartMarker(selected), AXTextMarkerRangeCopyEndMarker(selected)] {
            guard let owner = axElement(parameter(editor, "AXUIElementForTextMarker", marker, valid: { true })),
                  ancestors(owner, limit: 8).contains(where: { CFEqual($0, editor) }) else { return nil }
        }
        return selected
    }

    private static func parameter(_ editor: AXUIElement, _ name: String, _ input: CFTypeRef, valid: () -> Bool) -> CFTypeRef? {
        guard valid() else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(editor, name as CFString, input, &raw) == .success, valid() else { return nil }
        return raw
    }
    private static func range(_ editor: AXUIElement, _ node: AXUIElement, valid: () -> Bool) -> AXTextMarkerRange? {
        guard let raw = parameter(editor, "AXTextMarkerRangeForUIElement", node, valid: valid),
              CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        return (raw as! AXTextMarkerRange)
    }
    private static func string(_ editor: AXUIElement, _ range: AXTextMarkerRange, valid: () -> Bool) -> String? {
        guard let text = parameter(editor, "AXStringForTextMarkerRange", range, valid: valid) as? String,
              text.utf16.count <= 1_000_000, !text.utf16.contains(0xFFFC) else { return nil }
        return text
    }

    private static func snapshot(_ editor: AXUIElement, valid: () -> Bool) -> Snapshot? {
        guard valid(), attribute(editor, kAXRoleAttribute) as? String == "AXTextArea",
              let value = attribute(editor, kAXValueAttribute) as? String, value.utf16.count <= 1_000_000,
              let children = attribute(editor, kAXChildrenAttribute) as? [AXUIElement],
              !children.isEmpty, children.count <= 256, let whole = range(editor, editor, valid: valid) else { return nil }
        var paragraphs: [Paragraph] = [], remaining = 512, remainingText = 1_000_000
        func owned(_ node: AXUIElement, by parent: AXUIElement) -> Bool {
            remaining -= 1
            guard valid(), remaining >= 0, let owner = axElement(attribute(node, kAXParentAttribute)) else { return false }
            return CFEqual(owner, parent)
        }
        func inline(_ node: AXUIElement, parent: AXUIElement, depth: Int) -> String? {
            guard depth < 12, owned(node, by: parent), let role = attribute(node, kAXRoleAttribute) as? String else { return nil }
            if ["AXStaticText", "AXInlineTextBox"].contains(role) {
                guard let text = attribute(node, kAXValueAttribute) as? String,
                      text.utf16.count <= remainingText, !text.utf16.contains(0xFFFC) else { return nil }
                remainingText -= text.utf16.count
                return text
            }
            guard ["AXGroup", "AXLink"].contains(role),
                  let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty else { return nil }
            var text = ""
            for child in children {
                guard let part = inline(child, parent: node, depth: depth + 1) else { return nil }
                text += part
            }
            return text
        }
        func block(_ node: AXUIElement, parent: AXUIElement, depth: Int) -> Bool {
            guard depth < 12, owned(node, by: parent), let role = attribute(node, kAXRoleAttribute) as? String,
                  let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] else { return false }
            if role == "AXList" {
                guard !children.isEmpty else { return false }
                return children.allSatisfy { block($0, parent: node, depth: depth + 1) }
            }
            guard role == "AXGroup", attribute(node, kAXValueAttribute) as? String == "",
                  let markerRange = range(editor, node, valid: valid), let marker = string(editor, markerRange, valid: valid),
                  let frame = bounds(node), frame.width > 0, frame.height > 0,
                  frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite else { return false }
            var body = "", prefix = ""
            for (index, child) in children.enumerated() {
                if attribute(child, kAXRoleAttribute) as? String == "AXListMarker" {
                    guard index == 0, prefix.isEmpty, owned(child, by: node),
                          let label = attribute(child, kAXValueAttribute) as? String, !label.isEmpty,
                          label.utf16.count <= 32, !label.contains("\n"),
                          let descendants = attribute(child, kAXChildrenAttribute) as? [AXUIElement], descendants.isEmpty else { return false }
                    prefix = label
                } else {
                    guard let text = inline(child, parent: node, depth: 0) else { return false }
                    body += text
                }
            }
            var text = Text(body: body, marker: marker, prefix: prefix)
            guard (children.isEmpty && marker == "\n") || marker.utf16.elementsEqual(body.utf16)
                || marker.utf16.elementsEqual(text.value.utf16) else { return false }
            if children.isEmpty, marker == "\n" {
                text.markup = ""
            } else if body.utf16.count <= 16_384,
                      let attributed = parameter(editor, "AXAttributedStringForTextMarkerRange", markerRange, valid: valid) as? NSAttributedString,
                      attributed.string.utf16.elementsEqual(body.utf16) {
                var runs = 0
                attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { _, _, stop in
                    runs += 1
                    if runs > 128 || !valid() { stop.pointee = true }
                }
                if runs <= 128, valid() {
                    text.markup = SelectedTextFormatting.markdown(body, attributed: attributed, preserveStructure: true)
                }
            }
            guard valid() else { return false }
            if let previous = paragraphs.last {
                // Inline formatting groups cannot masquerade as paragraphs.
                guard follows(frame, previous.frame) else { return false }
            }
            paragraphs.append(Paragraph(element: node, range: markerRange, text: text, frame: frame))
            return paragraphs.count <= 256
        }
        guard children.allSatisfy({ block($0, parent: editor, depth: 0) }), valid(),
              let markerText = string(editor, whole, valid: valid),
              paragraphs.map({ $0.text.marker }).joined().utf16.elementsEqual(markerText.utf16) else { return nil }
        return Snapshot(value: value, range: whole, markerText: markerText, paragraphs: paragraphs)
    }

    static func same(_ first: Snapshot, _ second: Snapshot) -> Bool {
        first.value.utf16.elementsEqual(second.value.utf16) && first.markerText.utf16.elementsEqual(second.markerText.utf16)
            && SelectedTextMarkers.sameRange(first.range, second.range)
            && first.paragraphs.count == second.paragraphs.count
            && zip(first.paragraphs, second.paragraphs).allSatisfy {
                CFEqual($0.element, $1.element) && $0.text.body.utf16.elementsEqual($1.text.body.utf16)
                    && $0.text.prefix.utf16.elementsEqual($1.text.prefix.utf16)
                    && $0.text.marker.utf16.elementsEqual($1.text.marker.utf16) && $0.frame == $1.frame
                    && SelectedTextMarkers.sameRange($0.range, $1.range)
            }
    }

    static func stableMarkup(_ first: Snapshot, _ second: Snapshot) -> String? {
        guard let left = first.markup, let right = second.markup, left.utf16.elementsEqual(right.utf16) else { return nil }
        return left
    }

    static func before(_ editor: AXUIElement, selection: AXTextMarkerRange, rawValue: String, valid: () -> Bool) -> Before? {
        guard valid(), SelectedTextMarkers.sameRange(selectedRange(editor), selection),
              let first = snapshot(editor, valid: valid), first.value.utf16.elementsEqual(rawValue.utf16) else { return nil }
        func boundary(_ marker: AXTextMarker) -> Boundary? {
            guard let owner = axElement(parameter(editor, "AXUIElementForTextMarker", marker, valid: valid)),
                  attribute(owner, kAXRoleAttribute) as? String != "AXListMarker" else { return nil }
            let chain = ancestors(owner, limit: 24, shouldStop: { !valid() })
            guard let index = first.paragraphs.firstIndex(where: { paragraph in chain.contains { CFEqual($0, paragraph.element) } }) else { return nil }
            let paragraph = first.paragraphs[index]
            let prefix = AXTextMarkerRangeCreate(kCFAllocatorDefault, AXTextMarkerRangeCopyStartMarker(paragraph.range), marker)
            let suffix = AXTextMarkerRangeCreate(kCFAllocatorDefault, marker, AXTextMarkerRangeCopyEndMarker(paragraph.range))
            guard let left = string(editor, prefix, valid: valid), let right = string(editor, suffix, valid: valid) else { return nil }
            return Boundary(paragraph: index, prefix: left, suffix: right)
        }
        guard let start = boundary(AXTextMarkerRangeCopyStartMarker(selection)), let end = boundary(AXTextMarkerRangeCopyEndMarker(selection)),
              let result = insertionState(first.paragraphs.map(\.text), start: start, end: end), valid(),
              SelectedTextMarkers.sameRange(selectedRange(editor), selection),
              let second = snapshot(editor, valid: valid), same(first, second), valid() else { return nil }
        return Before(state: result, plainBeforeMarkup: stableMarkup(first, second)?.utf16.elementsEqual(first.text.utf16) == true)
    }

    static func text(_ editor: AXUIElement, valid: () -> Bool) -> Receipt? {
        guard let first = snapshot(editor, valid: valid), let second = snapshot(editor, valid: valid),
              same(first, second), valid() else { return nil }
        return Receipt(text: first.text, markup: stableMarkup(first, second))
    }
}

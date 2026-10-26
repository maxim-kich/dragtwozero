import AppKit

/// Some rich editors render pasted Unicode emoji as Noto image attachments and
/// omit them from AXValue. Read only this editor's owned, complete subtree. An
/// unknown attachment or ambiguous text boundary is not a positive receipt.
enum EditorReceiptText {
    enum Fragment: Equatable {
        case text(String)
        case emoji(String)
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.text(a), .text(b)), let (.emoji(a), .emoji(b)): return a.utf16.elementsEqual(b.utf16)
            default: return false
            }
        }
    }
    struct Snapshot {
        let value: String
        let fragments: [Fragment]
        let markerText: String
        let markerRange: AXTextMarkerRange
    }

    static func readStable(snapshot: () -> Snapshot?, valid: () -> Bool) -> String? {
        guard valid(), let first = snapshot(),
              let result = reconcile(value: first.value, fragments: first.fragments, markerText: first.markerText),
              valid(), let second = snapshot(),
              first.value.utf16.elementsEqual(second.value.utf16), first.fragments == second.fragments,
              first.markerText.utf16.elementsEqual(second.markerText.utf16),
              SelectedTextMarkers.sameRange(first.markerRange, second.markerRange), valid() else { return nil }
        return result
    }

    static func notoEmoji(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "fonts.gstatic.com",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 7, path[0].isEmpty, path[1] == "s", path[2] == "e", path[3] == "notoemoji",
              path[4].range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil,
              path[5].range(of: #"^[0-9a-f]+(_[0-9a-f]+)*$"#, options: .regularExpression) != nil,
              path[6].range(of: #"^[1-9][0-9]{0,3}\.png$"#, options: .regularExpression) != nil else { return nil }
        let components = path[5].split(separator: "_")
        let values = components.compactMap { UInt32($0, radix: 16) }
        guard !values.isEmpty, values.count <= 16, values.count == components.count else { return nil }
        let scalars = values.compactMap(Unicode.Scalar.init)
        guard scalars.count == values.count else { return nil }
        let text = String(String.UnicodeScalarView(scalars))
        guard text.count == 1, scalars.contains(where: { $0.properties.isEmoji && $0.value > 127 }) else { return nil }
        return text
    }

    /// Require two complete representations of the same owned subtree. In
    /// Chromium rich editors an inline image is U+FFFC in its marker string but
    /// two phantom line feeds in AXValue. Preserve every literal text fragment;
    /// never infer line ownership or replace object characters in arbitrary text.
    static func reconcile(value: String, fragments: [Fragment], markerText: String) -> String? {
        let marker = Array(markerText.utf16)
        var offset = 0, valueProjection = "", semantic = "", images = 0, previousImage = false
        for fragment in fragments {
            switch fragment {
            case .text(let text):
                let literal = Array(text.utf16)
                if literal.isEmpty { continue }
                guard !literal.contains(0xFFFC), !previousImage || ![10, 13].contains(literal.first ?? 0),
                      literal.count <= marker.count - offset,
                      marker[offset..<(offset + literal.count)].elementsEqual(literal) else { return nil }
                offset += literal.count; valueProjection += text; semantic += text; previousImage = false
            case .emoji(let text):
                guard !previousImage else { return nil }
                // This literal gap comes only from the complete owned marker
                // string, never from AXValue or the expected pasted payload.
                let gapStart = offset
                while offset < marker.count && marker[offset] == 10 { offset += 1 }
                let gap = offset - gapStart
                guard gap == 0 || gap == 2, offset < marker.count, marker[offset] == 0xFFFC else { return nil }
                if gap == 2 { valueProjection += "\n\n"; semantic += "\n\n" }
                var preceding = 0, index = offset
                while index > 0 && marker[index - 1] == 10 { preceding += 1; index -= 1 }
                guard preceding == 0 || preceding == 2, index == 0 || marker[index - 1] != 13 else { return nil }
                // Chromium coalesces the two image-placeholder line feeds with
                // exactly two real preceding marker line feeds. No other gap
                // shape is inferred, and the authorized payload is never read here.
                if preceding == 0 { valueProjection += "\n\n" }
                semantic += text; images += 1; offset += 1; previousImage = true
            }
        }
        guard images > 0, offset == marker.count, valueProjection.utf16.elementsEqual(value.utf16) else { return nil }
        return semantic
    }

    static func read(_ editor: AXUIElement, valid: () -> Bool) -> String? {
        func snapshot() -> Snapshot? {
            guard valid(), let value = attribute(editor, kAXValueAttribute) as? String,
                  value.utf16.count <= 1_000_000 else { return nil }
            var fragments: [Fragment] = [], remaining = 256, remainingText = value.utf16.count
            func walk(_ node: AXUIElement, parent: AXUIElement?, depth: Int) -> Bool {
                remaining -= 1
                guard valid(), remaining >= 0, depth < 20,
                      let role = attribute(node, kAXRoleAttribute) as? String else { return false }
                if let parent {
                    guard valid(), let owner = axElement(attribute(node, kAXParentAttribute)), CFEqual(owner, parent) else { return false }
                }
                switch role {
                case "AXStaticText", "AXInlineTextBox":
                    guard valid(), let text = attribute(node, kAXValueAttribute) as? String,
                          text.utf16.count <= remainingText else { return false }
                    remainingText -= text.utf16.count
                    fragments.append(.text(text)); return true
                case "AXImage":
                    guard valid() else { return false }
                    let raw = attribute(node, kAXURLAttribute)
                    let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
                    guard let url, let emoji = notoEmoji(url) else { return false }
                    fragments.append(.emoji(emoji)); return true
                default:
                    guard parent == nil || ["AXGroup", "AXGenericElement", "AXUnknown", "AXParagraph", "AXLink", "AXHeading", "AXListItem"].contains(role) else { return false }
                    guard valid(), let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] else { return false }
                    return children.allSatisfy { walk($0, parent: node, depth: depth + 1) }
                }
            }
            guard walk(editor, parent: nil, depth: 0), valid() else { return nil }
            var rawRange: CFTypeRef?, rawText: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(editor, "AXTextMarkerRangeForUIElement" as CFString, editor, &rawRange) == .success,
                  let rawRange, CFGetTypeID(rawRange) == AXTextMarkerRangeGetTypeID(), valid() else { return nil }
            guard AXUIElementCopyParameterizedAttributeValue(editor, "AXStringForTextMarkerRange" as CFString, rawRange, &rawText) == .success,
                  let markerText = rawText as? String, markerText.utf16.count <= 1_000_000, valid() else { return nil }
            return Snapshot(value: value, fragments: fragments, markerText: markerText, markerRange: rawRange as! AXTextMarkerRange)
        }
        return readStable(snapshot: snapshot, valid: valid)
    }
}

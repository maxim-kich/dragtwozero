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
    }

    static func readStable(snapshot: () -> Snapshot?, valid: () -> Bool) -> String? {
        guard valid(), let first = snapshot(),
              let result = reconcile(value: first.value, fragments: first.fragments),
              valid(), let second = snapshot(),
              first.value.utf16.elementsEqual(second.value.utf16), first.fragments == second.fragments,
              valid() else { return nil }
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

    /// All plain fragments must consume the complete AXValue in order. Only
    /// structural newlines may occur between fragments. Never choose which
    /// side of an omitted image a newline belongs to by looking at the payload.
    static func reconcile(value: String, fragments: [Fragment]) -> String? {
        guard fragments.contains(where: { if case .emoji = $0 { return true }; return false }) else { return nil }
        let units = Array(value.utf16)
        var offset = 0, result = "", previousImage = false
        for fragment in fragments {
            switch fragment {
            case .text(let text):
                let next = Array(text.utf16)
                guard !next.isEmpty else { continue }
                func matches() -> Bool {
                    offset <= units.count - next.count && units[offset..<(offset + next.count)].elementsEqual(next)
                }
                if !matches() {
                    let initial = offset
                    while offset < units.count && [10, 13].contains(units[offset]) { offset += 1 }
                    guard !previousImage, matches() else { return nil }
                    result += String(decoding: units[initial..<offset], as: UTF16.self)
                }
                result += text; offset += next.count; previousImage = false
            case .emoji(let text):
                guard offset == units.count || ![10, 13].contains(units[offset]) else { return nil }
                result += text; previousImage = true
            }
        }
        guard offset <= units.count, units[offset...].allSatisfy({ [10, 13].contains($0) }),
              !previousImage || offset == units.count else { return nil }
        result += String(decoding: units[offset...], as: UTF16.self)
        return result
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
                    guard let owner = axElement(attribute(node, kAXParentAttribute)), CFEqual(owner, parent) else { return false }
                }
                switch role {
                case "AXStaticText", "AXInlineTextBox":
                    guard let text = attribute(node, kAXValueAttribute) as? String,
                          text.utf16.count <= remainingText else { return false }
                    remainingText -= text.utf16.count
                    fragments.append(.text(text)); return true
                case "AXImage":
                    let raw = attribute(node, kAXURLAttribute)
                    let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:))
                    guard let url, let emoji = notoEmoji(url) else { return false }
                    fragments.append(.emoji(emoji)); return true
                default:
                    guard parent == nil || ["AXGroup", "AXGenericElement", "AXUnknown", "AXParagraph", "AXLink", "AXHeading", "AXListItem"].contains(role) else { return false }
                    guard let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] else { return false }
                    return children.allSatisfy { walk($0, parent: node, depth: depth + 1) }
                }
            }
            guard walk(editor, parent: nil, depth: 0), valid() else { return nil }
            return Snapshot(value: value, fragments: fragments)
        }
        return readStable(snapshot: snapshot, valid: valid)
    }
}

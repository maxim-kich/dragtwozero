import AppKit

indirect enum TextFragment {
    case text(String)
    case link(String, URL)
    case formattedLink(TextFragment, URL)
    case group([TextFragment])
    case emphasis(TextFragment, strong: Bool)

    var markdown: String {
        switch self {
        case .text(let text): return Self.escape(text)
        case .link(let title, let url):
            let destination = url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
            return "[\(Self.escape(title.isEmpty ? url.absoluteString : title))](\(destination))"
        case .formattedLink(let label, let url):
            let destination = url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
            return "[\(label.markdown)](\(destination))"
        case .group(let fragments):
            return fragments.map(\.markdown).joined()
        case .emphasis(let fragment, let strong):
            let marker = strong ? "**" : "*"
            return marker + fragment.markdown + marker
        }
    }
    var unlinked: TextFragment {
        switch self {
        case .text: return self
        case .link(let title, _): return .text(title)
        case .formattedLink(let label, _): return label.unlinked
        case .group(let fragments): return .group(fragments.map(\.unlinked))
        case .emphasis(let fragment, let strong): return .emphasis(fragment.unlinked, strong: strong)
        }
    }
    var plainText: String {
        switch self {
        case .text(let text): return text
        case .link(let title, _): return title
        case .formattedLink(let label, _): return label.plainText
        case .group(let fragments): return fragments.map(\.plainText).joined()
        case .emphasis(let fragment, _): return fragment.plainText
        }
    }
    static func escape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\", with: "\\\\")
        for char in ["[", "]", "*", "_", "`", "#", "<", ">"] { result = result.replacingOccurrences(of: char, with: "\\" + char) }
        return result
    }
}

struct TextNodeDetails {
    var role: String
    var subrole = ""
    var description = ""
    var value: String?
    var title: String?
    var url: URL?
    var frame: CGRect?
    var headingLevel: Int?
    var isParagraph: Bool {
        ["AXHeading", "AXParagraph", "AXListItem"].contains(role)
            || ["AXParagraph", "AXListItem"].contains(subrole)
            || ["paragraph", "heading", "list item"].contains(description.lowercased())
    }
    var isEditable: Bool {
        ["AXTextArea", "AXTextField", "AXSecureTextField"].contains(role) || subrole == "AXSecureTextField"
    }
}

/// The resolver is shared by live AX capture and structural regression fixtures.
struct TextBlockReader<Node> {
    struct Resolution {
        let candidate: CaptureCandidate
        let block: Node
    }

    let details: (Node) -> TextNodeDetails
    let parent: (Node) -> Node?
    let children: (Node) -> [Node]
    let equal: (Node, Node) -> Bool
    var preserveStructure = false

    func candidate(at hit: Node) -> CaptureCandidate? {
        resolution(at: hit)?.candidate
    }

    /// Carry the selected source node with its content. Equal rectangles do
    /// not establish identity between a semantic block and its text children.
    func resolution(at hit: Node) -> Resolution? {
        var chain = [hit]
        for _ in 0..<20 {
            guard let next = parent(chain.last!), !chain.contains(where: { equal($0, next) }) else { break }
            chain.append(next)
        }
        guard !chain.contains(where: { details($0).isEditable }) else { return nil }
        // Prefer the semantic block even when the hit is inside a link, span, or formatted run.
        if let block = chain.first(where: { details($0).isParagraph }) { return capture(block) }

        // Some browser trees replace paragraph roles with generic inline-only groups.
        // Keep ascending through these wrappers, but never cross a page, list, control or block boundary.
        var inferred: Node?
        for node in chain {
            let info = details(node)
            if ["AXWebArea", "AXScrollArea", "AXWindow", "AXList", "AXTable", "AXApplication"].contains(info.role) { break }
            if ["AXGroup", "AXGenericElement", "AXUnknown"].contains(info.role) {
                var budget = 256
                guard let runs = inlineRuns(node, depth: 0, budget: &budget),
                      !runs.isEmpty else { break }
                // Require surrounding prose; a standalone link remains a link capture.
                if runs.contains(where: { !$0.link && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                   runs.count > 1, continuous(runs) {
                    inferred = node
                    // Electron may expose a list item as a generic group.
                    // Its marker is a block boundary even without vertical gaps.
                    if children(node).prefix(256).contains(where: { details($0).role == "AXListMarker" }) { break }
                }
                else if inferred != nil { break }
            } else if !["AXStaticText", "AXInlineTextBox", "AXLink", "AXImage"].contains(info.role) { break }
        }
        if let inferred { return capture(inferred) }
        // A run inside a link must fall through to the standalone-link adapter.
        guard !chain.contains(where: { details($0).role == "AXLink" }) else { return nil }
        // Chromium can hit an inline text box rather than its static-text parent.
        // Prefer the complete static-text run, including when reached through wrappers.
        if let text = chain.first(where: { details($0).role == "AXStaticText" }) { return capture(text) }
        guard details(hit).role == "AXInlineTextBox" else { return nil }
        return capture(hit)
    }
    /// AX may hit a page/container in the leading between lines. Resolve by block bounds,
    /// visiting only the branches under the pointer, with a hard accessibility-work budget.
    func candidate(at hit: Node, containing point: CGPoint) -> CaptureCandidate? {
        resolution(at: hit, containing: point)?.candidate
    }

    func resolution(at hit: Node, containing point: CGPoint) -> Resolution? {
        if let result = resolution(at: hit), result.candidate.frame.contains(point) { return result }
        var budget = 160
        func search(_ node: Node, depth: Int) -> Resolution? {
            budget -= 1
            guard budget > 0, depth < 24 else { return nil }
            let info = details(node)
            guard !info.isEditable, info.frame?.contains(point) != false else { return nil }
            if let result = resolution(at: node), result.candidate.frame.contains(point) { return result }
            for child in children(node) {
                guard budget > 0 else { break }
                if let result = search(child, depth: depth + 1) { return result }
            }
            return nil
        }
        return search(hit, depth: 0)
    }

    private struct Run {
        let text: String
        let frame: CGRect?
        let link: Bool
    }
    private func inlineRuns(_ node: Node, depth: Int, budget: inout Int) -> [Run]? {
        budget -= 1
        guard budget > 0, depth < 24 else { return nil }
        let info = details(node)
        guard !info.isParagraph, !info.isEditable else { return nil }
        // Images and list markers contribute no inline prose. They must not
        // split supported runs within one otherwise continuous block.
        if ["AXImage", "AXListMarker"].contains(info.role) { return [] }
        if ["AXStaticText", "AXInlineTextBox"].contains(info.role) {
            return [Run(text: info.value ?? info.title ?? "", frame: info.frame, link: false)]
        }
        if info.role == "AXLink" { return [Run(text: info.value ?? info.title ?? "link", frame: info.frame, link: true)] }
        guard ["AXGroup", "AXGenericElement", "AXUnknown"].contains(info.role) else { return nil }
        let descendants = children(node)
        guard descendants.count < budget else { budget = 0; return nil }
        // A containing list/message must not flatten neighboring generic items.
        if depth > 0, descendants.contains(where: { details($0).role == "AXListMarker" }) { return nil }
        var result: [Run] = []
        for child in descendants {
            guard let runs = inlineRuns(child, depth: depth + 1, budget: &budget) else { return nil }
            result += runs
        }
        return result
    }
    private func continuous(_ runs: [Run]) -> Bool {
        // Reject blank paragraphs and vertical gaps, so fallback grouping cannot swallow a feed/page.
        guard !runs.contains(where: { $0.text.contains("\n\n") }) else { return false }
        let frames = runs.compactMap(\.frame).filter { $0.height > 0 }.sorted { $0.minY < $1.minY }
        guard let first = frames.first else { return false }
        let heights = frames.map(\.height).sorted()
        // Superscripts are shorter than the paragraph's line metrics; multiline runs are taller.
        let lineHeight = heights[heights.count / 2]
        var bottom = first.maxY
        for frame in frames.dropFirst() {
            if frame.minY - bottom > max(4, lineHeight * 0.75) { return false }
            bottom = max(bottom, frame.maxY)
        }
        return true
    }
    private func capture(_ block: Node) -> Resolution? {
        guard let frame = details(block).frame else { return nil }
        var budget = 512
        guard let fragment = read(block, depth: 0, budget: &budget), budget > 0 else { return nil }
        let plainMarkdown = fragment.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = details(block)
        let text = preserveStructure ? structuredMarkdown(plainMarkdown, role: info.role, subrole: info.subrole, headingLevel: info.headingLevel) : plainMarkdown
        guard !plainMarkdown.isEmpty, text.count <= 32_000 else { return nil }
        return Resolution(candidate: CaptureCandidate(payload: .init(title: String(text.prefix(100)), markdown: text), frame: frame), block: block)
    }
    private func read(_ node: Node, depth: Int, budget: inout Int) -> TextFragment? {
        budget -= 1
        guard budget > 0, depth < 24 else { budget = 0; return nil }
        let info = details(node)
        guard !info.isEditable else { return nil }
        let descendants = children(node)
        let inlineURL = preserveStructure && info.url != nil
            && ["AXStaticText", "AXInlineTextBox", "AXGroup", "AXGenericElement"].contains(info.role)
        if info.role == "AXLink" || inlineURL {
            let fragments = descendants.compactMap { read($0, depth: depth + 1, budget: &budget) }
            let label = TextFragment.group(fragments)
            let title = label.plainText.isEmpty ? (info.title ?? info.value ?? "") : label.plainText
            guard let url = info.url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") else { return .text(title) }
            if preserveStructure {
                let content: TextFragment = label.plainText.isEmpty ? .text(title.isEmpty ? url.absoluteString : title) : label
                return .formattedLink(content.unlinked, url)
            }
            return .link(title, url)
        }
        if ["AXStaticText", "AXInlineTextBox"].contains(info.role) {
            return (info.value ?? info.title).map(TextFragment.text)
        }
        guard !info.isEditable, !["AXButton", "AXImage"].contains(info.role) else { return nil }
        let fragments = descendants.compactMap { read($0, depth: depth + 1, budget: &budget) }
        let fragment: TextFragment
        if fragments.isEmpty {
            guard let text = info.value ?? info.title else { return nil }
            fragment = .text(text)
        } else { fragment = .group(fragments) }
        if preserveStructure {
            let semantics = [info.role, info.subrole]
            // Chromium and AppKit expose semantic <strong>/<em> containers as
            // AXGroup with the standard style-group subrole, not AXStrong.
            if semantics.contains(where: { ["AXStrong", "AXStrongStyleGroup"].contains($0) }) {
                return .emphasis(fragment, strong: true)
            }
            if semantics.contains(where: { ["AXEmphasis", "AXEmphasisStyleGroup"].contains($0) }) {
                return .emphasis(fragment, strong: false)
            }
        }
        return fragment
    }
}

struct AccessibleTextBlockAdapter: SourceAdapter {
    let id = "accessible-text-block"
    func candidate(at element: AXUIElement) -> CaptureCandidate? {
        resolve(element, point: nil)
    }
    func candidate(at element: AXUIElement, containing point: CGPoint) -> CaptureCandidate? {
        resolve(element, point: point)
    }
    func candidate(at element: AXUIElement, shouldStop: () -> Bool) -> CaptureCandidate? {
        resolve(element, point: nil, shouldStop: shouldStop)
    }
    func candidate(at element: AXUIElement, containing point: CGPoint, shouldStop: () -> Bool) -> CaptureCandidate? {
        resolve(element, point: point, shouldStop: shouldStop)
    }
    private func resolve(_ element: AXUIElement, point: CGPoint?, shouldStop: () -> Bool = { false }) -> CaptureCandidate? {
        withoutActuallyEscaping(shouldStop) { shouldStop in
            guard !shouldStop() else { return nil }
            func read(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
                shouldStop() ? nil : attribute(node, name)
            }
            let preserveStructure = CapturePreferences.preserveStructure
            var cache: [CFHashCode: [(AXUIElement, TextNodeDetails)]] = [:]
            let reader = TextBlockReader<AXUIElement>(details: { node in
                guard !shouldStop() else { return TextNodeDetails(role: "AXSecureTextField") }
                let key = CFHash(node)
                if let cached = cache[key]?.first(where: { CFEqual($0.0, node) }) { return cached.1 }
                let role = read(node, kAXRoleAttribute) as? String ?? ""
                let subrole = read(node, kAXSubroleAttribute) as? String ?? ""
                let eligibility = TextNodeDetails(role: role, subrole: subrole)
                // Do not request content attributes from excluded editable/secure nodes.
                guard !eligibility.isEditable else {
                    cache[key, default: []].append((node, eligibility))
                    return eligibility
                }
                let raw = read(node, kAXURLAttribute)
                let info = TextNodeDetails(
                    role: role,
                    subrole: subrole,
                    description: read(node, kAXRoleDescriptionAttribute) as? String ?? "",
                    value: read(node, kAXValueAttribute) as? String,
                    title: [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { read(node, $0) as? String }.first(where: { !$0.isEmpty }),
                    url: (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:)), frame: shouldStop() ? nil : bounds(node),
                    headingLevel: preserveStructure && role == "AXHeading" ? ((read(node, "AXHeadingLevel") as? NSNumber)?.intValue ?? (read(node, "AXLevel") as? NSNumber)?.intValue) : nil)
                cache[key, default: []].append((node, info))
                return info
            }, parent: { axElement(read($0, kAXParentAttribute)) },
               children: { read($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] }, equal: { CFEqual($0, $1) }, preserveStructure: preserveStructure)
            let result = point.map { reader.resolution(at: element, containing: $0) } ?? reader.resolution(at: element)
            guard !shouldStop(), let result else { return nil }
            let anchored = result.candidate.anchored(to: result.block, shouldStop: shouldStop)
            return shouldStop() ? nil : anchored
        }
    }
}

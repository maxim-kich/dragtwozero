import AppKit

enum SelectedTextFormatting {
    /// Attribute strings must describe exactly the selected UTF-16 text. Never
    /// serialize an app's accidentally returned enclosing paragraph.
    static func markdown(_ text: String, attributed: NSAttributedString?, preserveStructure: Bool,
                         linkURL: (Any) -> URL? = accessibilityLinkURL) -> String {
        guard let attributed, text.utf16.elementsEqual(attributed.string.utf16) else {
            return TextFragment.text(text).markdown
        }
        struct Run {
            var text: String
            let url: URL?
            let bold: Bool
            let italic: Bool
        }
        var runs: [Run] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let rawLink = attributes[.link] ?? attributes[NSAttributedString.Key(kAXLinkTextAttribute.takeUnretainedValue() as String)]
            let url = rawLink.flatMap(linkURL).flatMap { url in
                ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") ? url : nil
            }
            let axFont = attributes[NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)] as? [String: Any]
            let font = (attributes[.font] as? NSFont) ?? axFont.flatMap { dictionary in
                (dictionary[kAXFontNameKey.takeUnretainedValue() as String] as? String).flatMap {
                    let size = (dictionary[kAXFontSizeKey.takeUnretainedValue() as String] as? NSNumber)?.doubleValue ?? 12
                    // AX exposes private system-font face names. Asking NSFont
                    // to load these by name can silently return Times instead.
                    if $0.hasPrefix(".SF") || $0.hasPrefix(".AppleSystemUIFont") {
                        let face = $0.lowercased()
                        let system = NSFont.systemFont(ofSize: size, weight: face.contains("bold") ? .bold : .regular)
                        return face.contains("italic") || face.contains("oblique") ? NSFontManager.shared.convert(system, toHaveTrait: .italicFontMask) : system
                    }
                    return NSFont(name: $0, size: size)
                }
            }
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            // Chromium can expose a weight flag and size without a font name.
            let explicitBold = axFont?["AXFontBold"] as? Bool
            let bold = preserveStructure && (explicitBold ?? traits.contains(.bold))
            let italic = preserveStructure && traits.contains(.italic)
            let content = (text as NSString).substring(with: range)
            if let last = runs.last, last.url == url, last.bold == bold, last.italic == italic {
                runs[runs.count - 1].text += content
            } else { runs.append(Run(text: content, url: url, bold: bold, italic: italic)) }
        }
        return runs.map { run in
            var content: TextFragment = .text(run.text)
            if run.bold || run.italic {
                let core = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !core.isEmpty, let range = run.text.range(of: core) {
                    var styled: TextFragment = .text(core)
                    if run.italic { styled = .emphasis(styled, strong: false) }
                    if run.bold { styled = .emphasis(styled, strong: true) }
                    content = .group([.text(String(run.text[..<range.lowerBound])), styled, .text(String(run.text[range.upperBound...]))])
                }
            }
            if let url = run.url { content = .formattedLink(content, url) }
            return content.markdown
        }.joined()
    }

    private static func accessibilityLinkURL(_ raw: Any) -> URL? {
        if let url = raw as? URL { return url }
        if let string = raw as? String { return URL(string: string) }
        guard let element = axElement(raw as CFTypeRef) else { return nil }
        let value = attribute(element, kAXURLAttribute)
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }
}

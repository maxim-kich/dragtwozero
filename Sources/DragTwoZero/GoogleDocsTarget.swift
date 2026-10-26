import AppKit
import ApplicationServices

/// Docs draws the page separately from its accessible keyboard input.
/// This adapter connects the document viewport to that input without clicking
/// the page or interpreting the input's temporary buffer as document offsets.
enum GoogleDocsTarget {
    static func isDocumentURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "docs.google.com" else { return false }
        return url.path.hasPrefix("/document/d/") && url.path.contains("/edit")
    }

    static func viewport(_ frame: CGRect, excluding controls: [CGRect]) -> CGRect {
        var result = frame
        for control in controls {
            let rect = control.intersection(frame)
            guard !rect.isNull, !rect.isEmpty else { continue }
            // Horizontal editor chrome and tall side panels only. Floating
            // buttons must not arbitrarily cut the document viewport in half.
            if rect.width > frame.width * 0.5, rect.height < frame.height * 0.3,
               rect.minY < frame.minY + frame.height * 0.3 {
                let bottom = max(result.minY, rect.maxY)
                result = CGRect(x: result.minX, y: bottom, width: result.width, height: max(0, result.maxY - bottom))
            } else if rect.height > frame.height * 0.4, rect.width < frame.width * 0.4 {
                if rect.minX <= frame.minX + frame.width * 0.2 {
                    let left = max(result.minX, rect.maxX)
                    result = CGRect(x: left, y: result.minY, width: max(0, result.maxX - left), height: result.height)
                } else if rect.maxX >= frame.maxX - frame.width * 0.2 {
                    result.size.width = max(0, min(result.maxX, rect.minX) - result.minX)
                }
            }
        }
        return result
    }

    static func highlightFrame(caret: CGRect, pointer: CGPoint, viewport: CGRect) -> CGRect {
        let hasCaret = caret.height >= 8 && caret.height <= 160 && caret.width <= 4
            && caret.width >= 0 && viewport.contains(CGPoint(x: caret.midX, y: caret.midY))
        let anchor = hasCaret ? CGPoint(x: caret.midX, y: caret.midY) : pointer
        let height = hasCaret ? min(44, max(28, caret.height)) : 32
        return CGRect(x: anchor.x - 32, y: anchor.y - height / 2, width: 64, height: height)
            .intersection(viewport)
    }

    static func caretBounds(_ editor: AXUIElement) -> CGRect {
        guard var range = InputTarget.selectedInsertionRange(editor),
              let parameter = AXValueCreate(.cfRange, &range) else { return .zero }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(editor, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return .zero }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return .zero }
        return rect
    }

    static func find(hit: AXUIElement, at point: CGPoint, app: NSRunningApplication) -> InputTarget? {
        let chain = ancestors(hit, limit: 40)
        guard let document = chain.first(where: { node in
            guard attribute(node, kAXRoleAttribute) as? String == "AXWebArea" else { return false }
            let value = attribute(node, kAXURLAttribute)
            return isDocumentURL((value as? URL)?.absoluteString ?? value as? String ?? "")
        }), let documentFrame = bounds(document) else { return nil }
        // Toolbar fields, comments, links, and navigation retain their own targets.
        let controls: Set<String> = ["AXButton", "AXPopUpButton", "AXMenuBar", "AXToolbar", "AXLink", "AXOutline", "AXTabGroup", "AXTextField", "AXComboBox"]
        guard !chain.prefix(while: { !CFEqual($0, document) }).contains(where: {
            controls.contains(attribute($0, kAXRoleAttribute) as? String ?? "")
        }) else { return nil }
        var queue = [document], visited = 0
        var editor: AXUIElement?
        var chrome: [CGRect] = []
        while !queue.isEmpty && visited < 350 {
            let node = queue.removeFirst(); visited += 1
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            let label = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(node, $0) as? String }.joined(separator: " ")
            if role == "AXTextArea", label.localizedCaseInsensitiveContains("Document content"), InputTarget.isEditor(node) {
                editor = node
            }
            if role == "AXToolbar" || role == "AXMenuBar" || label == "Document tabs" || label == "Side panel",
               let frame = bounds(node) { chrome.append(frame) }
            queue += (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(max(0, 350 - visited - queue.count))
        }
        guard let editor else { return nil }
        let frame = viewport(documentFrame, excluding: chrome)
        guard !frame.isEmpty, frame.contains(point) else { return nil }
        return InputTarget(element: editor, app: app, frame: frame, dropPoint: point,
                           insertionRange: nil, caretFrame: caretBounds(editor), googleDocsDocument: document)
    }
}

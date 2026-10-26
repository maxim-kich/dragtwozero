import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func hitTest(_ point: CGPoint, diagnostic: (StaticString) -> Void = { _ in }) -> AXUIElement? {
    if case let .found(element) = hitTestLookup(point, diagnostic: diagnostic) { return element }
    return nil
}

private func hitTestLookup(_ point: CGPoint, diagnostic: (StaticString) -> Void = { _ in }) -> TargetLookupResult<AXUIElement> {
    guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { diagnostic("window-list-unavailable"); return .operationallyUnavailable }
    let windows = rawWindows.compactMap { window -> HitTestWindow? in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
              let layer = window[kCGWindowLayer as String] as? Int,
              let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return nil }
        return HitTestWindow(pid: pid, layer: layer, frame: frame,
                             alpha: window[kCGWindowAlpha as String] as? Double ?? 1,
                             windowID: (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value)
    }
    let nativeDragging = NativeDragHitTesting.isActive
    var resolution = WindowHitPolicy.resolve(windows, at: point, ownPID: getpid(), nativeDragActive: nativeDragging)
    if resolution == .blocked {
        let passive = PassiveScreenCaptureOverlay.authorizedWindows(in: windows, at: point,
            ownPID: getpid(), nativeDragActive: nativeDragging)
        if !passive.isEmpty {
            resolution = WindowHitPolicy.resolve(windows, at: point, ownPID: getpid(), nativeDragActive: nativeDragging,
                                                  passiveScreenCaptureWindows: passive)
        }
    }
    if resolution == .blocked {
        let passive = PassiveSystemOverlay.authorizedWindows(in: windows, at: point,
            ownPID: getpid(), nativeDragActive: nativeDragging, diagnostic: diagnostic)
        if !passive.isEmpty {
            resolution = WindowHitPolicy.resolve(windows, at: point, ownPID: getpid(), nativeDragActive: nativeDragging,
                passiveSystemWindows: passive)
        }
    }
    guard case let .application(pid) = resolution else {
        diagnostic(resolution == .blocked ? "window-hit-blocked" : "window-hit-empty"); return .rejected
    }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.08)
    if !Thread.isMainThread {
        AccessibilityTreePreparation.shared.prepare(pid: pid) {
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }
    var result: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &result)
    guard error == .success else {
        switch error {
        case .cannotComplete: diagnostic("ax-hit-cannot-complete")
        case .noValue: diagnostic("ax-hit-no-value")
        case .invalidUIElement: diagnostic("ax-hit-invalid-element")
        case .apiDisabled: diagnostic("ax-hit-api-disabled")
        default: diagnostic("ax-hit-error")
        }
        return AXTargetReadFailure.isOperational(error) ? .operationallyUnavailable : .rejected
    }
    guard let result else { diagnostic("ax-hit-empty"); return .operationallyUnavailable }
    return .found(result)
}

func ancestors(_ element: AXUIElement, limit: Int = 8, shouldStop: () -> Bool = { false }) -> [AXUIElement] {
    var result = [element]
    for _ in 0..<limit {
        guard !shouldStop(), let parent = axElement(attribute(result.last!, kAXParentAttribute)), !result.contains(where: { CFEqual($0, parent) }) else { break }
        result.append(parent)
    }
    return result
}
func bounds(_ element: AXUIElement) -> CGRect? {
    guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: point, size: size)
}
/// Identity is separate from geometry: an overlapping rectangle is not proof
/// that a source or destination still belongs to the same window/page.
struct CaptureElementContext: Equatable {
    let window: AXUIElement?
    let document: AXUIElement?
    let documentURL: String?

    init(window: AXUIElement?, document: AXUIElement?, documentURL: String?) {
        self.window = window; self.document = document; self.documentURL = documentURL
    }

    init(chain: [AXUIElement], shouldStop: () -> Bool = { false }) {
        window = chain.first { !shouldStop() && attribute($0, kAXRoleAttribute) as? String == "AXWindow" }
        document = chain.first { !shouldStop() && attribute($0, kAXRoleAttribute) as? String == "AXWebArea" }
        let raw = document.flatMap { shouldStop() ? nil : attribute($0, kAXURLAttribute) }
            ?? window.flatMap { shouldStop() ? nil : attribute($0, kAXDocumentAttribute) }
        documentURL = (raw as? URL)?.absoluteString ?? raw as? String
    }

    static func sameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return CFEqual(lhs, rhs)
        default: return false
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        sameElement(lhs.window, rhs.window) && sameElement(lhs.document, rhs.document)
            && lhs.documentURL == rhs.documentURL
    }
}

struct CaptureCandidate {
    let payload: CapturePayload
    let frame: CGRect
    var anchor: AXUIElement? = nil
    var anchorFrame: CGRect? = nil
    var viewport: AXUIElement? = nil
    var clipFrame: CGRect? = nil
    var context: CaptureElementContext? = nil
    var selectedTextRange: CFRange? = nil
    var selectedTextMarkerRange: AXTextMarkerRange? = nil
    var textFrames: [CGRect]? = nil
    var visibleHighlightFrames: [CGRect] {
        (textFrames ?? [frame]).compactMap { rect in
            let visible = clipFrame.map { rect.intersection($0) } ?? rect
            return visible.isNull || visible.isEmpty ? nil : visible
        }
    }
    func containsVisiblePoint(_ point: CGPoint) -> Bool {
        visibleHighlightFrames.contains { $0.contains(point) }
    }
    var scrollProtectionFrames: [CGRect] {
        selectedTextRange == nil ? visibleHighlightFrames : textSelectionScrollFrames(visibleHighlightFrames)
    }
    var visibleFrame: CGRect? {
        let visible = clipFrame.map { frame.intersection($0) } ?? frame
        return visible.isNull || visible.isEmpty ? nil : visible
    }
    func anchored(to element: AXUIElement, shouldStop: () -> Bool = { false }) -> CaptureCandidate {
        var copy = self
        let chain = ancestors(element, limit: 40, shouldStop: shouldStop)
        copy.context = CaptureElementContext(chain: chain, shouldStop: shouldStop)
        let matching = chain.first { !shouldStop() && bounds($0) == frame } ?? element
        copy.anchor = matching; copy.anchorFrame = shouldStop() ? nil : bounds(matching)
        copy.viewport = ancestors(matching, limit: 40, shouldStop: shouldStop).first {
            !shouldStop() && ["AXScrollArea", "AXWindow"].contains(attribute($0, kAXRoleAttribute) as? String ?? "")
        }
        copy.clipFrame = copy.viewport.flatMap { shouldStop() ? nil : bounds($0) }
        return copy
    }
    func repositioned(to newAnchor: CGRect, clippedTo viewportFrame: CGRect?) -> CaptureCandidate {
        let original = anchorFrame ?? frame
        let next = original == frame ? newAnchor : frame.offsetBy(dx: newAnchor.minX - original.minX, dy: newAnchor.minY - original.minY)
        var copy = CaptureCandidate(payload: payload, frame: next)
        copy.anchor = anchor; copy.anchorFrame = newAnchor; copy.viewport = viewport; copy.clipFrame = viewportFrame
        copy.context = context
        copy.selectedTextRange = selectedTextRange
        copy.selectedTextMarkerRange = selectedTextMarkerRange
        copy.textFrames = textFrames?.map { $0.offsetBy(dx: next.minX - frame.minX, dy: next.minY - frame.minY) }
        return copy
    }
    func matchesCurrentSource(_ current: CaptureCandidate, at point: CGPoint) -> Bool {
        matchesRetainedSource(current) && current.containsVisiblePoint(point)
    }
    /// Offscreen retained selections have no hit-test point. Require their
    /// original anchor, document context and exact payload to remain intact.
    func matchesRetainedSource(_ current: CaptureCandidate) -> Bool {
        guard let anchor, let currentAnchor = current.anchor,
              CFEqual(anchor, currentAnchor), context != nil, context == current.context else { return false }
        switch (selectedTextRange, current.selectedTextRange) {
        case (nil, nil): break
        case let (old?, fresh?) where old.location == fresh.location && old.length == fresh.length: break
        default: return false
        }
        guard SelectedTextMarkers.sameRange(selectedTextMarkerRange, current.selectedTextMarkerRange) else { return false }
        return payload.text.utf16.elementsEqual(current.payload.text.utf16) && payload.url == current.payload.url
    }
    func refreshedGeometry() -> CaptureCandidate {
        guard let anchor else { return self }
        if selectedTextRange != nil {
            if let current = AccessibleSelectedTextAdapter().candidate(at: anchor), matchesRetainedSource(current) { return current }
            var hidden = self; hidden.clipFrame = .zero; return hidden
        }
        guard let next = bounds(anchor) else {
            var hidden = self; hidden.clipFrame = .zero; return hidden
        }
        return repositioned(to: next, clippedTo: viewport.flatMap { bounds($0) })
    }
    var symbol: String { payload.url == nil ? "text.alignleft" : "link" }
}
protocol SourceAdapter {
    var id: String { get }
    func candidate(at element: AXUIElement) -> CaptureCandidate?
    func candidate(at element: AXUIElement, containing point: CGPoint) -> CaptureCandidate?
    func candidate(at element: AXUIElement, shouldStop: () -> Bool) -> CaptureCandidate?
    func candidate(at element: AXUIElement, containing point: CGPoint, shouldStop: () -> Bool) -> CaptureCandidate?
}
extension SourceAdapter {
    func candidate(at element: AXUIElement, shouldStop: () -> Bool) -> CaptureCandidate? {
        guard !shouldStop() else { return nil }
        let result = candidate(at: element)
        return shouldStop() ? nil : result
    }
    func candidate(at element: AXUIElement, containing point: CGPoint, shouldStop: () -> Bool) -> CaptureCandidate? {
        candidate(at: element, shouldStop: shouldStop).flatMap { $0.containsVisiblePoint(point) ? $0 : nil }
    }
    func candidate(at element: AXUIElement, containing point: CGPoint) -> CaptureCandidate? {
        candidate(at: element).flatMap { $0.frame.contains(point) ? $0 : nil }
    }
}

func sourceCandidate(at element: AXUIElement, containing point: CGPoint? = nil, adapters: [SourceAdapter],
                     shouldStop: () -> Bool = { false }) -> CaptureCandidate? {
    for adapter in adapters {
        guard !shouldStop() else { return nil }
        let candidate: CaptureCandidate?
        if let point { candidate = adapter.candidate(at: element, containing: point, shouldStop: shouldStop) }
        else { candidate = adapter.candidate(at: element, shouldStop: shouldStop) }
        if let candidate { return shouldStop() ? nil : candidate }
    }
    return nil
}
struct AccessibleLinkAdapter: SourceAdapter {
    let id = "accessible-link"
    func candidate(at element: AXUIElement) -> CaptureCandidate? {
        candidate(at: element, shouldStop: { false })
    }
    func candidate(at element: AXUIElement, shouldStop: () -> Bool) -> CaptureCandidate? {
        guard !shouldStop() else { return nil }
        let chain = ancestors(element, limit: 24, shouldStop: shouldStop)
        guard !chain.contains(where: {
            if shouldStop() { return true }
            return TextNodeDetails(role: attribute($0, kAXRoleAttribute) as? String ?? "",
                            subrole: attribute($0, kAXSubroleAttribute) as? String ?? "").isEditable
        }) else { return nil }
        for node in chain {
            guard !shouldStop() else { return nil }
            guard attribute(node, kAXRoleAttribute) as? String == "AXLink",
                  let raw = attribute(node, kAXURLAttribute),
                  let url = (raw as? URL) ?? (raw as? String).flatMap(URL.init(string:)),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let frame = bounds(node) else { continue }
            let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                .compactMap { attribute(node, $0) as? String }.first(where: { !$0.isEmpty }) ?? ""
            var pid: pid_t = 0; AXUIElementGetPid(node, &pid)
            let result = CaptureCandidate(payload: .init(title: title, url: url), frame: frame).anchored(to: node, shouldStop: shouldStop)
            return shouldStop() ? nil : result
        }
        return nil
    }
}
enum AXTargetReadFailure {
    static func isOperational(_ error: AXError) -> Bool { error == .cannotComplete || error == .noValue }
}

private struct TargetAttributeReads {
    var unavailable = false
    var rejected = false
    mutating func read(_ element: AXUIElement, _ name: String, diagnostic: (StaticString) -> Void) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        guard error == .success else {
            if AXTargetReadFailure.isOperational(error) {
                unavailable = true
                diagnostic(error == .cannotComplete ? "ax-target-read-cannot-complete" : "ax-target-read-no-value")
            } else { rejected = true; diagnostic("ax-target-read-terminal") }
            return nil
        }
        if result == nil { unavailable = true; diagnostic("ax-target-read-empty") }
        return result
    }
    func failure<Value>() -> TargetLookupResult<Value> {
        rejected || !unavailable ? .rejected : .operationallyUnavailable
    }
}

struct InputTarget {
    static func acceptsEditor(role: String, subrole: String?, enabled: Bool,
                              editable: Bool?, valueWritable: Bool, selectionWritable: Bool, hasCaret: Bool = false) -> Bool {
        guard enabled, editable != false,
              role != "AXSecureTextField", subrole != "AXSecureTextField" else { return false }
        let textRole = ["AXTextArea", "AXTextField", "AXComboBox"].contains(role)
        let documentRole = ["AXGroup", "AXWebArea", "AXLayoutArea", "AXLayoutItem"].contains(role)
        return (textRole && (valueWritable || editable == true || (hasCaret && selectionWritable)))
            || (documentRole && selectionWritable && editable == true)
    }

    static func isEditor(_ element: AXUIElement) -> Bool {
        var valueWritable = DarwinBoolean(false), selectionWritable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueWritable)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &selectionWritable)
        return acceptsEditor(role: attribute(element, kAXRoleAttribute) as? String ?? "",
                             subrole: attribute(element, kAXSubroleAttribute) as? String,
                             enabled: attribute(element, kAXEnabledAttribute) as? Bool != false,
                             editable: attribute(element, "AXEditable") as? Bool,
                             valueWritable: valueWritable.boolValue,
                             selectionWritable: selectionWritable.boolValue,
                             hasCaret: selectedInsertionRange(element) != nil)
    }

    let element: AXUIElement
    let app: NSRunningApplication
    let frame: CGRect
    let dropPoint: CGPoint
    var insertionRange: CFRange?
    let caretFrame: CGRect
    var cellValueElement: AXUIElement? = nil
    var googleDocsDocument: AXUIElement? = nil
    var context: CaptureElementContext? = nil
    var selectionValue: String? = nil
    func preservingSelection(from authorized: InputTarget) -> InputTarget {
        var copy = self
        copy.insertionRange = authorized.insertionRange
        copy.selectionValue = authorized.selectionValue
        return copy
    }
    func matchesCurrentTarget(_ current: InputTarget, at point: CGPoint) -> Bool {
        app.processIdentifier == current.app.processIdentifier && CFEqual(element, current.element)
            && context == current.context && current.frame.contains(point)
            && CaptureElementContext.sameElement(cellValueElement, current.cellValueElement)
            && CaptureElementContext.sameElement(googleDocsDocument, current.googleDocsDocument)
    }
    func matchesAuthorizedTarget(_ current: InputTarget, at point: CGPoint) -> Bool {
        guard context != nil, matchesCurrentTarget(current, at: point) else { return false }
        if cellValueElement != nil { return true }
        guard let original = insertionRange, let fresh = current.insertionRange,
              original.location == fresh.location, original.length == fresh.length,
              let originalValue = selectionValue, let freshValue = current.selectionValue else { return false }
        return originalValue.utf16.elementsEqual(freshValue.utf16)
    }
    func highlightFrame(at pointer: CGPoint) -> CGRect {
        googleDocsDocument == nil ? frame : GoogleDocsTarget.highlightFrame(caret: caretFrame, pointer: pointer, viewport: frame)
    }

    static func acceptsCell(role: String, enabled: Bool, editable: Bool?, valueWritable: Bool) -> Bool {
        role == "AXCell" && enabled && editable != false && valueWritable
    }

    static func writableCellValue(_ cell: AXUIElement) -> AXUIElement? {
        guard attribute(cell, kAXRoleAttribute) as? String == "AXCell",
              attribute(cell, kAXEnabledAttribute) as? Bool != false,
              attribute(cell, "AXEditable") as? Bool != false else { return nil }
        var nodes = [cell]
        var visited = 0
        while !nodes.isEmpty && visited < 32 {
            let node = nodes.removeFirst(); visited += 1
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            guard attribute(node, kAXEnabledAttribute) as? Bool != false,
                  attribute(node, "AXEditable") as? Bool != false,
                  attribute(node, kAXSubroleAttribute) as? String != "AXSecureTextField" else { continue }
            var writable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &writable)
            if Self.acceptsCell(role: role, enabled: true, editable: nil, valueWritable: writable.boolValue)
                || (["AXTextField", "AXTextArea", "AXComboBox"].contains(role) && writable.boolValue) {
                return node
            }
            nodes += (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(32 - visited)
        }
        return nil
    }
    func containsFocusedEditor(_ focused: AXUIElement) -> Bool {
        // Rich document editors can hand focus to an internal text editor.
        // Accept only editable descendants of this exact destination, never
        // another control elsewhere in the same window or application.
        CFEqual(focused, element) || (Self.isEditor(focused)
            && ancestors(focused, limit: 24).contains { CFEqual($0, element) })
    }
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }
    static func selectedInsertionRange(_ element: AXUIElement) -> CFRange? {
        selectedRange(element).map { CFRange(location: $0.location, length: 0) }
    }
    static func validatedSelectionRange(_ range: CFRange, value: String) -> CFRange? {
        let count = value.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= count,
              range.length <= count - range.location else { return nil }
        return range
    }
    private static func lookupBounds(_ element: AXUIElement, diagnostic: (StaticString) -> Void) -> TargetLookupResult<CGRect> {
        var reads = TargetAttributeReads()
        guard let p = reads.read(element, kAXPositionAttribute, diagnostic: diagnostic) else { return reads.failure() }
        guard CFGetTypeID(p) == AXValueGetTypeID() else { return .rejected }
        guard let s = reads.read(element, kAXSizeAttribute, diagnostic: diagnostic) else { return reads.failure() }
        guard CFGetTypeID(s) == AXValueGetTypeID() else { return .rejected }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return .rejected }
        return .found(CGRect(origin: point, size: size))
    }
    private static func lookupSelection(_ element: AXUIElement, diagnostic: (StaticString) -> Void) -> TargetLookupResult<(CFRange, String)> {
        var reads = TargetAttributeReads()
        func range() -> CFRange? {
            guard let raw = reads.read(element, kAXSelectedTextRangeAttribute, diagnostic: diagnostic) else { return nil }
            guard CFGetTypeID(raw) == AXValueGetTypeID() else { reads.rejected = true; return nil }
            var value = CFRange()
            guard AXValueGetValue(raw as! AXValue, .cfRange, &value), value.location >= 0, value.length >= 0 else { reads.rejected = true; return nil }
            return value
        }
        guard let first = range() else { return reads.failure() }
        guard let raw = reads.read(element, kAXValueAttribute, diagnostic: diagnostic) else { return reads.failure() }
        guard let value = raw as? String else { return .rejected }
        guard let second = range() else { return reads.failure() }
        guard first.location == second.location, first.length == second.length,
              let valid = validatedSelectionRange(second, value: value) else {
            diagnostic("editor-selection-unstable-or-invalid"); return .rejected
        }
        return .found((valid, value))
    }
    static func find(at point: CGPoint, diagnostic: (StaticString) -> Void = { _ in }) -> InputTarget? {
        if case let .found(target) = lookup(at: point, diagnostic: diagnostic) { return target }
        return nil
    }
    static func lookup(at point: CGPoint, diagnostic: (StaticString) -> Void = { _ in }) -> TargetLookupResult<InputTarget> {
        let hit: AXUIElement
        switch hitTestLookup(point, diagnostic: diagnostic) {
        case .found(let element): hit = element
        case .operationallyUnavailable: return .operationallyUnavailable
        case .rejected: return .rejected
        }
        var pid: pid_t = 0; AXUIElementGetPid(hit, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid) else { diagnostic("target-app-unavailable"); return .rejected }
        let chain = ancestors(hit)
        guard !chain.contains(where: {
            attribute($0, kAXSubroleAttribute) as? String == "AXSecureTextField"
                || attribute($0, kAXRoleAttribute) as? String == "AXSecureTextField"
        }) else { diagnostic("target-secure"); return .rejected }
        guard !chain.contains(where: { node in
            guard attribute(node, kAXRoleAttribute) as? String == "AXWebArea" else { return false }
            let value = attribute(node, kAXURLAttribute)
            return GoogleDocsTarget.isDocumentURL((value as? URL)?.absoluteString ?? value as? String ?? "")
        }) else { diagnostic("target-unsupported-document"); return .rejected }
        if let cell = chain.first(where: { attribute($0, kAXRoleAttribute) as? String == "AXCell" }) {
            guard let frame = bounds(cell), frame.contains(point), let value = writableCellValue(cell) else { diagnostic("target-cell-rejected"); return .rejected }
            return .found(InputTarget(element: cell, app: app, frame: frame, dropPoint: point,
                               insertionRange: nil, caretFrame: .zero, cellValueElement: value,
                               context: CaptureElementContext(chain: ancestors(cell, limit: 40))))
        }
        var operationalFailure = false
        var terminalFailure = false
        for node in chain {
            // Existing eligibility reads can swallow errors. Do not reinterpret
            // an ineligible node as operationally unavailable without evidence.
            guard isEditor(node) else { continue }
            let frame: CGRect
            switch lookupBounds(node, diagnostic: diagnostic) {
            case .found(let box): frame = box
            case .operationallyUnavailable: operationalFailure = true; continue
            case .rejected: terminalFailure = true; diagnostic("editor-bounds-rejected"); continue
            }
            guard frame.contains(point) else { terminalFailure = true; diagnostic("editor-outside-drop-point"); continue }
            switch lookupSelection(node, diagnostic: diagnostic) {
            case .found(let snapshot):
                return .found(InputTarget(element: node, app: app, frame: frame, dropPoint: point,
                    insertionRange: snapshot.0, caretFrame: .zero,
                    context: CaptureElementContext(chain: ancestors(node, limit: 40)), selectionValue: snapshot.1))
            case .operationallyUnavailable: operationalFailure = true
            case .rejected: terminalFailure = true; diagnostic("editor-selection-rejected")
            }
        }
        let recoverable = operationalFailure && !terminalFailure
        diagnostic(recoverable ? "editor-read-operationally-unavailable" : "no-eligible-editor")
        return recoverable ? .operationallyUnavailable : .rejected
    }
}

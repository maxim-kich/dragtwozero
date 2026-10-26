import AppKit

/// Only the source's known native drag image is transparent to AX hit testing.
/// This flag is read by the AX worker, never used to exempt another app's window.
enum NativeDragHitTesting {
    private static let lock = NSLock()
    private static var active = false
    static var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    static func setActive(_ value: Bool) { lock.lock(); active = value; lock.unlock() }
}

struct NativeDropPlan {
    let target: InputTarget
    let expectedEdits: [EditorInsertionState]
    func confirms(_ payload: String, observed: String) -> Bool {
        expectedEdits.contains { $0.confirmsInsertion(of: payload, observed: observed) }
    }
    /// Native receivers choose the caret at the physical drop point. Authorize
    /// only the hit character's boundaries (and an explicitly selected range).
    static func resolve(_ target: InputTarget, at point: CGPoint) -> NativeDropPlan? {
        guard target.cellValueElement == nil, target.googleDocsDocument == nil,
              let value = target.selectionValue, let selected = target.insertionRange else { return nil }
        if value.isEmpty, selected.location == 0, selected.length == 0 {
            return NativeDropPlan(target: target, expectedEdits: [.init(location: 0, length: 0, value: value)])
        }
        var point = point
        guard let input = AXValueCreate(.cgPoint, &point) else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(target.element, kAXRangeForPositionParameterizedAttribute as CFString, input, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var hit = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &hit), hit.location >= 0,
              hit.length >= 0, hit.location <= value.utf16.count,
              hit.length <= value.utf16.count - hit.location else { return nil }
        var edits = [EditorInsertionState(location: hit.location, length: 0, value: value)]
        if hit.length > 0 { edits.append(.init(location: hit.location + hit.length, length: 0, value: value)) }
        if selected.length > 0 { edits.append(.init(location: selected.location, length: selected.length, value: value)) }
        return NativeDropPlan(target: target, expectedEdits: edits.filter(\.hasValidRange))
    }
}

/// AppKit owns the drag and its private pasteboard. The event tap stages only
/// the physical release, so a fresh off-main authorization can reject a stale
/// editor without sending Paste, changing focus or editing an AX value.
final class NativeBufferDrag: NSObject, NSDraggingSource {
    struct Transfer {
        let id = UUID()
        let item: BufferItem
        let frame: CGRect
        let clipboardRevision: Int
    }
    private(set) var transfer: Transfer?
    private(set) var releasePending = false
    private(set) var plan: NativeDropPlan?
    private var session: NSDraggingSession?
    private var sequence: Int?
    private var release: CGEvent?
    private var cancelled = false
    var onBegin: ((Transfer, CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: ((Transfer, CGPoint, NSDragOperation, NativeDropPlan?) -> Void)?
    var isActive: Bool { transfer != nil }
    func movedSinceStagedRelease(to point: CGPoint) -> Bool {
        guard let release else { return false }
        return hypot(point.x - release.location.x, point.y - release.location.y) > 1
    }

    func begin(item: BufferItem, frame: CGRect, view: NSView, event: NSEvent) {
        guard transfer == nil, view.window != nil else { return }
        transfer = Transfer(item: item, frame: frame, clipboardRevision: NSPasteboard.general.changeCount)
        plan = nil; release = nil; releasePending = false; cancelled = false; sequence = nil
        NativeDragHitTesting.setActive(true)
        let drag = NSDraggingItem(pasteboardWriter: item.payload.text as NSString)
        // The existing Liquid Glass overlay supplies the single animated hint.
        let clear = NSImage(size: view.bounds.size, flipped: false) { _ in true }
        drag.setDraggingFrame(view.bounds, contents: clear)
        session = view.beginDraggingSession(with: [drag], event: event, source: self)
        session?.animatesToStartingPositionsOnCancelOrFail = false
    }
    func stageRelease(_ event: CGEvent) -> UUID? {
        guard let transfer, !releasePending, !cancelled else { return nil }
        releasePending = true; release = event.copy()
        return transfer.id
    }
    func completeRelease(id: UUID, plan: NativeDropPlan?) {
        guard transfer?.id == id, releasePending, let release else { return }
        self.plan = plan
        if plan == nil { cancelled = true; postEscape() }
        self.release = nil
        release.setIntegerValueField(.eventSourceUserData, value: 0xD203)
        release.post(tap: .cghidEventTap)
    }
    func cancel() {
        guard transfer != nil, !cancelled else { return }
        cancelled = true; plan = nil
        postEscape()
        if let release {
            self.release = nil
            release.setIntegerValueField(.eventSourceUserData, value: 0xD203)
            release.post(tap: .cghidEventTap)
        }
    }
    private func postEscape() {
        // Only while this exact source owns AppKit's drag tracking loop. AppKit
        // has no public NSDraggingSession.cancel API. Its normal Escape path
        // cancels before the staged mouse-up can reach a destination.
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { continue }
            event.flags = []; event.setIntegerValueField(.eventSourceUserData, value: 0xD203)
            event.post(tap: .cghidEventTap)
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication && !cancelled ? .copy : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        sequence = session.draggingSequenceNumber
        // The session location is not initialized until the first movedTo
        // callback. Seed the morph with AppKit's actual start point instead.
        if !cancelled, let transfer { onBegin?(transfer, quartz(screenPoint)) }
    }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        if sequence == session.draggingSequenceNumber && !releasePending && !cancelled { onMove?(quartz(session.draggingLocation)) }
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let sequence, sequence != session.draggingSequenceNumber { return }
        if sequence == nil, let active = self.session, active !== session { return }
        guard let transfer else { return }
        let plan = cancelled ? nil : self.plan
        self.transfer = nil; self.session = nil; sequence = nil; release = nil; releasePending = false; self.plan = nil
        NativeDragHitTesting.setActive(false)
        onEnd?(transfer, quartz(session.draggingLocation), cancelled ? [] : operation, plan)
    }
    private func quartz(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
}

/// Read-only confirmation for the explicit clipboard preference. Native receiver
/// acceptance settles the Buffer item independently of these optional AX reads.
final class NativeDropVerifier {
    private let queue = DispatchQueue(label: "capture.native-drop-verification", qos: .userInitiated)
    func verify(_ payload: CapturePayload, plan: NativeDropPlan, clipboardRevision: Int,
                overwriteClipboard: Bool, token: CaptureCommitToken, completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        func poll() {
            queue.asyncAfter(deadline: .now() + 0.1) {
                let valid = token.isValid && ProcessInfo.processInfo.systemUptime < deadline
                    && plan.target.context == CaptureElementContext(chain: ancestors(plan.target.element, limit: 40))
                let confirmed = valid && (attribute(plan.target.element, kAXValueAttribute) as? String).map {
                    plan.confirms(payload.text, observed: $0)
                } == true
                if valid && !confirmed { poll(); return }
                if confirmed && overwriteClipboard && NSPasteboard.general.changeCount == clipboardRevision {
                    let prepared = CaptureClipboard.prepare()
                    let copy = CaptureClipboard(prepared: prepared, restoreAfterPaste: false)
                    if NSPasteboard.general.changeCount == clipboardRevision {
                        if !copy.install(text: payload.text, isCurrent: { token.isValid && ProcessInfo.processInfo.systemUptime < deadline }) {
                            copy.abortBeforePaste()
                        }
                    }
                }
                DispatchQueue.main.async { completion(confirmed) }
            }
        }
        poll()
    }
}

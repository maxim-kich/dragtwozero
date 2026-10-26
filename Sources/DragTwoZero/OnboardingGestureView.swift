import AppKit

/// A contained practice area. It never captures other apps or changes the clipboard.
final class OnboardingGestureView: NSView {
    let interactive: Bool
    let sample = "Good ideas deserve a little context."
    private let destination = NSTextField()
    private let caption = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var monitor: Any?
    private var began = Date.timeIntervalSinceReferenceDate
    private var highlighted = false
    private var dragging = false
    private var cursor = NSPoint.zero
    private var completed = false
    private var shortcutKeyPressed = false
    private var tracking: NSTrackingArea?
    private var source: NSRect { NSRect(x: 28, y: bounds.height - 128, width: bounds.width - 56, height: 68) }

    init(frame: NSRect, interactive: Bool) {
        self.interactive = interactive
        super.init(frame: frame)
        wantsLayer = true
        destination.frame = NSRect(x: 28, y: 58, width: frame.width - 56, height: 62)
        destination.placeholderString = "Drop the paragraph here"
        destination.font = .systemFont(ofSize: 16)
        destination.isEditable = interactive
        destination.isSelectable = interactive
        destination.setAccessibilityLabel("Practice destination")
        addSubview(destination)
        caption.frame = NSRect(x: 28, y: 15, width: frame.width - 56, height: 25)
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.alignment = .center
        addSubview(caption)
        setAccessibilityLabel(interactive ? "Drag practice area" : "Animated drag demonstration")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    private func shortcutHeld(_ event: NSEvent) -> Bool {
        let shortcut = CaptureShortcut.current
        return shortcut.matches(flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)), keyPressed: shortcut.keyCode == nil || shortcutKeyPressed)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        began = Date.timeIntervalSinceReferenceDate
        if interactive {
            window?.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true, event.window === self.window else { return event }
                if event.type == .keyDown && event.keyCode == 53 {
                    self.dragging = false; self.highlighted = false; self.needsDisplay = true
                    return nil
                }
                if CaptureShortcut.current.keyCode == event.keyCode && (event.type == .keyDown || event.type == .keyUp) {
                    self.shortcutKeyPressed = event.type == .keyDown
                }
                let point = self.convert(self.window!.mouseLocationOutsideOfEventStream, from: nil)
                if event.type == .leftMouseDown && self.source.contains(self.convert(event.locationInWindow, from: nil)) && self.shortcutHeld(event) {
                    self.mouseDown(with: event); return nil
                }
                if self.dragging && event.type == .leftMouseDragged { self.mouseDragged(with: event); return nil }
                if self.dragging && event.type == .leftMouseUp { self.mouseUp(with: event); return nil }
                self.highlighted = self.shortcutHeld(event) && self.source.contains(point)
                self.needsDisplay = true
                return event
            }
        } else if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    private func stop() {
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
    }
    deinit { stop() }
    override func mouseDown(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        guard interactive, source.contains(cursor), shortcutHeld(event) else { return }
        dragging = true; completed = false; highlighted = true; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        cursor = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        cursor = convert(event.locationInWindow, from: nil)
        if destination.frame.contains(cursor) {
            destination.selectText(nil)
            window?.makeFirstResponder(destination)
            if let editor = destination.currentEditor() as? NSTextView {
                editor.insertText(sample, replacementRange: editor.selectedRange())
                completed = true
            }
        }
        dragging = false; highlighted = false; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 18, yRadius: 18)
        outline.fill(); NSColor.separatorColor.setStroke(); outline.stroke()
        NSGraphicsContext.saveGraphicsState(); outline.addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let time = (Date.timeIntervalSinceReferenceDate - began).truncatingRemainder(dividingBy: 6)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let demoDrag = !interactive && !reduced && time > 1.5 && time < 4.5
        let selected = highlighted || (!interactive && (reduced || time > 0.6 && time < 4.5))
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: source, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: source, xRadius: 12, yRadius: 12).stroke()
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            let selection = NSBezierPath(roundedRect: source, xRadius: 12, yRadius: 12)
            selection.fill(); NSColor.controlAccentColor.setStroke(); selection.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor]
        (sample as NSString).draw(at: NSPoint(x: source.minX + 18, y: source.midY - 10), withAttributes: attributes)
        let label = interactive ? "Practice with your shortcut" : "Hold \(CaptureShortcut.current.title) → select → drag → drop"
        (label as NSString).draw(at: NSPoint(x: 28, y: bounds.height - 35), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
        if !interactive { destination.stringValue = !reduced && time > 4.5 ? sample : "" }
        var point = cursor
        if demoDrag {
            let t = min(1, max(0, (time - 1.5) / 2.5))
            let eased = t * t * (3 - 2 * t)
            point = NSPoint(x: source.midX + 50, y: source.midY + (destination.frame.midY - source.midY) * eased)
        }
        if dragging || demoDrag {
            let chip = NSRect(x: min(bounds.width - 125, max(8, point.x)), y: max(8, point.y + 16), width: 112, height: 34)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: chip, xRadius: 12, yRadius: 12).fill()
            DragCursorIcon.image.draw(in: NSRect(x: chip.minX + 10, y: chip.minY + 7, width: 20, height: 20))
            ((destination.frame.contains(point) ? "Drop" : "Drag") as NSString).draw(at: NSPoint(x: chip.minX + 40, y: chip.minY + 8), withAttributes: attributes)
        }
        caption.stringValue = interactive
            ? (completed ? "Done! You added the paragraph. Try again or finish setup." : dragging ? "Release over the field to drop. Escape cancels." : "Hold \(CaptureShortcut.current.title), then click and drag the paragraph.")
            : "Release the keys while dragging. Release the mouse button to drop."
    }
}

import AppKit

/// Shared gesture styling for the Experimental help popovers.
final class MultiselectDemoView: NSView {
    enum Mode { case multiSelect, selectedText }
    private let mode: Mode
    init(frame: NSRect, mode: Mode = .multiSelect) {
        self.mode = mode
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(mode == .multiSelect ? "Multi-select demonstration" : "Select text and hold the shortcut to show a hint under the pointer. Grab and drag the hint; the shortcut can then be released. Escape cancels.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static let lightCursor: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        DragCursorIcon.image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24))
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill(using: .sourceIn)
        image.unlockFocus()
        return image
    }()
    private var timer: Timer?
    private var started = Date.timeIntervalSinceReferenceDate
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        started = Date.timeIntervalSinceReferenceDate
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.window?.isVisible == true { self.needsDisplay = true }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        needsDisplay = true
    }

    deinit { timer?.invalidate() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let time = reduced ? 2.2 : (Date.timeIntervalSinceReferenceDate - started).truncatingRemainder(dividingBy: mode == .selectedText ? 6.8 : 5.2)
        func smooth(_ value: Double) -> CGFloat {
            let t = min(1, max(0, value))
            return CGFloat(t * t * (3 - 2 * t))
        }
        func rounded(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 7) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        let box = bounds.insetBy(dx: 1, dy: 1)
        rounded(box, .windowBackgroundColor, radius: 12)
        let border = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        NSColor.separatorColor.setStroke()
        border.lineWidth = 1
        border.stroke()
        NSGraphicsContext.saveGraphicsState()
        border.addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if mode == .selectedText {
            drawSelectedText(time: time)
            return
        }
        let sweep = smooth((time - 0.5) / 1.7)
        let drag = smooth((time - 2.8) / 1.1)
        let fade = 1 - smooth((time - 4.5) / 0.5)
        let offset = NSPoint(x: drag * 30, y: drag * 8)
        let selection = NSRect(x: 26, y: 32, width: 18 + sweep * 198, height: 8 + sweep * 108)
        let dragging = time >= 2.8
        for index in 0..<3 {
            let original = NSRect(x: 44, y: 42 + CGFloat(index) * 34, width: 174, height: 26)
            let selected = selection.intersects(original)
            let rect = selected && dragging ? original.offsetBy(dx: offset.x, dy: offset.y) : original
            rounded(original, .separatorColor.withAlphaComponent(0.12))
            rounded(rect, .controlBackgroundColor.withAlphaComponent(0.9))
            if selected {
                rounded(rect.insetBy(dx: -3, dy: -3), .controlAccentColor.withAlphaComponent(0.15 * fade))
                let outline = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 9, yRadius: 9)
                NSColor.controlAccentColor.withAlphaComponent(0.55 * fade).setStroke()
                outline.lineWidth = 1
                outline.stroke()
            }
            rounded(NSRect(x: rect.minX + 10, y: rect.minY + 8, width: CGFloat([112, 144, 92][index]), height: 3), .secondaryLabelColor.withAlphaComponent(0.45), radius: 1.5)
            rounded(NSRect(x: rect.minX + 10, y: rect.minY + 15, width: CGFloat([78, 104, 128][index]), height: 3), .tertiaryLabelColor.withAlphaComponent(0.4), radius: 1.5)
        }
        if !dragging && time >= 0.5 {
            rounded(selection, .controlAccentColor.withAlphaComponent(0.07))
            let outline = NSBezierPath(roundedRect: selection, xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
        let cursor = NSPoint(x: selection.maxX + offset.x, y: selection.maxY + offset.y)
        let cursorRect = NSRect(x: min(box.maxX - 30, max(box.minX + 8, cursor.x - 4)),
                                y: min(box.maxY - 30, max(box.minY + 8, cursor.y - 4)),
                                width: 22, height: 22)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        Self.lightCursor.draw(in: cursorRect, from: .zero, operation: .sourceOver, fraction: fade, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let caption = dragging ? "Release shortcut to drag together" : "Hold shortcut and sweep across blocks"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let text = NSAttributedString(string: caption, attributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: 169))
    }

    private func drawSelectedText(time: Double) {
        func smooth(_ value: Double) -> CGFloat {
            let t = min(1, max(0, value))
            return CGFloat(t * t * (3 - 2 * t))
        }
        func rounded(_ rect: NSRect, color: NSColor, radius: CGFloat = 3) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        let selection = smooth((time - 0.2) / 0.8)
        let hintOpacity = smooth((time - 1.3) / 0.35)
        let drag = smooth((time - 2.8) / 1.5)
        let dropped = smooth((time - 4.5) / 0.25)
        let fade = 1 - smooth((time - 6.2) / 0.4)
        let lines = [NSRect(x: 34, y: 48, width: 218, height: 5), NSRect(x: 34, y: 78, width: 218, height: 5), NSRect(x: 34, y: 98, width: 142, height: 5)]
        for line in lines { rounded(line, color: .tertiaryLabelColor.withAlphaComponent(0.5), radius: 2) }
        let selected = [NSRect(x: 106, y: 40, width: 146, height: 21), NSRect(x: 34, y: 70, width: 136, height: 21)]
        for (index, rect) in selected.enumerated() {
            let progress = min(1, max(0, selection * 2 - CGFloat(index)))
            if progress <= 0 { continue }
            let selectedRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height)
            rounded(selectedRect, color: .selectedTextBackgroundColor.withAlphaComponent(0.4 * fade))
            rounded(NSRect(x: selectedRect.minX, y: selectedRect.minY + 8, width: selectedRect.width, height: 5), color: .labelColor.withAlphaComponent(0.6 * fade), radius: 2)
        }
        // The source selection stays in place; only the grabbed hint moves.
        let target = NSRect(x: 26, y: 119, width: 236, height: 35)
        rounded(target, color: .controlBackgroundColor, radius: 7)
        let targetOutline = NSBezierPath(roundedRect: target, xRadius: 7, yRadius: 7)
        NSColor.separatorColor.setStroke()
        targetOutline.stroke()
        let targetTitle = NSAttributedString(string: dropped > 0 ? "Selected text" : "Drop into an input", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: dropped > 0 ? NSColor.labelColor : NSColor.placeholderTextColor])
        targetTitle.draw(at: NSPoint(x: target.minX + 10, y: target.minY + 10))
        let opacity = hintOpacity * (1 - dropped) * fade
        let hint = NSRect(x: 104 - drag * 26, y: 36 + drag * 85, width: 132, height: 29)
        if opacity > 0 {
            rounded(hint, color: .controlBackgroundColor.withAlphaComponent(opacity), radius: 9)
            let outline = NSBezierPath(roundedRect: hint, xRadius: 9, yRadius: 9)
            NSColor.controlAccentColor.withAlphaComponent(0.8 * opacity).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
            let title = NSAttributedString(string: "Selected text", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor.withAlphaComponent(opacity)])
            title.draw(at: NSPoint(x: hint.minX + 12, y: hint.minY + 6))
        }
        let cursor = NSRect(x: hint.midX, y: hint.midY, width: 22, height: 22)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        Self.lightCursor.draw(in: cursor, from: .zero, operation: .sourceOver, fraction: hintOpacity * fade, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let shortcutHeld = time >= 1.3 && time < 3.2
        let keyState = NSAttributedString(string: shortcutHeld ? "Shortcut held" : "Shortcut released", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: shortcutHeld ? NSColor.controlAccentColor : NSColor.secondaryLabelColor])
        keyState.draw(at: NSPoint(x: 14, y: 12))
        let caption: String
        if time < 1.3 { caption = "Select text first" }
        else if time < 2.5 { caption = "Hold shortcut: hint under pointer" }
        else if time < 3.2 { caption = "Grab the hint and start dragging" }
        else if time < 4.5 { caption = "Keep dragging; shortcut can be released" }
        else { caption = "Release the mouse to drop" }
        let text = NSAttributedString(string: caption, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: 169))
    }
}

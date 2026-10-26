import AppKit

/// Product artwork drawn at the window's resolution; no screenshots or personal content.
final class OnboardingProductView: NSView {
    var step = 0 { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let top = dark ? NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.18, alpha: 1) : NSColor(calibratedRed: 0.91, green: 0.95, blue: 0.99, alpha: 1)
        let bottom = dark ? NSColor(calibratedRed: 0.19, green: 0.26, blue: 0.30, alpha: 1) : NSColor(calibratedRed: 0.66, green: 0.80, blue: 0.89, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: bounds, angle: 90)
        if step == 4 {
            AppIcon.image(for: effectiveAppearance)?.draw(in: NSRect(x: bounds.midX - 130, y: 280, width: 260, height: 260))
            return
        }
        func text(_ value: String, at point: NSPoint, size: CGFloat, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        func panel(_ rect: NSRect) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(dark ? 0.12 : 0.6).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22).stroke()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.withAlphaComponent(0.8).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.minX + 20 + CGFloat(index) * 18, y: rect.maxY - 29, width: 10, height: 10)).fill()
            }
        }
        let source = NSRect(x: 54, y: 290, width: 510, height: 260)
        let target = NSRect(x: 420, y: 225, width: 485, height: 230)
        panel(source)
        text("Drag & Drop instead.", at: NSPoint(x: 80, y: 460), size: 25, weight: .semibold)
        text("Drag what you need.", at: NSPoint(x: 80, y: 416), size: 17)
        text("From where you found it.", at: NSPoint(x: 80, y: 383), size: 17, color: .secondaryLabelColor)
        panel(target)
        text("Your prompt", at: NSPoint(x: 445, y: 376), size: 23, weight: .semibold)
        let field = NSRect(x: 444, y: 250, width: 437, height: 100)
        NSColor.textBackgroundColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: field, xRadius: 14, yRadius: 14).fill()
        text("Add context to your prompt…", at: NSPoint(x: 464, y: 310), size: 17, color: .secondaryLabelColor)
        let chip = NSRect(x: 230, y: 320, width: 180, height: 56)
        NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 18, yRadius: 18).fill()
        let cursor = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
            DragCursorIcon.image.draw(in: rect)
            NSColor.labelColor.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        cursor.draw(in: NSRect(x: 246, y: 333, width: 28, height: 28))
        text("Drag", at: NSPoint(x: 290, y: 335), size: 18, weight: .medium)
        if step == 2 {
            text(CaptureShortcut.current.title, at: NSPoint(x: 695, y: 485), size: 38, color: .secondaryLabelColor, weight: .medium)
        } else if step == 3 {
            let notice = NSRect(x: 595, y: 475, width: 310, height: 68)
            NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: notice, xRadius: 16, yRadius: 16).fill()
            AppIcon.image(for: effectiveAppearance)?.draw(in: NSRect(x: 609, y: 489, width: 40, height: 40))
            text("Drag 2.0", at: NSPoint(x: 660, y: 512), size: 13, weight: .semibold)
            text("An update is ready", at: NSPoint(x: 660, y: 490), size: 14)
        }
    }
}

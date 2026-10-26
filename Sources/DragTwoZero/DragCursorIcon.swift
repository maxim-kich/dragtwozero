import AppKit

/// Template artwork uses the hint's semantic label tint in either appearance.
/// Custom motion marks keep the three-line identity consistent with the app icon.
enum DragCursorIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 2.5, y: 2))
            arrow.line(to: NSPoint(x: 16, y: 14))
            arrow.line(to: NSPoint(x: 10.5, y: 14.5))
            arrow.line(to: NSPoint(x: 14, y: 21))
            arrow.line(to: NSPoint(x: 10.5, y: 23))
            arrow.line(to: NSPoint(x: 7, y: 16.5))
            arrow.line(to: NSPoint(x: 2.5, y: 20.5))
            arrow.close()
            arrow.lineJoinStyle = .round
            arrow.lineWidth = 1
            arrow.fill(); arrow.stroke()
            for (start, end, y): (CGFloat, CGFloat, CGFloat) in [(10, 17, 2.5), (14, 20, 6.5), (18, 23, 10.5)] {
                let line = NSBezierPath()
                line.lineWidth = 2
                line.lineCapStyle = .round
                line.move(to: NSPoint(x: start, y: y))
                line.line(to: NSPoint(x: end, y: y))
                line.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Drag"
        return image
    }()
}

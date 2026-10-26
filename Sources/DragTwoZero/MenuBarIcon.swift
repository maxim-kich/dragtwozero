import AppKit

/// A template brand mark with a centered cursor and open, rounded outlines. macOS supplies
/// its foreground color so the menu bar remains legible in either appearance.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            NSColor.black.setStroke()
            let tiles = NSBezierPath()
            // Deliberate open ends leave transparent clearance around the cursor
            // and its motion lines without small clipped fragments.
            tiles.move(to: NSPoint(x: 12.14, y: 3.55))
            tiles.curve(to: NSPoint(x: 9.8, y: 2.5),
                        controlPoint1: NSPoint(x: 11.59, y: 2.85),
                        controlPoint2: NSPoint(x: 10.79, y: 2.5))
            tiles.line(to: NSPoint(x: 4.9, y: 2.5))
            tiles.curve(to: NSPoint(x: 1.88, y: 5.51),
                        controlPoint1: NSPoint(x: 3.23, y: 2.5),
                        controlPoint2: NSPoint(x: 1.88, y: 3.84))
            tiles.line(to: NSPoint(x: 1.88, y: 10.19))
            tiles.curve(to: NSPoint(x: 4.9, y: 13.05),
                        controlPoint1: NSPoint(x: 1.88, y: 11.86),
                        controlPoint2: NSPoint(x: 3.23, y: 13.05))
            tiles.line(to: NSPoint(x: 5.1, y: 13.05))

            tiles.move(to: NSPoint(x: 10.93, y: 16.79))
            tiles.curve(to: NSPoint(x: 12.9, y: 17.56),
                        controlPoint1: NSPoint(x: 11.46, y: 17.31),
                        controlPoint2: NSPoint(x: 12.1, y: 17.56))
            tiles.line(to: NSPoint(x: 15.3, y: 17.56))
            tiles.curve(to: NSPoint(x: 18.16, y: 14.6),
                        controlPoint1: NSPoint(x: 16.97, y: 17.56),
                        controlPoint2: NSPoint(x: 18.16, y: 16.3))
            tiles.line(to: NSPoint(x: 18.16, y: 10.96))
            tiles.curve(to: NSPoint(x: 17.94, y: 9.7),
                        controlPoint1: NSPoint(x: 18.16, y: 10.5),
                        controlPoint2: NSPoint(x: 18.1, y: 10.08))
            tiles.lineWidth = 1
            tiles.lineCapStyle = .round
            tiles.lineJoinStyle = .round
            tiles.stroke()
            DragCursorIcon.image.draw(in: NSRect(x: 5.765, y: 4.275, width: 11.04, height: 11.04),
                                      from: .zero, operation: .sourceOver, fraction: 1,
                                      respectFlipped: true, hints: nil)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DragTwoZero"
        return image
    }()
}

import AppKit

// Static Finder artwork; native file icons remain interactive above it.
let size = NSSize(width: 720, height: 460)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 920,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGradient(colors: [NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1),
                    NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.055, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: 65)
func text(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (string as NSString).draw(in: NSRect(x: 40, y: y, width: 640, height: 48), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: alpha), .paragraphStyle: style])
}
text("Your new copy paste", y: 350, size: 30, weight: .semibold, alpha: 1)
// A single restrained glass-like tray joins the two installation destinations.
let tray = NSBezierPath(roundedRect: NSRect(x: 105, y: 135, width: 510, height: 165), xRadius: 38, yRadius: 38)
NSColor.white.withAlphaComponent(0.035).setFill(); tray.fill()
NSColor.white.withAlphaComponent(0.09).setStroke(); tray.lineWidth = 1; tray.stroke()
// Finder renders native filenames in black over custom pictures.
// Keep those accessible, real labels readable without renaming the files.
for (center, width) in [(CGFloat(225), CGFloat(162)), (CGFloat(495), CGFloat(116))] {
    let labelBacking = NSBezierPath(roundedRect: NSRect(x: center - width / 2, y: 151, width: width, height: 26), xRadius: 8, yRadius: 8)
    NSColor.white.withAlphaComponent(0.5).setFill()
    labelBacking.fill()
}
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 337, y: 222)); arrow.line(to: NSPoint(x: 383, y: 222))
arrow.move(to: NSPoint(x: 373, y: 232)); arrow.line(to: NSPoint(x: 383, y: 222)); arrow.line(to: NSPoint(x: 373, y: 212))
arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0.9, alpha: 0.4).setStroke(); arrow.stroke()
text("Drag 2.0 (Alpha) to Applications", y: 72, size: 15, weight: .regular, alpha: 0.7)
NSGraphicsContext.restoreGraphicsState()
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

import AppKit
import ScreenCaptureKit

enum BackdropTone: Equatable { case light, dark }

/// A single low-resolution measurement per recognized target. No stream or stored frames.
actor BackdropAppearanceSampler {
    private var content: SCShareableContent?
    private var refreshedAt: TimeInterval = 0

    func tone(in frame: CGRect) async -> BackdropTone? {
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(),
              frame.width > 0, frame.height > 0 else { return nil }
        do {
            let now = ProcessInfo.processInfo.systemUptime
            if content == nil || now - refreshedAt > 5 || content?.applications.contains(where: { $0.processID == getpid() }) != true {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                refreshedAt = now
            }
            guard let content,
                  let display = content.displays.max(by: { intersectionArea($0.frame, frame) < intersectionArea($1.frame, frame) }) else { return nil }
            let region = frame.intersection(display.frame)
            guard !region.isNull, region.width > 0, region.height > 0 else { return nil }
            let filter = SCContentFilter(display: display,
                excludingApplications: content.applications.filter { $0.processID == getpid() }, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = 32; config.height = 32
            config.showsCursor = false; config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return backdropTone(image)
        } catch { return nil }
    }
}

private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let rect = a.intersection(b)
    return rect.isNull ? 0 : rect.width * rect.height
}

func backdropTone(_ image: CGImage) -> BackdropTone? {
    let side = 32
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { data -> Bool in
        guard let context = CGContext(data: data.baseAddress, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { return nil }
    var luminance: Double = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        luminance += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
    }
    return luminance / Double(side * side * 255) >= 0.5 ? .light : .dark
}

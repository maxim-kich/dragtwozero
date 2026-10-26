import AppKit
import XCTest
@testable import DragTwoZero

final class BackdropAppearanceTests: XCTestCase {
    private func image(background: NSColor, ink: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        if ink {
            context.setFillColor(NSColor.black.cgColor)
            for y in stride(from: 8, to: 60, by: 12) { context.fill(CGRect(x: 8, y: y, width: 40, height: 2)) }
        }
        return context.makeImage()!
    }
    func testWhiteParagraphWithDarkTextUsesLightAppearance() {
        XCTAssertEqual(backdropTone(image(background: .white, ink: true)), .light)
    }
    func testDarkBackdropUsesDarkAppearance() {
        XCTAssertEqual(backdropTone(image(background: .black)), .dark)
    }
    func testBrightnessUsesLuminanceRatherThanEqualRGBWeights() {
        XCTAssertEqual(backdropTone(image(background: .green)), .light)
        XCTAssertEqual(backdropTone(image(background: .blue)), .dark)
    }
}

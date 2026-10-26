import AppKit

enum AppIcon {
    static func image(for appearance: NSAppearance) -> NSImage? {
        let name = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "AppIconDark" : "AppIcon"
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }
}
final class AppIconView: NSImageView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        image = AppIcon.image(for: effectiveAppearance)
        NSApp.applicationIconImage = image
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        image = AppIcon.image(for: effectiveAppearance)
    }
}

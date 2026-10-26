import AppKit

/// Center actual text bounds rather than an oversized text-field frame.
/// AppKit alignment rectangles exclude a control's decorative insets.
func alignSettingsLabels(_ labels: [NSTextField], centerY: CGFloat) {
    guard !labels.isEmpty else { return }
    for label in labels {
        label.frame.size.height = ceil(label.intrinsicContentSize.height)
    }
    let bottom = labels.map { $0.frame.minY }.min()!
    let top = labels.map { $0.frame.maxY }.max()!
    let shift = centerY - (bottom + top) / 2
    for label in labels { label.frame.origin.y += shift }
}

func alignSettingsLabels(_ labels: [NSTextField], with control: NSView) {
    alignSettingsLabels(labels, centerY: control.alignmentRect(forFrame: control.frame).midY)
}

func settingsOutlineCard(_ frame: NSRect) -> NSBox {
    let box = NSBox(frame: frame)
    box.boxType = .custom
    box.borderColor = .separatorColor
    box.borderWidth = 0.5
    box.cornerRadius = 12
    box.fillColor = .controlBackgroundColor
    box.contentViewMargins = .zero
    return box
}

func settingsCardDivider(y: CGFloat, width: CGFloat) -> NSBox {
    let divider = NSBox(frame: NSRect(x: 16, y: y, width: width - 32, height: 1))
    divider.boxType = .separator
    divider.setAccessibilityElement(false)
    return divider
}

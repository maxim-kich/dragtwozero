import AppKit

final class GlassSettingsView: NSView {
    private let toggle = NSSwitch()
    private let colors = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appearanceControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let borderLabel = NSTextField(labelWithString: "Border color")
    private let appearanceLabel = NSTextField(labelWithString: "Color mode")
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init(frame: CGRect(x: 0, y: 0, width: 592, height: 172))
        let glassRow = settingsOutlineCard(NSRect(x: 0, y: 120, width: 592, height: 52))
        let colorRow = settingsOutlineCard(NSRect(x: 0, y: 60, width: 592, height: 52))
        let appearanceRow = settingsOutlineCard(NSRect(x: 0, y: 0, width: 592, height: 52))
        [glassRow, colorRow, appearanceRow].forEach { addSubview($0) }
        let title = NSTextField(labelWithString: "Liquid Glass")
        title.frame = CGRect(x: 16, y: 16, width: 180, height: 20)
        glassRow.contentView?.addSubview(title)
        toggle.frame = CGRect(x: 530, y: 14, width: 40, height: 24)
        toggle.state = CapturePreferences.liquidGlassEnabled ? .on : .off
        toggle.target = self; toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("Liquid Glass")
        glassRow.contentView?.addSubview(toggle)
        borderLabel.frame = CGRect(x: 16, y: 16, width: 90, height: 20)
        colorRow.contentView?.addSubview(borderLabel)
        colors.frame = CGRect(x: 416, y: 12, width: 157, height: 28)
        for color in BorderColor.allCases {
            colors.addItem(withTitle: color.title)
            colors.lastItem?.representedObject = color.rawValue
            let swatch = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                color.color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            colors.lastItem?.image = swatch
        }
        colors.selectItem(at: BorderColor.allCases.firstIndex(of: CapturePreferences.borderColor) ?? 0)
        colors.target = self; colors.action = #selector(colorChanged)
        colors.setAccessibilityLabel("Selection border color")
        colors.isEnabled = !CapturePreferences.liquidGlassEnabled
        colorRow.contentView?.addSubview(colors)
        appearanceLabel.frame = CGRect(x: 16, y: 16, width: 90, height: 20)
        appearanceRow.contentView?.addSubview(appearanceLabel)
        appearanceControl.frame = CGRect(x: 416, y: 12, width: 157, height: 28)
        appearanceControl.addItems(withTitles: BorderAppearance.allCases.map(\.title))
        appearanceControl.selectItem(at: BorderAppearance.allCases.firstIndex(of: CapturePreferences.borderAppearance) ?? 0)
        appearanceControl.target = self; appearanceControl.action = #selector(appearanceChanged)
        appearanceControl.setAccessibilityLabel("Color mode")
        appearanceControl.isEnabled = !CapturePreferences.liquidGlassEnabled
        appearanceRow.contentView?.addSubview(appearanceControl)
        alignSettingsLabels([title], with: toggle)
        alignSettingsLabels([borderLabel], with: colors)
        alignSettingsLabels([appearanceLabel], with: appearanceControl)
        refreshAvailability()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func toggleChanged() {
        CapturePreferences.liquidGlassEnabled = toggle.state == .on
        refreshAvailability()
        onChange()
    }
    private func refreshAvailability() {
        let enabled = !CapturePreferences.liquidGlassEnabled
        colors.isEnabled = enabled
        appearanceControl.isEnabled = enabled
        borderLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
        appearanceLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
        let help = enabled ? nil : "Turn off Liquid Glass to use this option."
        for view in [colors, appearanceControl, borderLabel, appearanceLabel] { view.toolTip = help }
    }
    @objc private func appearanceChanged() {
        guard !CapturePreferences.liquidGlassEnabled else { return }
        guard BorderAppearance.allCases.indices.contains(appearanceControl.indexOfSelectedItem) else { return }
        CapturePreferences.borderAppearance = BorderAppearance.allCases[appearanceControl.indexOfSelectedItem]
        onChange()
    }
    @objc private func colorChanged() {
        guard !CapturePreferences.liquidGlassEnabled else { return }
        guard let raw = colors.selectedItem?.representedObject as? String,
              let color = BorderColor(rawValue: raw) else { return }
        CapturePreferences.borderColor = color
        onChange()
    }
}

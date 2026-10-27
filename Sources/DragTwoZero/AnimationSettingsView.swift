import AppKit

/// Native animation controls used in the Settings window.
final class AnimationSettingsView: NSView {
    private let toggle = NSSwitch()
    private let titleLabel = NSTextField(labelWithString: "Animations")
    private var rangeLabels: [NSTextField] = []
    private let slider = NSSlider(value: CapturePreferences.animationSpeed, minValue: 0.5, maxValue: 2, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 592, height: 140))
        let card = settingsOutlineCard(bounds)
        addSubview(card)
        titleLabel.frame = CGRect(x: 16, y: 104, width: 180, height: 20)
        card.contentView?.addSubview(titleLabel)
        toggle.frame = CGRect(x: 530, y: 102, width: 40, height: 24)
        toggle.state = CapturePreferences.animationsEnabled ? .on : .off
        toggle.target = self; toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("Animations")
        toggle.toolTip = "Animate selection, hint, drag, and drop transitions."
        card.contentView?.addSubview(toggle)
        speedLabel.frame = CGRect(x: 16, y: 62, width: 556, height: 18)
        speedLabel.font = .systemFont(ofSize: 12)
        card.contentView?.addSubview(speedLabel)
        slider.frame = CGRect(x: 16, y: 30, width: 556, height: 24)
        slider.isContinuous = true
        slider.target = self; slider.action = #selector(speedChanged)
        slider.setAccessibilityLabel("Animation speed")
        card.contentView?.addSubview(slider)
        for (text, x) in [("Slower · 0.5×", CGFloat(16)), ("Faster · 2×", CGFloat(482))] {
            let label = NSTextField(labelWithString: text)
            label.frame = CGRect(x: x, y: 8, width: 90, height: 16)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            if x > 16 { label.alignment = .right }
            card.contentView?.addSubview(label)
            rangeLabels.append(label)
        }
        alignSettingsLabels([titleLabel], with: toggle)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggleChanged() {
        guard CapturePreferences.liquidGlassEnabled else { return }
        CapturePreferences.animationsEnabled = toggle.state == .on
        refresh()
    }
    @objc private func speedChanged() {
        guard CapturePreferences.liquidGlassEnabled && CapturePreferences.animationsEnabled else { return }
        CapturePreferences.animationSpeed = (slider.doubleValue * 10).rounded() / 10
        refresh()
    }
    func refresh() {
        toggle.isEnabled = CapturePreferences.liquidGlassEnabled
        toggle.state = CapturePreferences.liquidGlassEnabled && CapturePreferences.animationsEnabled ? .on : .off
        slider.isEnabled = CapturePreferences.liquidGlassEnabled && CapturePreferences.animationsEnabled
        titleLabel.textColor = toggle.isEnabled ? .labelColor : .disabledControlTextColor
        speedLabel.textColor = slider.isEnabled ? .labelColor : .disabledControlTextColor
        for label in rangeLabels {
            label.textColor = slider.isEnabled ? .secondaryLabelColor : .disabledControlTextColor
        }
        toolTip = toggle.isEnabled ? nil : "Turn on Liquid Glass to enable animations."
        toggle.toolTip = toolTip ?? "Animate selection, hint, drag, and drop transitions."
        slider.toolTip = toolTip
        speedLabel.stringValue = String(format: "Animation speed · %.1f×", CapturePreferences.animationSpeed)
    }
}

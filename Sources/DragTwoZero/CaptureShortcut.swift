import AppKit

struct CaptureShortcut: Codable, Equatable {
    let modifiers: UInt64
    let keyCode: UInt16?
    let keyLabel: String
    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]
    static let defaultValue = CaptureShortcut(modifiers: CGEventFlags([.maskAlternate, .maskCommand]).rawValue, keyCode: nil, keyLabel: "")
    static var current: CaptureShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: "captureShortcut"),
                  let shortcut = try? JSONDecoder().decode(Self.self, from: data), shortcut.modifiers != 0 else { return .defaultValue }
            return shortcut
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "captureShortcut") }
    }
    var title: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return [(CGEventFlags.maskSecondaryFn, "fn"), (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined() + keyLabel
    }
    func matches(flags: CGEventFlags, keyPressed: Bool) -> Bool {
        flags.contains(CGEventFlags(rawValue: modifiers)) && (keyCode == nil || keyPressed)
    }
    func isHeld(flags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState), event: CGEvent? = nil,
                type: CGEventType? = nil, observedKeyDown: Bool? = nil) -> Bool {
        // A consumed event-tap keyDown need not reach combinedSessionState.
        // Callers observing that stream must use their paired down/up state.
        var keyPressed = keyCode.map { observedKeyDown ?? CGEventSource.keyState(.combinedSessionState, key: $0) } ?? false
        if let keyCode, let event, UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode {
            if type == .keyDown { keyPressed = true }
            if type == .keyUp { keyPressed = false }
        }
        return matches(flags: flags, keyPressed: keyPressed)
    }
}

/// Keys consumed by the event tap, independently of shortcut configuration.
/// Release bookkeeping must run even while capture/recording/onboarding gates
/// suppress gestures. Tracking codes prevents a changed shortcut inheriting an
/// old key's held state.
struct CaptureShortcutKeyState {
    private var consumed: Set<UInt16> = []
    mutating func consumeKeyDown(_ code: UInt16) { consumed.insert(code) }
    @discardableResult
    mutating func releaseKey(_ code: UInt16) -> Bool { consumed.remove(code) != nil }
    func isPressed(for shortcut: CaptureShortcut) -> Bool {
        shortcut.keyCode.map { consumed.contains($0) } ?? false
    }
    func consumesAutorepeat(for shortcut: CaptureShortcut, code: UInt16, flags: CGEventFlags, isAutorepeat: Bool) -> Bool {
        isAutorepeat && shortcut.keyCode == code && isPressed(for: shortcut)
            && shortcut.matches(flags: flags, keyPressed: true)
    }
    mutating func reset() { consumed.removeAll() }
}

final class ShortcutRecorderView: NSView {
    static var isRecording = false
    private let button = NSButton(title: "", target: nil, action: nil)
    private let reset = NSButton()
    private var monitor: Any?
    private var deactivation: NSObjectProtocol?
    private var pendingModifiers: UInt64 = 0
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 224, height: 32))
        button.frame = NSRect(x: 0, y: 0, width: 184, height: 32)
        button.bezelStyle = .rounded
        button.target = self; button.action = #selector(startRecording)
        button.setAccessibilityLabel("Trigger Shortcut")
        button.toolTip = "Click, then press a shortcut, including Fn or a modifier combination. Escape cancels."
        addSubview(button)
        reset.frame = NSRect(x: 192, y: 2, width: 28, height: 28)
        reset.bezelStyle = .inline
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset shortcut")
        reset.target = self; reset.action = #selector(resetShortcut)
        reset.toolTip = "Reset to Option + Command"
        addSubview(reset)
        reset.frame.origin.y += controlCenterY - reset.alignmentRect(forFrame: reset.frame).midY
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var controlCenterY: CGFloat { button.alignmentRect(forFrame: button.frame).midY }
    private func refresh() {
        button.title = CaptureShortcut.current.title
        reset.isHidden = CaptureShortcut.current == .defaultValue
        button.frame.origin.x = reset.isHidden ? bounds.width - button.frame.width : 0
    }
    @objc private func startRecording() {
        if monitor != nil { cancelRecording(); return }
        onChange()
        Self.isRecording = true
        pendingModifiers = 0
        button.title = "Press shortcut…"
        deactivation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.cancelRecording() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown { self.cancelRecording(); return event }
            let flags = UInt64(event.modifierFlags.rawValue) & CaptureShortcut.modifierMask.rawValue
            if event.type == .flagsChanged {
                if flags == 0, self.pendingModifiers != 0 {
                    self.save(CaptureShortcut(modifiers: self.pendingModifiers, keyCode: nil, keyLabel: ""))
                } else if flags.nonzeroBitCount >= self.pendingModifiers.nonzeroBitCount {
                    self.pendingModifiers = flags
                    self.button.title = CaptureShortcut(modifiers: flags, keyCode: nil, keyLabel: "").title
                }
                return nil
            }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
            // Fn can be used alone or combined with another key/modifier.
            let primary = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]).rawValue
            guard flags & primary != 0 else { NSSound.beep(); return nil }
            let names: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            self.save(CaptureShortcut(modifiers: flags, keyCode: event.keyCode, keyLabel: label))
            return nil
        }
    }
    private func save(_ shortcut: CaptureShortcut) {
        CaptureShortcut.current = shortcut
        cancelRecording()
        onChange()
    }
    func cancelRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
        monitor = nil; deactivation = nil
        Self.isRecording = false
        refresh()
    }
    @objc private func resetShortcut() { save(.defaultValue) }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
    }
}

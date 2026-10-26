import AppKit
import QuartzCore

enum CaptureWindowLayers {
    static var buffer: NSWindow.Level { NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.helpWindow)) + 2) }
    static var hint: NSWindow.Level { NSWindow.Level(rawValue: buffer.rawValue + 1) }
}

enum BufferLayout {
    static let contentHeight: CGFloat = 108
    static let slotCornerRadius: CGFloat = 12
    static func slot(in bounds: CGRect) -> CGRect { CGRect(x: 12, y: 12, width: bounds.width - 24, height: 48) }
    static func close(in bounds: CGRect) -> CGRect { CGRect(x: bounds.width - 38, y: 74, width: 28, height: 28) }
}

enum BufferPosition: String, CaseIterable {
    case leftBottom, rightBottom, leftTop, rightTop, notch
    var title: String {
        switch self {
        case .leftBottom: return "Left bottom"
        case .rightBottom: return "Right bottom"
        case .leftTop: return "Left top"
        case .rightTop: return "Right top"
        case .notch: return "Dynamic Island"
        }
    }
}

/// An in-memory snapshot, independent of the original app, document, and AX tree.
struct BufferItem {
    let id = UUID()
    let payload: CapturePayload
    let symbol: String
    var deliveryUnconfirmed = false
}

struct CaptureBuffer {
    private(set) var item: BufferItem?
    /// Replacement is authorized only by a deliberate drop onto the slot.
    @discardableResult mutating func store(_ payload: CapturePayload, symbol: String, replacing: Bool = false) -> Bool {
        guard item == nil || replacing else { return false }
        item = BufferItem(payload: payload, symbol: symbol)
        return true
    }
    mutating func clear() { item = nil }
    @discardableResult mutating func consume(id: UUID) -> Bool {
        guard item?.id == id else { return false }
        item = nil
        return true
    }
    mutating func finishDelivery(id: UUID, confirmed: Bool) {
        guard item?.id == id else { return }
        if confirmed { consume(id: id) }
        else { item?.deliveryUnconfirmed = true }
    }
}

/// Cocoa coordinates. Corner positions respect the menu bar and Dock. Notch
/// mode joins the physical screen edge and reserves the camera's safe area.
func bufferFrame(position: BufferPosition, screen: CGRect, visibleFrame: CGRect,
                 safeAreaTop: CGFloat, notchWidth: CGFloat = 0) -> CGRect {
    let margin: CGFloat = 20
    let width = min(position == .notch ? max(304, notchWidth + 32) : 304, visibleFrame.width - 2 * margin)
    let height = BufferLayout.contentHeight + (position == .notch ? max(0, safeAreaTop) : 0)
    switch position {
    case .leftBottom: return CGRect(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin, width: width, height: height)
    case .rightBottom: return CGRect(x: visibleFrame.maxX - margin - width, y: visibleFrame.minY + margin, width: width, height: height)
    case .leftTop: return CGRect(x: visibleFrame.minX + margin, y: visibleFrame.maxY - margin - height, width: width, height: height)
    case .rightTop: return CGRect(x: visibleFrame.maxX - margin - width, y: visibleFrame.maxY - margin - height, width: width, height: height)
    case .notch: return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
}

enum BufferMotion {
    static func hiddenFrame(position: BufferPosition, shown: CGRect, screen: CGRect,
                            safeAreaTop: CGFloat, notchWidth: CGFloat) -> CGRect {
        switch position {
        case .leftBottom, .leftTop:
            return shown.offsetBy(dx: screen.minX - shown.maxX - 8, dy: 0)
        case .rightBottom, .rightTop:
            return shown.offsetBy(dx: screen.maxX - shown.minX + 8, dy: 0)
        case .notch:
            let width = min(shown.width, max(120, notchWidth))
            let height = max(2, safeAreaTop)
            return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
        }
    }
    static func progress(_ time: CGFloat, position: BufferPosition) -> CGFloat {
        let t = min(1, max(0, time))
        if t == 0 || t == 1 { return t }
        if position == .notch {
            // A critically damped expansion stays liquid without crossing the
            // destination and performing a second settling motion after arrival.
            let end = 1 - 11 * exp(CGFloat(-10))
            return (1 - (1 + 10 * t) * exp(-10 * t)) / end
        }
        return 1 - pow(1 - t, 3)
    }
    /// Hide clipped control fragments until the expanding surface can contain
    /// them. The surface keeps its existing easing and duration.
    static func contentOpacity(visibleHeight: CGFloat, fullHeight: CGFloat) -> CGFloat {
        guard fullHeight > 0 else { return 0 }
        let t = min(1, max(0, (visibleHeight / fullHeight - 0.55) / 0.45))
        return t * t * (3 - 2 * t)
    }
    /// A nearly collapsed black surface reads as a stray line on the menu bar.
    /// Reveal it only once the area below the camera has room for its rounded
    /// edge. Geometry, rather than elapsed time, also handles reversed motion.
    static func surfaceOpacity(frameHeight: CGFloat, shownHeight: CGFloat) -> CGFloat {
        let safeTop = max(0, shownHeight - BufferLayout.contentHeight)
        let visibleHeight = frameHeight - safeTop
        let t = min(1, max(0, (visibleHeight - 18) / 18))
        return t * t * (3 - 2 * t)
    }
    static func frame(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        CGRect(x: from.minX + (to.minX - from.minX) * progress,
               y: from.minY + (to.minY - from.minY) * progress,
               width: max(1, from.width + (to.width - from.width) * progress),
               height: max(1, from.height + (to.height - from.height) * progress))
    }
}

private final class BufferPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BufferRootView: NSView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}

private final class BufferSlotView: NSView {
    var onDrag: ((NSEvent) -> Void)?
    private var started = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { started = false }
    override func mouseDragged(with event: NSEvent) {
        guard !started else { return }
        started = true; onDrag?(event)
    }
}

final class BufferOverlay {
    private let panel = BufferPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let root = BufferRootView()
    private let content = NSView()
    private let title = NSTextField(labelWithString: "Buffer")
    private let recoveryNotice = NSTextField(labelWithString: "Drop unconfirmed. Check input before retrying.")
    private let slot = BufferSlotView()
    private let slotBorder = CAShapeLayer()
    private let label = NSTextField(labelWithString: "Drop content here")
    private let icon = NSImageView()
    private let closeButton = NSButton()
    private var surface: NSView?
    private var item: BufferItem?
    private var captureVisible = false
    private var dismissed = false
    private var screen: NSScreen?
    private var position: BufferPosition?
    private var ready = false
    private var draggingOut = false
    private var receiving = false
    private var requestedVisible = false
    private var shownFrame = CGRect.zero
    private var hiddenFrame = CGRect.zero
    private var presentationFrame = CGRect.zero
    private var motionTimer: AnimationFrames?
    private var motionGeneration = 0
    var onClose: (() -> Void)?
    var onNativeDrag: ((BufferItem, CGRect, NSView, NSEvent) -> Void)?

    init() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = CaptureWindowLayers.buffer
        panel.ignoresMouseEvents = true // The event tap owns only the bounded content/close regions.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = root
        root.wantsLayer = true
        for view in [root, content, title, recoveryNotice, slot, label, icon, closeButton] { view.focusRingType = .none }
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        recoveryNotice.font = .systemFont(ofSize: 10)
        recoveryNotice.isHidden = true
        slot.wantsLayer = true
        slot.layer?.cornerRadius = BufferLayout.slotCornerRadius
        slotBorder.lineWidth = 1
        slot.layer?.addSublayer(slotBorder)
        slot.onDrag = { [weak self] event in
            guard let self, let item = self.item, let frame = self.targetFrame else { return }
            self.onNativeDrag?(item, frame, self.slot, event)
        }
        content.addSubview(title); content.addSubview(recoveryNotice); content.addSubview(slot)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true; label.cell?.wraps = false
        slot.addSubview(label); slot.addSubview(icon); content.addSubview(closeButton)
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Buffer and remove content")
        closeButton.imagePosition = .imageOnly
        closeButton.target = self; closeButton.action = #selector(closeClicked)
        closeButton.setAccessibilityLabel("Close Buffer and remove content")
        closeButton.toolTip = "Close Buffer and remove content"
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        root.appearanceChanged = { [weak self] in
            // AppKit propagates appearance down the hierarchy after notifying
            // the root. Resolve content colors after its descendants inherit it.
            DispatchQueue.main.async { [weak self] in self?.refreshSlotAppearance() }
        }
    }
    deinit { motionTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    func close() {
        motionGeneration += 1; motionTimer?.invalidate(); motionTimer = nil
        requestedVisible = false
        panel.orderOut(nil); panel.close()
    }
    @objc private func closeClicked() { onClose?() }
    @objc private func screensChanged() {
        if !NSScreen.screens.contains(where: { $0 === screen }) { screen = nil }
        present()
    }
    func beginCapture(at point: CGPoint) {
        dismissed = false
        if item == nil { screen = screenAt(point) }
        captureVisible = true
        present()
    }
    func showCaptureTarget(at point: CGPoint) {
        guard captureVisible, !dismissed else { return }
        if item == nil { screen = screenAt(point) }
        present()
    }
    func endCapture() { captureVisible = false; setDropReady(false); present() }
    func refresh(item: BufferItem?, dragging: Bool = false) {
        self.item = item
        draggingOut = dragging
        receiving = false
        // The overlay takes ownership of this preview at lift. Do not carry a
        // second copy of its text/icon away with the exiting container.
        label.alphaValue = dragging ? 0 : 1; icon.alphaValue = dragging ? 0 : 1
        present()
    }
    func setReceiving(_ value: Bool) {
        receiving = value
        label.alphaValue = value || draggingOut ? 0 : 1; icon.alphaValue = value || draggingOut ? 0 : 1
        refreshSlotAppearance()
    }
    func dismiss() {
        dismissed = true; captureVisible = false; item = nil; draggingOut = false
        setDropReady(false); hide()
    }
    /// Keep recovery in memory without reopening the shelf on a recipient click
    /// or app activation. Only a new explicit capture reveals it again.
    func hideUntilNextCapture() {
        dismissed = true; captureVisible = false
        setDropReady(false); hide()
    }
    func repositionForActiveSpace() {
        screen = screenAt(quartz(NSEvent.mouseLocation))
        present()
    }
    private func quartz(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    private func screenAt(_ point: CGPoint) -> NSScreen? {
        let cocoa = quartz(point)
        return NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func screenFrame(of view: NSView) -> CGRect? {
        guard requestedVisible, panel.isVisible, panel.alphaValue > 0.1,
              !draggingOut, content.alphaValue > 0.1 else { return nil }
        let rect = view.convert(view.bounds, to: nil).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        var clipped = rect.intersection(panel.frame)
        if position == .notch {
            clipped = clipped.intersection(presentationFrame)
        }
        if let screen {
            var usable = screen.frame
            if position == .notch { usable.size.height -= screen.safeAreaInsets.top }
            clipped = clipped.intersection(usable)
        }
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return CGRect(x: clipped.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - clipped.maxY, width: clipped.width, height: clipped.height)
    }
    var targetFrame: CGRect? { screenFrame(of: slot) }
    var containerFrame: CGRect? { screenFrame(of: content) }
    var closeFrame: CGRect? { screenFrame(of: closeButton) }
    func contains(_ point: CGPoint) -> Bool { containerFrame?.contains(point) == true }
    func slotContains(_ point: CGPoint) -> Bool { targetFrame?.contains(point) == true }
    func closeContains(_ point: CGPoint) -> Bool {
        closeFrame?.contains(point) == true
    }
    func setDropReady(_ value: Bool) {
        guard ready != value else { return }
        ready = value
        let changes = {
            self.refreshSlotAppearance()
            self.icon.contentTintColor = self.position == .notch ? .white : .labelColor
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CapturePreferences.animationDuration(0.14)
            context.allowsImplicitAnimation = context.duration > 0
            changes()
        }
    }
    private func refreshSlotAppearance() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        effectiveAppearanceColors {
            let color: NSColor = self.position == .notch ? .white : .labelColor
            self.slot.layer?.backgroundColor = color.withAlphaComponent(self.ready ? 0.10 : 0.045).cgColor
            self.slotBorder.fillColor = NSColor.clear.cgColor
            // The capture scene supplies the merging highlight. An accent stroke
            // below that glass leaves blue fragments around its rounded corners.
            self.slotBorder.strokeColor = color.withAlphaComponent(self.ready ? 0.3 : (self.item == nil ? 0.25 : 0.12)).cgColor
            self.slotBorder.lineWidth = self.ready ? 1.2 : 1
            self.slotBorder.lineDashPattern = self.ready || self.item != nil ? nil : [4, 4]
            // The native glass highlight owns this edge while merging. A second
            // stroke beneath it remains exposed at the rounded corners.
            self.slotBorder.isHidden = self.ready || self.receiving
        }
    }
    private func effectiveAppearanceColors(_ changes: () -> Void) {
        content.effectiveAppearance.performAsCurrentDrawingAppearance(changes)
    }
    private func present() {
        guard CapturePreferences.bufferEnabled, !dismissed, !draggingOut, item != nil || captureVisible else { hide(); return }
        panel.ignoresMouseEvents = item == nil
        let screen = self.screen ?? screenAt(quartz(NSEvent.mouseLocation))
        guard let screen else { return }
        self.screen = screen
        let position = CapturePreferences.bufferPosition
        if self.position != position || surface == nil {
            surface?.removeFromSuperview()
            let view: NSView
            if position == .notch {
                view = NSView(); view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.black.cgColor
                view.layer?.cornerRadius = 18
                view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            } else if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                // A persistent shelf needs the regular material's legibility
                // treatment while unrelated apps and backdrops move underneath it.
                glass.style = .regular; glass.cornerRadius = 18
                glass.focusRingType = .none
                view = glass
            } else {
                let effect = NSVisualEffectView()
                effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
                effect.wantsLayer = true; effect.layer?.cornerRadius = 18; effect.layer?.masksToBounds = true
                view = effect
            }
            view.wantsLayer = true
            root.addSubview(view)
            if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView { glass.contentView = content }
            else { view.addSubview(content) }
            surface = view; self.position = position
        }
        var safeTop: CGFloat = 0, notchWidth: CGFloat = 0
        if #available(macOS 12.0, *) {
            safeTop = screen.safeAreaInsets.top
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notchWidth = max(0, right.minX - left.maxX)
            }
        }
        let frame = bufferFrame(position: position, screen: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: safeTop, notchWidth: notchWidth)
        let entering = !requestedVisible
        let changedPosition = frame != shownFrame
        shownFrame = frame
        hiddenFrame = BufferMotion.hiddenFrame(position: position, shown: frame, screen: screen.frame, safeAreaTop: safeTop, notchWidth: notchWidth)
        requestedVisible = true
        root.setAccessibilityHidden(false)
        root.layer?.masksToBounds = position == .notch
        // Keep all controls below the camera, including their hit regions.
        // Source probes may refresh content during entrance. Preserve the live
        // presentation frame instead of snapping content to its final geometry.
        if motionTimer == nil || changedPosition {
            content.frame = CGRect(x: 0, y: 0, width: frame.width, height: BufferLayout.contentHeight)
        }
        title.frame = CGRect(x: 16, y: 80, width: frame.width - 60, height: 16)
        recoveryNotice.frame = CGRect(x: 16, y: 64, width: frame.width - 32, height: 13)
        recoveryNotice.isHidden = item?.deliveryUnconfirmed != true
        recoveryNotice.textColor = position == .notch ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
        closeButton.frame = BufferLayout.close(in: content.bounds)
        slot.frame = BufferLayout.slot(in: content.bounds)
        slotBorder.frame = slot.bounds
        slotBorder.path = CGPath(roundedRect: slot.bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: BufferLayout.slotCornerRadius, cornerHeight: BufferLayout.slotCornerRadius, transform: nil)
        icon.frame = CGRect(x: 10, y: 16, width: 16, height: 16)
        label.frame = CGRect(x: 33, y: 15, width: slot.bounds.width - 43, height: 17)
        label.stringValue = item.map { $0.payload.title.isEmpty ? $0.payload.text : $0.payload.title } ?? "Drop content here"
        icon.image = NSImage(systemSymbolName: item?.symbol ?? "tray.and.arrow.down", accessibilityDescription: item == nil ? "Buffer" : "Buffered content")
        let foreground: NSColor = position == .notch ? .white : .labelColor
        title.textColor = position == .notch ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
        label.textColor = item == nil ? foreground.withAlphaComponent(0.65) : foreground
        icon.contentTintColor = foreground
        closeButton.contentTintColor = position == .notch ? .white : .secondaryLabelColor
        refreshSlotAppearance()
        label.alphaValue = receiving ? 0 : 1; icon.alphaValue = receiving ? 0 : 1
        slot.setAccessibilityLabel(item == nil ? "Buffer slot. Drop content here." : "Buffered content. Drag out of the slot into an input field.")
        if entering || changedPosition {
            let start = panel.isVisible ? presentationFrame : hiddenFrame
            animatePresentation(from: start, to: frame, entering: true)
        } else if motionTimer == nil {
            applyPresentationFrame(frame)
            content.alphaValue = 1
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private func applyPresentationFrame(_ frame: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        presentationFrame = frame
        // Resizing a live top-edge window makes WindowServer composite its old
        // backing at intermediate sizes. Keep the Island window fixed; animate
        // only its clipped surface inside that transparent window.
        let windowFrame = position == .notch ? shownFrame : frame
        panel.setFrame(windowFrame, display: false)
        root.frame = CGRect(origin: .zero, size: windowFrame.size)
        surface?.frame = CGRect(x: frame.minX - windowFrame.minX, y: frame.minY - windowFrame.minY,
                                width: frame.width, height: frame.height)
        surface?.layer?.masksToBounds = position == .notch
        panel.alphaValue = position == .notch
            ? BufferMotion.surfaceOpacity(frameHeight: frame.height, shownHeight: shownFrame.height)
            : 1
        content.frame = CGRect(x: (frame.width - shownFrame.width) / 2, y: 0,
                               width: shownFrame.width, height: BufferLayout.contentHeight)
        root.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }
    private func hide() {
        panel.ignoresMouseEvents = true
        guard requestedVisible else { return }
        requestedVisible = false
        root.setAccessibilityHidden(true)
        animatePresentation(from: presentationFrame, to: hiddenFrame, entering: false)
    }
    private func animatePresentation(from start: CGRect, to end: CGRect, entering: Bool) {
        motionGeneration += 1
        let token = motionGeneration
        motionTimer?.invalidate(); motionTimer = nil
        let position = self.position ?? .notch
        let duration = CapturePreferences.animationDuration(position == .notch ? 0.36 : 0.24)
        guard duration > 0 else {
            applyPresentationFrame(end); content.alphaValue = entering ? 1 : 0
            if !entering { panel.orderOut(nil) }
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        let initialOpacity = entering && !panel.isVisible ? CGFloat(0) : content.alphaValue
        content.alphaValue = position == .notch ? initialOpacity : 1
        applyPresentationFrame(start)
        if entering { panel.orderFrontRegardless() }
        motionTimer = AnimationFrames(screen: screen) { [weak self] in
            guard let self, self.motionGeneration == token else { return false }
            let t = min(1, CGFloat((ProcessInfo.processInfo.systemUptime - started) / duration))
            let progress = BufferMotion.progress(t, position: position)
            let currentFrame = BufferMotion.frame(from: start, to: end, progress: progress)
            self.applyPresentationFrame(currentFrame)
            if position == .notch {
                let visibleHeight = currentFrame.height - max(0, self.shownFrame.height - BufferLayout.contentHeight)
                self.content.alphaValue = entering
                    ? BufferMotion.contentOpacity(visibleHeight: visibleHeight, fullHeight: BufferLayout.contentHeight)
                    : initialOpacity * max(0, 1 - t * 3)
            } else { self.content.alphaValue = 1 }
            if t == 1 {
                self.motionTimer = nil
                self.applyPresentationFrame(end)
                if !entering { self.panel.orderOut(nil) }
            }
            return t < 1
        }
    }
}

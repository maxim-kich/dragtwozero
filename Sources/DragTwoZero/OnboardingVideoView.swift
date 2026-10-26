import AppKit
import AVFoundation

/// One continuous, silent background across all onboarding pages.
final class OnboardingVideoView: NSView {
    private let player = AVQueuePlayer()
    private let videoLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var motionObserver: NSObjectProtocol?
    private var active = false
    private var visibilityObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        player.isMuted = true
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)
        if let url = Bundle.main.url(forResource: "OnboardingBackground", withExtension: "mp4") {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updatePlayback() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
        visibilityObservers.removeAll()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification,
                         NSApplication.didUnhideNotification] {
                let object: AnyObject? = name == NSApplication.didHideNotification || name == NSApplication.didUnhideNotification ? NSApp : window
                visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    self?.updatePlayback()
                })
            }
        }
        updatePlayback()
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    func setActive(_ active: Bool) {
        self.active = active
        updatePlayback()
    }
    private func updatePlayback() {
        if onboardingVideoShouldPlay(active: active, visible: window?.occlusionState.contains(.visible) == true,
                                     miniaturized: window?.isMiniaturized == true, hidden: NSApp.isHidden,
                                     reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
            player.play()
        } else {
            player.pause()
        }
    }
    deinit {
        player.pause()
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }
}

func onboardingVideoShouldPlay(active: Bool, visible: Bool, miniaturized: Bool, hidden: Bool, reduceMotion: Bool) -> Bool {
    active && visible && !miniaturized && !hidden && !reduceMotion
}

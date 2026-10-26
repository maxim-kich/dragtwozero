import AppKit
import QuartzCore

/// A short-lived main-run-loop clock. A screen link keeps ticking while an
/// exiting panel leaves the display, and matches ProMotion rather than 60 Hz.
final class AnimationFrames {
    private final class Target: NSObject {
        var frame: (() -> Void)?
        @objc func drawFrame() { frame?() }
    }
    private let target = Target()
    private var stop: (() -> Void)?

    init(screen: NSScreen?, frame: @escaping () -> Bool) {
        target.frame = { [weak self] in
            if !frame() { self?.invalidate() }
        }
        if #available(macOS 14.0, *), let screen {
            let link = screen.displayLink(target: target, selector: #selector(Target.drawFrame))
            let rate = Float(max(1, screen.maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, rate), maximum: rate, preferred: rate)
            stop = { link.invalidate() }
            link.add(to: .main, forMode: .common)
        } else {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak target] _ in target?.drawFrame() }
            stop = { timer.invalidate() }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func invalidate() {
        stop?(); stop = nil
        target.frame = nil
    }
    deinit { invalidate() }
}

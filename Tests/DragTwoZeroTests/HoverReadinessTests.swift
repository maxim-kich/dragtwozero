import AppKit
import XCTest
@testable import DragTwoZero

final class HoverReadinessTests: XCTestCase {
    func testAccessibilityResultDoesNotWaitForOptionalBackdropSampling() {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "liquidGlassEnabled")
        CapturePreferences.liquidGlassEnabled = true
        defer { defaults.set(saved, forKey: "liquidGlassEnabled") }
        let frame = CGRect(x: 100, y: 100, width: 200, height: 40)
        let candidate = CaptureCandidate(payload: .init(title: "Fixture", markdown: "Fixture"), frame: frame)
        let samplerStarted = expectation(description: "Sampler started")
        let lock = NSLock()
        var resume: CheckedContinuation<BackdropTone?, Never>?
        let app = AppDelegate(sourceLookupResolver: { _, _ in
            SourceCaptureLookup(candidate: candidate, allowsMarquee: true)
        }, backdropToneResolver: { _ in
            await withCheckedContinuation { continuation in
                lock.lock(); resume = continuation; lock.unlock()
                samplerStarted.fulfill()
            }
        })
        app.captureEnabled = true
        app.state.modifiers(held: true)
        app.pointer = CGPoint(x: 140, y: 120)
        app.probe(app.pointer)
        wait(for: [samplerStarted], timeout: 1)
        let deadline = Date().addingTimeInterval(0.5)
        while app.candidate == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(app.candidate?.payload.text, "Fixture", "Text detection must work even if screen sampling never completes")
        XCTAssertFalse(app.probing)
        // Repeated hover probes must not create additional screen requests
        // while the original sampler remains suspended.
        let repeatedUntil = Date().addingTimeInterval(0.25)
        while Date() < repeatedUntil {
            app.probe(app.pointer)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        app.cancel(); app.bufferOverlay.close(); app.overlay.close()
        lock.lock(); let continuation = resume; resume = nil; lock.unlock()
        continuation?.resume(returning: .dark)
    }
}

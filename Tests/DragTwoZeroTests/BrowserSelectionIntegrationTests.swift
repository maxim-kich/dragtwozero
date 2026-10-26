import AppKit
import XCTest
@testable import DragTwoZero

/// Opt in with a browser PID after opening scripts/fixtures/selected-text.html.
/// Reads only that synthetic fixture; never inspects an unrelated document.
final class BrowserSelectionIntegrationTests: XCTestCase {
    func testBrowserMarkerSelectionAcrossWrappedLines() throws {
        guard let value = ProcessInfo.processInfo.environment["DRAGTWOZERO_BROWSER_FIXTURE_PID"],
              let pid = Int32(value) else { throw XCTSkip("Requires the synthetic browser fixture") }
        let oldPreference = UserDefaults.standard.object(forKey: CapturePreferences.structureKey)
        defer { UserDefaults.standard.set(oldPreference, forKey: CapturePreferences.structureKey) }
        CapturePreferences.preserveStructure = true
        let app = AXUIElementCreateApplication(pid)
        var remaining = 400
        func find(_ node: AXUIElement, depth: Int = 0) -> AXUIElement? {
            remaining -= 1
            guard depth < 25, remaining > 0 else { return nil }
            let role = attribute(node, kAXRoleAttribute) as? String
            if role == "AXWebArea" { return node }
            for child in attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let window = try XCTUnwrap(windows.first {
            (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("Drag selection test") == true
        }, "Open the synthetic fixture and select its passage")
        // WebKit/Chromium can publish the host window before the remote web
        // accessibility subtree. Wait only for fixture readiness, not capture.
        var readyOwner: AXUIElement?
        for _ in 0..<10 {
            remaining = 400
            readyOwner = find(window)
            if readyOwner != nil { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        let owner = try XCTUnwrap(readyOwner)
        let candidate = try XCTUnwrap(AccessibleSelectedTextAdapter().candidate(at: owner))
        XCTAssertNotNil(candidate.selectedTextMarkerRange)
        XCTAssertEqual(candidate.payload.text, "Select this **passage** with [emoji 🐈](https://example.test/) and wrapped text across several line")
        let frames = try XCTUnwrap(candidate.textFrames)
        XCTAssertGreaterThan(frames.count, 1)
        XCTAssertGreaterThan(frames[0].minX, frames[1].minX)
        XCTAssertLessThan(frames[0].maxY, frames[1].maxY)
        let firstPoint = CGPoint(x: frames[0].midX, y: frames[0].midY)
        let hovered = try XCTUnwrap(AccessibleSelectedTextAdapter().candidate(at: owner, containing: firstPoint))
        XCTAssertTrue(candidate.matchesCurrentSource(hovered, at: firstPoint))
        func leaf(at node: AXUIElement, depth: Int = 0) -> AXUIElement? {
            guard depth < 25 else { return nil }
            if attribute(node, kAXRoleAttribute) as? String == "AXStaticText", bounds(node)?.contains(firstPoint) == true { return node }
            for child in attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = leaf(at: child, depth: depth + 1) { return found }
            }
            return nil
        }
        let hit = try XCTUnwrap(leaf(at: owner))
        let fromHit = try XCTUnwrap(AccessibleSelectedTextAdapter().candidate(at: hit, containing: firstPoint))
        XCTAssertTrue(candidate.matchesCurrentSource(fromHit, at: firstPoint))
        let fresh = try XCTUnwrap(AccessibleSelectedTextAdapter().candidate(at: owner))
        XCTAssertTrue(candidate.matchesRetainedSource(fresh))
        let unselected = CGPoint(x: frames[1].minX + 1, y: frames[0].midY)
        XCTAssertFalse(candidate.containsVisiblePoint(unselected))
    }
}

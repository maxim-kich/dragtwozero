import AppKit
import XCTest
@testable import DragTwoZero

/// Opt in with a browser PID after opening scripts/fixtures/selected-text.html.
/// Reads only that synthetic fixture; never inspects an unrelated document.
final class BrowserSelectionIntegrationTests: XCTestCase {
    func testSelectedTextHintReadsIdentityAndContentWithoutSourceOutlines() throws {
        guard let value = ProcessInfo.processInfo.environment["DRAGTWOZERO_BROWSER_FIXTURE_PID"], let pid = Int32(value) else { throw XCTSkip("Requires the synthetic browser fixture") }
        let app = AXUIElementCreateApplication(pid)
        let window = try XCTUnwrap((attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).first {
            (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("Drag selection test") == true
        })
        var remaining = 400
        func find(_ node: AXUIElement, depth: Int = 0) -> AXUIElement? {
            remaining -= 1; guard remaining > 0, depth < 30 else { return nil }
            if attribute(node, kAXRoleAttribute) as? String == "AXWebArea" { return node }
            for child in attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] { if let found = find(child, depth: depth + 1) { return found } }
            return nil
        }
        let owner = try XCTUnwrap(find(window)), previous = UserDefaults.standard.object(forKey: CapturePreferences.structureKey)
        defer { UserDefaults.standard.set(previous, forKey: CapturePreferences.structureKey) }
        CapturePreferences.preserveStructure = false
        let adapter = AccessibleSelectedTextAdapter()
        guard case .selected(let selected) = adapter.pickup(at: owner, origin: CGPoint(x: 10, y: 10)),
              case .selected(let current) = adapter.pickup(at: owner, origin: CGPoint(x: 500, y: 400)) else { return XCTFail("Readable selection must produce a hint payload") }
        XCTAssertEqual(selected.payload.text, "Select this passage with emoji 🐈 and wrapped text across several line")
        XCTAssertTrue(selected.visibleHighlightFrames.isEmpty)
        XCTAssertNotNil(selected.selectedTextMarkerRange)
        XCTAssertEqual(selected.selectedTextRange?.length, 70)
        XCTAssertTrue(selected.matchesRetainedSource(current), "The hint position is not source identity")
    }

    func testBrowserEqualBoundsKeepCanonicalBlockIdentity() throws {
        guard let value = ProcessInfo.processInfo.environment["DRAGTWOZERO_BROWSER_FIXTURE_PID"],
              let pid = Int32(value) else { throw XCTSkip("Requires the synthetic browser fixture") }
        let app = AXUIElementCreateApplication(pid)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let window = try XCTUnwrap(windows.first {
            (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("Drag selection test") == true
        })
        var remaining = 1_000
        func headings(_ node: AXUIElement, depth: Int = 0) -> [AXUIElement] {
            remaining -= 1
            guard remaining > 0, depth < 30 else { return [] }
            if attribute(node, kAXRoleAttribute) as? String == "AXHeading",
               let child = (attribute(node, kAXChildrenAttribute) as? [AXUIElement])?.first,
               (attribute(child, kAXValueAttribute) as? String)?.hasPrefix("Identity fixture ") == true { return [node] }
            return (attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { headings($0, depth: depth + 1) }
        }
        let blocks = headings(window)
        XCTAssertEqual(blocks.count, 3)
        let adapter = AccessibleTextBlockAdapter()
        var previous: CaptureCandidate?
        for block in blocks {
            let text = try XCTUnwrap((attribute(block, kAXChildrenAttribute) as? [AXUIElement])?.first)
            XCTAssertEqual(bounds(block), bounds(text), "Fixture must exercise ambiguous equal bounds")
            let expected = try XCTUnwrap(adapter.candidate(at: block))
            XCTAssertTrue(CaptureElementContext.sameElement(expected.anchor, block))
            for _ in 0..<8 {
                let current = try XCTUnwrap(adapter.candidate(at: text))
                XCTAssertTrue(CaptureElementContext.sameElement(current.anchor, block))
                XCTAssertTrue(expected.matchesRetainedSource(current))
            }
            if let previous { XCTAssertFalse(previous.matchesRetainedSource(expected)) }
            previous = expected
        }
    }

    func testBrowserHintKeepsSelectedFormattingAcrossWrappedLines() throws {
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
        // Inspect the provider independently of the capture formatter. Some
        // Chromium builds expose bold but omit URL metadata from selected
        // attributed text; blue/underlined text is not proof of a link URL.
        let selected = try XCTUnwrap(attribute(owner, "AXSelectedTextMarkerRange"))
        func readAttributed(_ name: String, _ input: CFTypeRef) -> NSAttributedString? {
            var raw: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(owner, name as CFString, input, &raw) == .success else { return nil }
            return raw as? NSAttributedString
        }
        let options = ["AXTextMarkerRange": selected, "AXSpellCheck": false] as CFDictionary
        let raw = try XCTUnwrap(readAttributed("AXAttributedStringForTextMarkerRangeWithOptions", options)
            ?? readAttributed("AXAttributedStringForTextMarkerRange", selected))
        let plain = "Select this passage with emoji 🐈 and wrapped text across several line"
        XCTAssertEqual(raw.string, plain)
        let passage = (plain as NSString).range(of: "passage")
        let attributes = raw.attributes(at: passage.location, effectiveRange: nil)
        let font = attributes[NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)] as? [String: Any]
        let explicitBold = font?["AXFontBold"] as? Bool
        let namedBold = (font?[kAXFontNameKey.takeUnretainedValue() as String] as? String)?.localizedCaseInsensitiveContains("bold") == true
        let nativeBold = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
        let expectedPassage = (explicitBold ?? (namedBold || nativeBold)) ? "**passage**" : "passage"
        let linkRange = (plain as NSString).range(of: "emoji 🐈")
        let linkAttributes = raw.attributes(at: linkRange.location, effectiveRange: nil)
        let rawLink = linkAttributes[.link] ?? linkAttributes[NSAttributedString.Key(kAXLinkTextAttribute.takeUnretainedValue() as String)]
        let linkValue = rawLink.flatMap { value -> CFTypeRef? in
            axElement(value as CFTypeRef).map { attribute($0, kAXURLAttribute) } ?? (value as CFTypeRef)
        }
        let linkURL = (linkValue as? URL) ?? (linkValue as? String).flatMap(URL.init(string:))
        let supportedURL = linkURL.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0:nil }
        if let supportedURL { XCTAssertEqual(supportedURL.absoluteString, "https://example.test/") }
        let expectedLink = supportedURL == nil ? "emoji 🐈" : "[emoji 🐈](https://example.test/)"
        let adapter = AccessibleSelectedTextAdapter()
        guard case .selected(let candidate) = adapter.pickup(at: owner, origin: CGPoint(x: 100, y: 100)) else {
            return XCTFail("Readable selected text must not depend on line geometry")
        }
        XCTAssertNotNil(candidate.selectedTextMarkerRange)
        XCTAssertEqual(candidate.payload.text, "Select this \(expectedPassage) with \(expectedLink) and wrapped text across several line")
        XCTAssertTrue(candidate.visibleHighlightFrames.isEmpty, "The new interaction must not outline selected lines")
        func leaf(at node: AXUIElement, depth: Int = 0) -> AXUIElement? {
            guard depth < 25 else { return nil }
            if attribute(node, kAXRoleAttribute) as? String == "AXStaticText",
               (attribute(node, kAXValueAttribute) as? String ?? "").hasPrefix("Unselected prefix.") { return node }
            for child in attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = leaf(at: child, depth: depth + 1) { return found }
            }
            return nil
        }
        let hit = try XCTUnwrap(leaf(at: owner))
        guard case .selected(let fromHit) = adapter.pickup(at: hit, origin: CGPoint(x: 300, y: 300)),
              case .selected(let fresh) = adapter.pickup(at: owner, origin: CGPoint(x: 500, y: 400)) else { return XCTFail("Repeated pickup must retain the same selected source") }
        XCTAssertTrue(candidate.matchesRetainedSource(fromHit))
        XCTAssertTrue(candidate.matchesRetainedSource(fresh))
    }
}

import AppKit
import XCTest
@testable import DragTwoZero

final class SelectedTextFormattingTests: XCTestCase {
    func testExplicitAXBoldWithoutFontNameIsPreservedOnlyWithStructure() {
        let key = NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)
        let text = NSAttributedString(string: " passage ", attributes: [key: ["AXFontBold": true, "AXFontSize": 24]])
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true), " **passage** ")
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: false), " passage ")
        let plain = NSAttributedString(string: "passage", attributes: [key: ["AXFontBold": false, "AXFontSize": 24]])
        XCTAssertEqual(SelectedTextFormatting.markdown(plain.string, attributed: plain, preserveStructure: true), "passage")
        let explicitRegular = NSAttributedString(string: "passage", attributes: [.font: NSFont.boldSystemFont(ofSize: 24), key: ["AXFontBold": false]])
        XCTAssertEqual(SelectedTextFormatting.markdown(explicitRegular.string, attributed: explicitRegular, preserveStructure: true), "passage")
    }

    func testAXSystemFontFaceDoesNotLoseBoldThroughFontSubstitution() {
        let text = NSAttributedString(string: "passage", attributes: [
            NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String): [
                kAXFontNameKey.takeUnretainedValue() as String: ".SFNS-Bold",
                kAXFontSizeKey.takeUnretainedValue() as String: 24]])
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true), "**passage**")
    }

    func testSelectedLinkSurvivesWithStructureOff() {
        let text = NSAttributedString(string: "selected link", attributes: [.link: URL(string: "https://example.test/path")!])
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: false), "[selected link](https://example.test/path)")
    }

    func testEmphasisRespectsStructurePreferenceAndPreservesSpaces() {
        let text = NSAttributedString(string: " bold 🐈 ", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true), " **bold 🐈** ")
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: false), " bold 🐈 ")
    }

    func testAXFontDictionaryAndAXLinkArePreserved() {
        let text = NSAttributedString(string: "part", attributes: [
            NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String): [
                kAXFontNameKey.takeUnretainedValue() as String: NSFont.boldSystemFont(ofSize: 16).fontName,
                kAXFontSizeKey.takeUnretainedValue() as String: 16],
            NSAttributedString.Key(kAXLinkTextAttribute.takeUnretainedValue() as String): "synthetic link owner"])
        let markdown = SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true, linkURL: { _ in URL(string: "https://example.test") })
        XCTAssertEqual(markdown, "[**part**](https://example.test)")
    }

    func testUnrelatedAttributesDoNotFragmentOneBoldRun() {
        let text = NSMutableAttributedString(string: "one two", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
        text.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 4, length: 3))
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true), "**one two**")
    }

    func testEnclosingAttributedParagraphCannotLeakUnselectedText() {
        let paragraph = NSAttributedString(string: "prefix selected suffix", attributes: [.link: "https://example.test"])
        XCTAssertEqual(SelectedTextFormatting.markdown("selected", attributed: paragraph, preserveStructure: true), "selected")
    }

    func testMissingAttributesAndUnsupportedURLsRemainLiteralText() {
        XCTAssertEqual(SelectedTextFormatting.markdown("[literal]", attributed: nil, preserveStructure: true), "\\[literal\\]")
        let text = NSAttributedString(string: "label", attributes: [.link: "javascript:alert(1)"])
        XCTAssertEqual(SelectedTextFormatting.markdown(text.string, attributed: text, preserveStructure: true), "label")
    }
}

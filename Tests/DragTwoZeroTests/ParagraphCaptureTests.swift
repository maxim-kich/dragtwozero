import XCTest
@testable import DragTwoZero

final class ParagraphCaptureTests: XCTestCase {
    private final class Node {
        var info: TextNodeDetails
        weak var parent: Node?
        var children: [Node]
        init(_ role: String, _ value: String? = nil, frame: CGRect = CGRect(x: 10, y: 20, width: 300, height: 20), url: URL? = nil, children: [Node] = []) {
            info = TextNodeDetails(role: role, value: value, url: url, frame: frame)
            self.children = children
            children.forEach { $0.parent = self }
        }
    }
    private func capture(_ node: Node, preserveStructure: Bool = false) -> CaptureCandidate? {
        TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 }, preserveStructure: preserveStructure).candidate(at: node)
    }

    func testEqualBoundsKeepTheSemanticBlockIdentityAcrossHits() throws {
        let text = Node("AXStaticText", "Same visible content")
        let heading = Node("AXHeading", children: [text])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        XCTAssertEqual(heading.info.frame, text.info.frame)
        for hit in [heading, text] {
            let result = try XCTUnwrap(reader.resolution(at: hit))
            XCTAssertTrue(result.block === heading)
            XCTAssertEqual(result.candidate.payload.text, "Same visible content")
            XCTAssertEqual(result.candidate.frame, heading.info.frame)
        }
    }

    func testEqualBoundsKeepTheInferredInlineGroupIdentity() throws {
        let before = Node("AXStaticText", "Read ")
        let link = Node("AXLink", "guide", url: URL(string: "https://example.test/guide"))
        let group = Node("AXGroup", children: [before, link])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        for hit in [group, before, link] {
            let result = try XCTUnwrap(reader.resolution(at: hit))
            XCTAssertTrue(result.block === group)
            XCTAssertEqual(result.candidate.payload.text, "Read [guide](https://example.test/guide)")
        }
    }

    func testIdenticalTextAndBoundsDoNotMergeDistinctSourceNodes() throws {
        let first = Node("AXHeading", children: [Node("AXStaticText", "Duplicate")])
        let second = Node("AXHeading", children: [Node("AXStaticText", "Duplicate")])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        let a = try XCTUnwrap(reader.resolution(at: first.children[0]))
        let b = try XCTUnwrap(reader.resolution(at: second.children[0]))
        XCTAssertEqual(a.candidate.payload.text, b.candidate.payload.text)
        XCTAssertEqual(a.candidate.frame, b.candidate.frame)
        XCTAssertTrue(a.block === first)
        XCTAssertTrue(b.block === second)
        XCTAssertFalse(a.block === b.block)
    }

    func testPointSearchKeepsTheIdentityOfTheAcceptedBlock() throws {
        let first = Node("AXParagraph", frame: CGRect(x: 10, y: 20, width: 300, height: 20), children: [Node("AXStaticText", "First")])
        let text = Node("AXStaticText", "Second", frame: CGRect(x: 10, y: 80, width: 300, height: 20))
        let second = Node("AXParagraph", frame: text.info.frame!, children: [text])
        let page = Node("AXWebArea", frame: CGRect(x: 0, y: 0, width: 800, height: 800), children: [first, second])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        let result = try XCTUnwrap(reader.resolution(at: page, containing: CGPoint(x: 40, y: 90)))
        XCTAssertTrue(result.block === second)
        XCTAssertEqual(result.candidate.payload.text, "Second")
        XCTAssertNil(reader.resolution(at: page, containing: CGPoint(x: 40, y: 60)))
        let editor = Node("AXTextArea", children: [second])
        XCTAssertNil(reader.resolution(at: text))
        XCTAssertNil(reader.resolution(at: editor, containing: CGPoint(x: 40, y: 90)))
    }
    func testSecureSubroleRejectsHitAndAncestorAndSkipsNestedContent() {
        let secret = Node("AXStaticText", "Synthetic private fixture")
        secret.info.subrole = "AXSecureTextField"
        XCTAssertNil(capture(secret))
        let child = Node("AXStaticText", "Synthetic child")
        let secureContainer = Node("AXGroup", children: [child])
        secureContainer.info.subrole = "AXSecureTextField"
        XCTAssertNil(capture(child))
        let paragraph = Node("AXParagraph", children: [Node("AXStaticText", "Visible"), secret])
        XCTAssertEqual(capture(paragraph)?.payload.text, "Visible")
    }
    func testLiteralHTMLRemainsLiteralInMarkdownTextAndLinkLabels() {
        XCTAssertEqual(TextFragment.text("<b>literal</b>").markdown, "\\<b\\>literal\\</b\\>")
        XCTAssertEqual(TextFragment.link("<tag>", URL(string: "https://example.com")!).markdown,
                       "[\\<tag\\>](https://example.com)")
    }
    func testStructureTogglePreservesHeadingLevelWithoutChangingDefault() {
        let text = Node("AXStaticText", "Overview")
        let heading = Node("AXHeading", children: [text])
        heading.info.headingLevel = 2
        XCTAssertEqual(capture(text)?.payload.text, "Overview")
        XCTAssertEqual(capture(text, preserveStructure: true)?.payload.text, "## Overview")
    }
    func testStructureRetainsInlineEmphasisAndLinks() {
        let strong = Node("AXStrong", children: [Node("AXStaticText", "important")])
        let emphasis = Node("AXEmphasis", children: [Node("AXStaticText", "note")])
        let link = Node("AXLink", "docs", url: URL(string: "https://example.com"))
        let paragraph = Node("AXParagraph", children: [strong, Node("AXStaticText", " "), emphasis, Node("AXStaticText", " "), link])
        XCTAssertEqual(capture(paragraph)?.payload.text, "important note [docs](https://example.com)")
        XCTAssertEqual(capture(paragraph, preserveStructure: true)?.payload.text, "**important** *note* [docs](https://example.com)")
    }
    func testNativeStyleGroupSubrolesPreserveStrongEmphasisAndLinkedLabels() {
        // Real Chromium macOS AX shape: semantic formatting is an AXGroup
        // subrole, with the actual characters in a child AXStaticText node.
        let strong = Node("AXGroup", children: [Node("AXStaticText", "bold")])
        strong.info.subrole = "AXStrongStyleGroup"
        let emphasis = Node("AXGroup", children: [Node("AXStaticText", "italic")])
        emphasis.info.subrole = "AXEmphasisStyleGroup"
        let linkStrong = Node("AXGroup", children: [Node("AXStaticText", "guide")])
        linkStrong.info.subrole = "AXStrongStyleGroup"
        let link = Node("AXLink", url: URL(string: "https://example.test/guide"), children: [linkStrong])
        let paragraph = Node("AXParagraph", children: [Node("AXStaticText", "ALPHA "), strong,
            Node("AXStaticText", " and "), emphasis, Node("AXStaticText", " with "), link])
        XCTAssertEqual(capture(paragraph, preserveStructure: true)?.payload.text,
                       "ALPHA **bold** and *italic* with [**guide**](https://example.test/guide)")
        XCTAssertEqual(capture(paragraph, preserveStructure: false)?.payload.text,
                       "ALPHA bold and italic with [guide](https://example.test/guide)")
    }

    func testNestedNativeStrongAndEmphasisDoNotLoseEitherSemanticStyle() {
        let emphasis = Node("AXGroup", children: [Node("AXStaticText", "both")])
        emphasis.info.subrole = "AXEmphasisStyleGroup"
        let strong = Node("AXGroup", children: [emphasis])
        strong.info.subrole = "AXStrongStyleGroup"
        let paragraph = Node("AXParagraph", children: [strong])
        XCTAssertEqual(capture(paragraph, preserveStructure: true)?.payload.text, "***both***")
    }

    func testListMarkersAndParagraphFallback() {
        let item = Node("AXListItem", children: [Node("AXStaticText", "• First item")])
        XCTAssertEqual(capture(item, preserveStructure: true)?.payload.text, "- First item")
        let numbered = Node("AXListItem", children: [Node("AXStaticText", "3. Third item")])
        XCTAssertEqual(capture(numbered, preserveStructure: true)?.payload.text, "3. Third item")
        let paragraph = Node("AXParagraph", children: [Node("AXStaticText", "Ordinary text")])
        XCTAssertEqual(capture(paragraph, preserveStructure: true)?.payload.text, "Ordinary text")
    }
    func testStructuredHeadingKeepsLinkedLabelAndEmphasis() {
        let bold = Node("AXStrong", children: [Node("AXStaticText", "Guide")])
        let link = Node("AXLink", url: URL(string: "https://example.com/guide"), children: [bold])
        let heading = Node("AXHeading", children: [link])
        heading.info.headingLevel = 2
        XCTAssertEqual(capture(heading, preserveStructure: true)?.payload.text, "## [**Guide**](https://example.com/guide)")
    }
    func testStructuredCaptureKeepsURLsExposedOnTextRuns() {
        let run = Node("AXStaticText", "Contact us", url: URL(string: "mailto:hello@example.com"))
        let paragraph = Node("AXParagraph", children: [run])
        XCTAssertEqual(capture(paragraph, preserveStructure: true)?.payload.text, "[Contact us](mailto:hello@example.com)")
        XCTAssertEqual(capture(paragraph)?.payload.text, "Contact us")
    }
    func testPageHitBetweenLinesResolvesWholeParagraphBox() {
        let first = Node("AXStaticText", "First line. ", frame: CGRect(x: 10, y: 20, width: 180, height: 18))
        let second = Node("AXStaticText", "Second line.", frame: CGRect(x: 10, y: 46, width: 120, height: 18))
        let paragraph = Node("AXGroup", frame: CGRect(x: 10, y: 20, width: 300, height: 44), children: [first, second])
        let next = Node("AXParagraph", frame: CGRect(x: 10, y: 90, width: 300, height: 20), children: [Node("AXStaticText", "Next paragraph.")])
        let page = Node("AXWebArea", frame: CGRect(x: 0, y: 0, width: 800, height: 800), children: [paragraph, next])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        // Both line leading and empty space after a short line belong to the paragraph.
        for point in [CGPoint(x: 50, y: 42), CGPoint(x: 290, y: 52)] {
            XCTAssertEqual(reader.candidate(at: page, containing: point)?.frame, paragraph.info.frame)
            XCTAssertEqual(reader.candidate(at: page, containing: point)?.payload.text, "First line. Second line.")
        }
        XCTAssertNil(reader.candidate(at: page, containing: CGPoint(x: 50, y: 77)))
        XCTAssertEqual(reader.candidate(at: page, containing: CGPoint(x: 50, y: 100))?.payload.text, "Next paragraph.")
    }
    func testRectangleSearchDoesNotCaptureEditableContent() {
        let paragraph = Node("AXParagraph", children: [Node("AXStaticText", "Draft")])
        let editor = Node("AXTextArea", children: [paragraph])
        let page = Node("AXWebArea", children: [editor])
        let reader = TextBlockReader<Node>(details: { $0.info }, parent: { $0.parent }, children: { $0.children }, equal: { $0 === $1 })
        XCTAssertNil(reader.candidate(at: page, containing: CGPoint(x: 30, y: 30)))
    }
    func testEveryInlineHitCapturesTheSameWholeParagraph() {
        let before = Node("AXStaticText", "Read ")
        let label = Node("AXStaticText", "the guide")
        let link = Node("AXLink", url: URL(string: "https://example.com/guide"), children: [label])
        let formatted = Node("AXGroup", children: [Node("AXStaticText", " then "), Node("AXStaticText", "continue.")])
        let paragraph = Node("AXParagraph", frame: CGRect(x: 10, y: 20, width: 600, height: 48), children: [before, link, formatted])
        for hit in [before, link, label, formatted, formatted.children[1]] {
            XCTAssertEqual(capture(hit)?.payload.text, "Read [the guide](https://example.com/guide) then continue.")
            XCTAssertEqual(capture(hit)?.frame, paragraph.info.frame)
        }
    }
    func testInlineOnlyGenericGroupCapturesAcrossLinkAndFormatting() {
        let first = Node("AXStaticText", "Read ")
        let link = Node("AXLink", "guide", url: URL(string: "https://example.com"))
        let last = Node("AXGroup", children: [Node("AXStaticText", " carefully.")])
        let group = Node("AXGroup", children: [first, link, last])
        XCTAssertEqual(capture(link)?.payload.text, "Read [guide](https://example.com) carefully.")
        XCTAssertEqual(capture(first)?.frame, group.info.frame)
    }
    func testInlineImageIsSkippedWithoutDiscardingSupportedTextAndLinks() {
        let first = Node("AXStaticText", "Read ", frame: CGRect(x: 10, y: 20, width: 40, height: 20))
        let image = Node("AXImage", "Unsupported image", frame: CGRect(x: 50, y: 20, width: 60, height: 20))
        let link = Node("AXLink", "guide", frame: CGRect(x: 110, y: 20, width: 50, height: 20), url: URL(string: "https://example.test/guide"))
        let last = Node("AXStaticText", " then continue.", frame: CGRect(x: 160, y: 20, width: 130, height: 20))
        let group = Node("AXGroup", frame: CGRect(x: 10, y: 20, width: 280, height: 20), children: [first, image, link, last])
        for hit in [first, image, link, last] {
            XCTAssertEqual(capture(hit)?.payload.text, "Read [guide](https://example.test/guide) then continue.")
            XCTAssertEqual(capture(hit)?.frame, group.info.frame)
        }
        let unsupported = Node("AXGroup", children: [Node("AXImage", "Not text")])
        XCTAssertNil(capture(unsupported.children[0]))
        XCTAssertNil(capture(unsupported))
    }

    func testSeparateParagraphsNeverMergeAcrossPageContainer() {
        let firstText = Node("AXStaticText", "First.")
        let secondText = Node("AXStaticText", "Second.")
        let first = Node("AXParagraph", children: [firstText])
        let second = Node("AXParagraph", children: [secondText])
        let page = Node("AXWebArea", children: [first, second])
        XCTAssertEqual(capture(firstText)?.payload.text, "First.")
        XCTAssertEqual(capture(secondText)?.payload.text, "Second.")
        XCTAssertNil(capture(page))
    }
    func testStandaloneLinkFallsThroughToLinkAdapter() {
        let label = Node("AXStaticText", "Standalone")
        let link = Node("AXLink", url: URL(string: "https://example.com"), children: [label])
        let wrapper = Node("AXGroup", children: [link])
        XCTAssertNil(capture(label)); XCTAssertNil(capture(link))
        XCTAssertEqual(wrapper.children.count, 1)
    }
    func testGenericGroupsWithParagraphGapsDoNotMerge() {
        let first = Node("AXStaticText", "One.", frame: CGRect(x: 0, y: 0, width: 200, height: 20))
        let second = Node("AXStaticText", "Two.", frame: CGRect(x: 0, y: 60, width: 200, height: 20))
        let wrapper = Node("AXGroup", children: [first, second])
        XCTAssertEqual(capture(first)?.payload.text, "One.")
        XCTAssertEqual(wrapper.children.count, 2)
    }
    func testEditableParagraphsNeverCapture() {
        let text = Node("AXStaticText", "Draft text")
        let paragraph = Node("AXParagraph", children: [text])
        let editor = Node("AXTextArea", children: [paragraph])
        XCTAssertNil(capture(text)); XCTAssertNil(capture(editor))
    }
    func testWrappedParagraphWithSuperscriptDoesNotSplitAtLineLeading() {
        let first = Node("AXStaticText", "Read ", frame: CGRect(x: 0, y: 0, width: 40, height: 19))
        let link = Node("AXLink", "guide", frame: CGRect(x: 40, y: 0, width: 50, height: 19), url: URL(string: "https://example.com"))
        let nextLine = Node("AXStaticText", " in m", frame: CGRect(x: 0, y: 26, width: 40, height: 19))
        let superscript = Node("AXGroup", children: [Node("AXStaticText", "2", frame: CGRect(x: 40, y: 22, width: 8, height: 9))])
        let last = Node("AXStaticText", " and continue.", frame: CGRect(x: 0, y: 52, width: 160, height: 19))
        let paragraph = Node("AXGroup", frame: CGRect(x: 0, y: 0, width: 200, height: 71), children: [first, link, nextLine, superscript, last])
        for hit in [first, link, superscript.children[0], last] {
            XCTAssertEqual(capture(hit)?.payload.text, "Read [guide](https://example.com) in m2 and continue.")
            XCTAssertEqual(capture(hit)?.frame, paragraph.info.frame)
        }
    }
    func testStandaloneInlineTextBoxCanBeCaptured() {
        let text = Node("AXInlineTextBox", "Visible inline text")
        XCTAssertEqual(capture(text)?.payload.text, "Visible inline text")
    }
    func testInlineTextBoxCapturesCompleteStaticTextParent() {
        let first = Node("AXInlineTextBox", "First line", frame: CGRect(x: 10, y: 20, width: 80, height: 18))
        let second = Node("AXInlineTextBox", "Second line", frame: CGRect(x: 10, y: 40, width: 90, height: 18))
        let text = Node("AXStaticText", "First line Second line", frame: CGRect(x: 10, y: 20, width: 150, height: 38), children: [first, second])
        XCTAssertEqual(capture(first)?.payload.text, "First line Second line")
        XCTAssertEqual(capture(second)?.frame, text.info.frame)
    }
    func testInlineTextBoxInsideStandaloneLinkStillUsesLinkAdapter() {
        let text = Node("AXInlineTextBox", "Linked label")
        let link = Node("AXLink", url: URL(string: "https://example.com"), children: [text])
        XCTAssertNil(capture(text))
        XCTAssertNil(capture(link))
    }
    func testDeepFormattingDoesNotSplitTheParagraph() {
        let text = Node("AXStaticText", "Nested text")
        var nested = text
        for _ in 0..<12 { nested = Node("AXGroup", children: [nested]) }
        let paragraph = Node("AXParagraph", children: [nested, Node("AXStaticText", " continues.")])
        XCTAssertEqual(capture(text)?.payload.text, "Nested text continues.")
        XCTAssertNotNil(paragraph.info.frame)
    }
}

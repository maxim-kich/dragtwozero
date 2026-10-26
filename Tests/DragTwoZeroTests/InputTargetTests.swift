import XCTest
@testable import DragTwoZero

final class InputTargetTests: XCTestCase {
    func testTextCaretSupportsTextInputsWithoutEditableFlag() {
        for role in ["AXTextArea", "AXTextField", "AXComboBox"] {
            XCTAssertTrue(InputTarget.acceptsEditor(role: role, subrole: nil, enabled: true,
                editable: nil, valueWritable: false, selectionWritable: true, hasCaret: true))
            XCTAssertFalse(InputTarget.acceptsEditor(role: role, subrole: nil, enabled: true,
                editable: false, valueWritable: false, selectionWritable: true, hasCaret: true))
        }
    }
    func testSelectablePageContainersAreNotDropTargets() {
        for role in ["AXGroup", "AXWebArea", "AXLayoutArea", "AXLayoutItem"] {
            XCTAssertFalse(InputTarget.acceptsEditor(role: role, subrole: nil, enabled: true,
                editable: nil, valueWritable: false, selectionWritable: true, hasCaret: true))
            XCTAssertTrue(InputTarget.acceptsEditor(role: role, subrole: nil, enabled: true,
                editable: true, valueWritable: false, selectionWritable: true, hasCaret: true))
        }
    }
    func testCellsRequireWritableContentNotJustSelection() {
        XCTAssertTrue(InputTarget.acceptsCell(role: "AXCell", enabled: true, editable: nil, valueWritable: true))
        XCTAssertFalse(InputTarget.acceptsCell(role: "AXCell", enabled: true, editable: nil, valueWritable: false))
        XCTAssertFalse(InputTarget.acceptsCell(role: "AXCell", enabled: false, editable: true, valueWritable: true))
        XCTAssertFalse(InputTarget.acceptsCell(role: "AXCell", enabled: true, editable: false, valueWritable: true))
        XCTAssertFalse(InputTarget.acceptsCell(role: "AXRow", enabled: true, editable: nil, valueWritable: true))
    }
    func testStandardInputsDoNotRequireComposerLabels() {
        for role in ["AXTextArea", "AXTextField", "AXComboBox"] {
            XCTAssertTrue(InputTarget.acceptsEditor(role: role, subrole: nil, enabled: true,
                editable: nil, valueWritable: true, selectionWritable: true))
        }
    }
    func testEditableDocumentsCanPasteWithoutSettableValue() {
        XCTAssertTrue(InputTarget.acceptsEditor(role: "AXTextArea", subrole: nil, enabled: true,
            editable: true, valueWritable: false, selectionWritable: true))
        XCTAssertTrue(InputTarget.acceptsEditor(role: "AXWebArea", subrole: nil, enabled: true,
            editable: true, valueWritable: false, selectionWritable: true))
        XCTAssertFalse(InputTarget.acceptsEditor(role: "AXWebArea", subrole: nil, enabled: true,
            editable: nil, valueWritable: false, selectionWritable: true))
    }
    func testSecureDisabledAndReadOnlyEditorsAreRejected() {
        XCTAssertFalse(InputTarget.acceptsEditor(role: "AXTextField", subrole: "AXSecureTextField", enabled: true,
            editable: true, valueWritable: true, selectionWritable: true))
        XCTAssertFalse(InputTarget.acceptsEditor(role: "AXTextArea", subrole: nil, enabled: false,
            editable: true, valueWritable: true, selectionWritable: true))
        XCTAssertFalse(InputTarget.acceptsEditor(role: "AXTextArea", subrole: nil, enabled: true,
            editable: false, valueWritable: true, selectionWritable: true))
        XCTAssertFalse(InputTarget.acceptsEditor(role: "AXStaticText", subrole: nil, enabled: true,
            editable: nil, valueWritable: false, selectionWritable: false))
    }
}

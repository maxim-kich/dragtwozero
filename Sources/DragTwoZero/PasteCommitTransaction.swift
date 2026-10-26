import Foundation

/// Unlike selectedInsertionRange, this retains selection length for safety checks.
struct EditorInsertionState: Equatable {
    let location: Int
    let length: Int
    let value: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
            && lhs.value.utf16.elementsEqual(rhs.value.utf16)
    }

    var isCollapsed: Bool { location >= 0 && length == 0 }

    var hasValidRange: Bool {
        let units = Array(value.utf16)
        guard location >= 0, length >= 0, location <= units.count, length <= units.count - location else { return false }
        func boundary(_ offset: Int) -> Bool {
            offset == 0 || offset == units.count || !(0xD800...0xDBFF).contains(units[offset - 1]) || !(0xDC00...0xDFFF).contains(units[offset])
        }
        return boundary(location) && boundary(location + length)
    }

    /// Exact authorized edit, including replacement of an intentionally selected range.
    func replacingSelection(with text: String) -> String? {
        guard hasValidRange else { return nil }
        let units = Array(value.utf16)
        return String(decoding: Array(units[..<location]) + Array(text.utf16) + Array(units[(location + length)...]), as: UTF16.self)
    }

    func confirmsInsertion(of text: String, observed: String) -> Bool {
        guard let result = replacingSelection(with: text),
              !result.utf16.elementsEqual(value.utf16) else { return false }
        return result.utf16.elementsEqual(observed.utf16)
    }
}

/// The production commit boundary, also exercised with deterministic editor/clipboard fakes.
/// Preparation may synchronously ask another process for promised clipboard data.
enum PasteCommitTransaction {
    static func commit<Preparation, Ownership>(
        expected: EditorInsertionState,
        readState: () -> EditorInsertionState?,
        prepareClipboard: () -> Preparation,
        installClipboard: (Preparation) -> Ownership?,
        restoreClipboard: (Ownership) -> Void,
        ownsClipboard: (Ownership) -> Bool,
        postPaste: () -> Bool,
        diagnostic: (StaticString) -> Void = { _ in }
    ) -> Ownership? {
        guard expected.hasValidRange, readState() == expected else { diagnostic("commit-initial-state-rejected"); return nil }
        let prepared = prepareClipboard()
        guard readState() == expected else { diagnostic("commit-state-changed-during-preparation"); return nil }
        guard let ownership = installClipboard(prepared) else { diagnostic("commit-clipboard-install-rejected"); return nil }
        // Installing the payload can also cross process boundaries. Do not trust
        // the selection that was read before that operation.
        guard readState() == expected else {
            restoreClipboard(ownership)
            diagnostic("commit-state-changed-after-install")
            return nil
        }
        guard ownsClipboard(ownership) else {
            restoreClipboard(ownership)
            diagnostic("commit-clipboard-ownership-lost")
            return nil
        }
        guard postPaste() else {
            restoreClipboard(ownership)
            diagnostic("commit-cancelled-before-post")
            return nil
        }
        return ownership
    }
}

import Combine
import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var document: ManuscriptDocument

    private let documentStore: DocumentStore
    private var cancellables = Set<AnyCancellable>()
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let historyLimit = 100

    init(documentStore: DocumentStore) {
        self.documentStore = documentStore
        self.document = documentStore.document

        documentStore.$document
            .sink { [weak self] document in
                guard let self else { return }
                if self.document.id != document.id {
                    self.undoStack.removeAll()
                    self.redoStack.removeAll()
                }
                self.document = document
            }
            .store(in: &cancellables)
    }

    var body: String {
        get { document.body }
        set { updateBody(newValue) }
    }

    var title: String {
        get { document.title }
        set { documentStore.updateTitle(newValue) }
    }

    var characterCount: Int {
        ManuscriptMarkupParser.characterCountBody(from: document.body).count
    }

    var pageCount: Int {
        ManuscriptPaginator.pages(for: document).count
    }

    func insert(_ text: String, replacing selectedRange: NSRange, cursorOffsetFromEnd: Int = 0) -> NSRange {
        let currentBody = document.body
        let nsBody = currentBody as NSString
        let safeRange = clampedRange(selectedRange, in: nsBody)
        let updatedBody = nsBody.replacingCharacters(in: safeRange, with: text)
        updateBody(updatedBody)

        let insertedLength = (text as NSString).length
        let cursorLocation = safeRange.location + max(insertedLength - cursorOffsetFromEnd, 0)
        return NSRange(location: cursorLocation, length: 0)
    }

    func updateBody(_ newBody: String) {
        commitBody(newBody, recordsUndo: true)
    }

    func undo(currentRange: NSRange) -> NSRange? {
        guard let previousBody = undoStack.popLast() else { return nil }
        redoStack.append(document.body)
        commitBody(previousBody, recordsUndo: false)
        return clampedInsertionRange(currentRange, in: previousBody)
    }

    func redo(currentRange: NSRange) -> NSRange? {
        guard let nextBody = redoStack.popLast() else { return nil }
        undoStack.append(document.body)
        commitBody(nextBody, recordsUndo: false)
        return clampedInsertionRange(currentRange, in: nextBody)
    }

    func replace(in range: NSRange, with text: String) -> NSRange {
        insert(text, replacing: range)
    }

    func replaceAll(searchText: String, replacementText: String) -> Int {
        guard !searchText.isEmpty else { return 0 }
        let matches = document.body.components(separatedBy: searchText).count - 1
        guard matches > 0 else { return 0 }

        updateBody(document.body.replacingOccurrences(of: searchText, with: replacementText))
        return matches
    }

    func rangeOfNextMatch(searchText: String, after selectedRange: NSRange) -> NSRange? {
        guard !searchText.isEmpty else { return nil }

        let body = document.body as NSString
        let searchLength = body.length
        guard searchLength > 0 else { return nil }

        let startLocation = min(selectedRange.location + selectedRange.length, searchLength)
        let tailRange = NSRange(location: startLocation, length: searchLength - startLocation)
        let tailMatch = body.range(of: searchText, options: [], range: tailRange)
        if tailMatch.location != NSNotFound {
            return tailMatch
        }

        let headRange = NSRange(location: 0, length: startLocation)
        let headMatch = body.range(of: searchText, options: [], range: headRange)
        return headMatch.location == NSNotFound ? nil : headMatch
    }

    func rangeOfPreviousMatch(searchText: String, before selectedRange: NSRange) -> NSRange? {
        guard !searchText.isEmpty else { return nil }

        let body = document.body as NSString
        let searchLength = body.length
        guard searchLength > 0 else { return nil }

        let startLocation = min(max(selectedRange.location, 0), searchLength)
        let headRange = NSRange(location: 0, length: startLocation)
        let headMatch = body.range(of: searchText, options: .backwards, range: headRange)
        if headMatch.location != NSNotFound {
            return headMatch
        }

        let tailRange = NSRange(location: startLocation, length: searchLength - startLocation)
        let tailMatch = body.range(of: searchText, options: .backwards, range: tailRange)
        return tailMatch.location == NSNotFound ? nil : tailMatch
    }

    func selectedText(in selectedRange: NSRange) -> String {
        let nsBody = document.body as NSString
        let safeRange = clampedRange(selectedRange, in: nsBody)
        return nsBody.substring(with: safeRange)
    }

    private func clampedRange(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        let remainingLength = text.length - location
        let length = min(max(range.length, 0), remainingLength)
        return NSRange(location: location, length: length)
    }

    private func commitBody(_ newBody: String, recordsUndo: Bool) {
        guard newBody != document.body else { return }

        if recordsUndo {
            undoStack.append(document.body)
            if undoStack.count > historyLimit {
                undoStack.removeFirst(undoStack.count - historyLimit)
            }
            redoStack.removeAll()
        }

        documentStore.updateBody(newBody)
    }

    private func clampedInsertionRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        return NSRange(location: min(max(range.location, 0), length), length: 0)
    }
}

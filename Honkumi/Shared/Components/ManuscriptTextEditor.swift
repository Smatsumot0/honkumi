import SwiftUI
import UIKit

enum ManuscriptTextEditorCommand: Equatable {
    case undo(UUID)
    case redo(UUID)
}

struct ManuscriptTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var requestedSelectedRange: NSRange?
    @Binding var isEditing: Bool
    @Binding var command: ManuscriptTextEditorCommand?
    let fontName: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = editorFont()
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.font = editorFont()

        if let command {
            context.coordinator.perform(command, in: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }

        if let requestedSelectedRange {
            if textView.text != text {
                textView.text = text
            }

            let safeRange = clampedRange(requestedSelectedRange, in: textView.text)
            context.coordinator.applySelection(safeRange, to: textView)
            DispatchQueue.main.async {
                self.selectedRange = safeRange
                self.requestedSelectedRange = nil
            }
            return
        }

        if textView.markedTextRange != nil {
            return
        }

        if !textView.isFirstResponder, textView.text != text {
            textView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let remainingLength = length - location
        let selectedLength = min(max(range.length, 0), remainingLength)
        return NSRange(location: location, length: selectedLength)
    }

    private func editorFont() -> UIFont {
        let preferredFont = UIFont.preferredFont(forTextStyle: .body)
        return UIFont(name: fontName, size: preferredFont.pointSize) ?? preferredFont
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: ManuscriptTextEditor
        private var isApplyingSelection = false

        init(_ parent: ManuscriptTextEditor) {
            self.parent = parent
        }

        func applySelection(_ range: NSRange, to textView: UITextView) {
            isApplyingSelection = true
            textView.selectedRange = range
            textView.becomeFirstResponder()
            isApplyingSelection = false
        }

        func perform(_ command: ManuscriptTextEditorCommand, in textView: UITextView) {
            switch command {
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            }

            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingSelection else { return }
            guard textView.markedTextRange == nil else { return }
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isEditing = false
        }
    }
}

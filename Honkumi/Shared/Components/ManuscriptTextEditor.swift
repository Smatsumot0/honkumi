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
    @Binding var contentOffset: CGPoint
    @Binding var isEditing: Bool
    @Binding var command: ManuscriptTextEditorCommand?
    let selectedFontId: String
    let isAdditionalFontPackUnlocked: Bool
    let formatSettings: FormatSettings
    let formatOptions: FormatOptions

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = editorFont()
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .secondarySystemBackground
        textView.textColor = .label
        textView.tintColor = .label
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.font = editorFont()
        textView.backgroundColor = .secondarySystemBackground
        textView.textColor = .label
        textView.tintColor = .label

        if !context.coordinator.didRestoreInitialOffset {
            context.coordinator.didRestoreInitialOffset = true
            DispatchQueue.main.async {
                guard !context.coordinator.isUserScrolling(in: textView) else { return }
                textView.setContentOffset(contentOffset, animated: false)
            }
        }

        if let command {
            context.coordinator.perform(command, in: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }

        if let requestedSelectedRange {
            let preservedOffset = textView.contentOffset
            if textView.text != text {
                textView.text = text
            }

            let safeRange = clampedRange(requestedSelectedRange, in: textView.text)
            context.coordinator.applySelection(safeRange, to: textView)
            textView.setContentOffset(preservedOffset, animated: false)
            DispatchQueue.main.async {
                self.selectedRange = safeRange
                self.requestedSelectedRange = nil
                self.contentOffset = preservedOffset
            }
            return
        }

        if textView.markedTextRange != nil {
            return
        }

        if !textView.isFirstResponder, textView.text != text {
            let preservedOffset = textView.contentOffset
            textView.text = text
            textView.setContentOffset(preservedOffset, animated: false)
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
        return AppFontCatalog.uiFont(
            selectedFontId: selectedFontId,
            size: preferredFont.pointSize,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ManuscriptTextEditor
        private var isApplyingSelection = false
        private var isApplyingTextChange = false
        var didRestoreInitialOffset = false

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
            let preservedOffset = textView.contentOffset
            switch command {
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            }

            textView.setContentOffset(preservedOffset, animated: false)
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
            parent.contentOffset = preservedOffset
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingTextChange else { return }
            guard textView.markedTextRange == nil else { return }
            applyFormatIfNeeded(to: textView)
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
            saveContentOffset(from: textView)
            guard textView.markedTextRange == nil else { return }
            applyFormatIfNeeded(to: textView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            saveContentOffset(from: scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                saveContentOffset(from: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            saveContentOffset(from: scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            saveContentOffset(from: scrollView)
        }

        func isUserScrolling(in scrollView: UIScrollView) -> Bool {
            scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        }

        private func saveContentOffset(from scrollView: UIScrollView) {
            let offset = scrollView.contentOffset
            if abs(parent.contentOffset.x - offset.x) > 0.5
                || abs(parent.contentOffset.y - offset.y) > 0.5 {
                parent.contentOffset = offset
            }
        }

        private func applyFormatIfNeeded(to textView: UITextView) {
            let originalText = textView.text ?? ""
            let originalSelection = textView.selectedRange
            let originalOffset = textView.contentOffset
            let formattedText = ManuscriptFormatter.formatManuscriptText(
                originalText,
                settings: parent.formatSettings,
                options: parent.formatOptions
            )

            if formattedText != originalText {
                let adjustedSelection = adjustedRange(
                    originalSelection,
                    from: originalText,
                    to: formattedText
                )
                isApplyingTextChange = true
                textView.text = formattedText
                textView.selectedRange = adjustedSelection
                textView.setContentOffset(originalOffset, animated: false)
                isApplyingTextChange = false
                parent.text = formattedText
                parent.selectedRange = adjustedSelection
                parent.contentOffset = originalOffset
            } else {
                parent.text = originalText
                parent.selectedRange = originalSelection
                parent.contentOffset = originalOffset
            }
        }

        private func adjustedRange(_ range: NSRange, from originalText: String, to formattedText: String) -> NSRange {
            let newLocation = adjustedLocation(range.location, from: originalText, to: formattedText)
            let originalEnd = range.location + range.length
            let adjustedEnd = adjustedLocation(originalEnd, from: originalText, to: formattedText)
            let formattedLength = (formattedText as NSString).length
            let safeLocation = min(max(newLocation, 0), formattedLength)
            let safeEnd = min(max(adjustedEnd, safeLocation), formattedLength)
            return NSRange(location: safeLocation, length: safeEnd - safeLocation)
        }

        private func adjustedLocation(_ location: Int, from originalText: String, to formattedText: String) -> Int {
            let original = originalText as NSString
            let formatted = formattedText as NSString
            let originalLength = original.length
            let formattedLength = formatted.length
            let safeLocation = min(max(location, 0), originalLength)
            let commonPrefixLength = commonPrefixLength(original: original, formatted: formatted)
            let commonSuffixLength = commonSuffixLength(
                original: original,
                formatted: formatted,
                commonPrefixLength: commonPrefixLength
            )
            let originalChangedEnd = originalLength - commonSuffixLength
            let formattedChangedEnd = formattedLength - commonSuffixLength

            if safeLocation <= commonPrefixLength {
                return safeLocation
            }

            if safeLocation >= originalChangedEnd {
                return safeLocation + (formattedChangedEnd - originalChangedEnd)
            }

            return formattedChangedEnd
        }

        private func commonPrefixLength(original: NSString, formatted: NSString) -> Int {
            let maxLength = min(original.length, formatted.length)
            var index = 0
            while index < maxLength,
                  original.substring(with: NSRange(location: index, length: 1)) == formatted.substring(with: NSRange(location: index, length: 1)) {
                index += 1
            }
            return index
        }

        private func commonSuffixLength(
            original: NSString,
            formatted: NSString,
            commonPrefixLength: Int
        ) -> Int {
            let originalLength = original.length
            let formattedLength = formatted.length
            var length = 0

            while originalLength - length > commonPrefixLength,
                  formattedLength - length > commonPrefixLength {
                let originalCharacter = original.substring(
                    with: NSRange(location: originalLength - length - 1, length: 1)
                )
                let formattedCharacter = formatted.substring(
                    with: NSRange(location: formattedLength - length - 1, length: 1)
                )
                guard originalCharacter == formattedCharacter else { break }
                length += 1
            }

            return length
        }
    }
}

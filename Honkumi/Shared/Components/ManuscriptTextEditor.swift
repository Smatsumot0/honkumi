import SwiftUI
import UIKit

enum ManuscriptTextEditorCommand: Equatable {
    case undo(UUID)
    case redo(UUID)
}

enum ManuscriptTextEditorScrollDirection: Equatable {
    case up
    case down
}

private enum ManuscriptTextEditorLayout {
    static let textContainerInsets = UIEdgeInsets(top: 8, left: 6, bottom: 20, right: 6)
    static let scrollContentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)
}

private final class ManuscriptUIKitTextView: UITextView {
    var suppressesAutomaticSelectionScrolling = false
    var allowsAutomaticSelectionScrolling = false

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !shouldSuppressAutomaticSelectionScrolling else { return }
        super.scrollRangeToVisible(range)
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        guard !shouldSuppressAutomaticSelectionScrolling else { return }
        super.scrollRectToVisible(rect, animated: animated)
    }

    private var shouldSuppressAutomaticSelectionScrolling: Bool {
        suppressesAutomaticSelectionScrolling && !allowsAutomaticSelectionScrolling
    }
}

struct ManuscriptTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var requestedSelectedRange: NSRange?
    @Binding var contentOffset: CGPoint
    @Binding var isEditing: Bool
    @Binding var command: ManuscriptTextEditorCommand?
    let editorFontId: String
    let editorFontSize: CGFloat
    let isAdditionalFontPackUnlocked: Bool
    let formatSettings: FormatSettings
    let formatOptions: FormatOptions
    let onScrollDirectionChange: (ManuscriptTextEditorScrollDirection) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = ManuscriptUIKitTextView()
        textView.delegate = context.coordinator
        context.coordinator.attach(to: textView)
        applyEditorStyle(to: textView, coordinator: context.coordinator)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .secondarySystemBackground
        textView.textColor = .label
        textView.tintColor = .label
        textView.keyboardDismissMode = .interactive
        applyEditorScrollInsets(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: textView)
        applyEditorStyle(to: textView, coordinator: context.coordinator)
        textView.backgroundColor = .secondarySystemBackground
        textView.textColor = .label
        textView.tintColor = .label
        applyEditorScrollInsets(to: textView)

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
            if textView.text != text {
                textView.text = text
                context.coordinator.needsFullStyleRefresh = true
                applyEditorStyle(to: textView, coordinator: context.coordinator)
            }

            let safeRange = clampedRange(requestedSelectedRange, in: textView.text)
            context.coordinator.applySelection(safeRange, to: textView)
            context.coordinator.scrollSelectionToVisible(safeRange, in: textView)
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
            let preservedOffset = textView.contentOffset
            textView.text = text
            context.coordinator.needsFullStyleRefresh = true
            applyEditorStyle(to: textView, coordinator: context.coordinator)
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
        let sizeRange = EditorSettings.editorFontSizeRange
        let fontSize = min(max(editorFontSize, sizeRange.lowerBound), sizeRange.upperBound)
        return AppFontCatalog.uiFont(
            selectedFontId: editorFontId,
            size: fontSize,
            isAdditionalFontPackUnlocked: isAdditionalFontPackUnlocked
        )
    }

    private func applyEditorStyle(to textView: UITextView, coordinator: Coordinator) {
        let font = editorFont()
        let styleSignature = "\(font.fontName)-\(font.pointSize)"

        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: UIColor.label
        ]

        guard coordinator.needsFullStyleRefresh || coordinator.appliedStyleSignature != styleSignature else { return }
        coordinator.needsFullStyleRefresh = false
        coordinator.appliedStyleSignature = styleSignature
    }

    private func applyEditorScrollInsets(to textView: UITextView) {
        textView.textContainerInset = ManuscriptTextEditorLayout.textContainerInsets
        textView.contentInset = ManuscriptTextEditorLayout.scrollContentInsets
        textView.verticalScrollIndicatorInsets = ManuscriptTextEditorLayout.scrollContentInsets
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ManuscriptTextEditor
        private var isApplyingSelection = false
        private var isApplyingTextChange = false
        private weak var observedTextView: UITextView?
        private var keyboardTransitionOffset: CGPoint?
        private var keyboardTransitionWorkItem: DispatchWorkItem?
        private var lastScrollOffsetY: CGFloat?
        private var lastReportedScrollDirection: ManuscriptTextEditorScrollDirection?
        private var suppressesSelectionScrollingUntil: Date?
        var didRestoreInitialOffset = false
        var needsFullStyleRefresh = true
        var appliedStyleSignature: String?

        init(_ parent: ManuscriptTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            keyboardTransitionWorkItem?.cancel()
        }

        func attach(to textView: UITextView) {
            guard observedTextView !== textView else { return }
            if observedTextView != nil {
                NotificationCenter.default.removeObserver(self)
            }

            observedTextView = textView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        func applySelection(_ range: NSRange, to textView: UITextView) {
            isApplyingSelection = true
            allowingAutomaticSelectionScrolling(in: textView) {
                textView.selectedRange = range
                textView.becomeFirstResponder()
            }
            isApplyingSelection = false
        }

        func scrollSelectionToVisible(_ range: NSRange, in textView: UITextView) {
            if range.location <= 0 {
                let topOffset = CGPoint(x: 0, y: -textView.adjustedContentInset.top)
                textView.setContentOffset(topOffset, animated: false)
                saveContentOffset(from: textView)
                return
            }

            guard !textView.text.isEmpty else {
                saveContentOffset(from: textView)
                return
            }

            allowingAutomaticSelectionScrolling(in: textView) {
                revealSelectionIfNeeded(range, in: textView, savesOffset: true)
            }
            saveContentOffset(from: textView)
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
            commitTextChange(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingSelection else { return }
            guard textView.markedTextRange == nil else { return }
            guard !isUserScrolling(in: textView), !isSuppressingAutomaticSelectionScrolling else { return }
            let range = textView.selectedRange
            if parent.selectedRange != range {
                parent.selectedRange = range
            }
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
            lastScrollOffsetY = scrollView.contentOffset.y
            lastReportedScrollDirection = nil
            beginSuppressingAutomaticSelectionScrolling(in: scrollView)
            keyboardTransitionOffset = nil
            keyboardTransitionWorkItem?.cancel()
            keyboardTransitionWorkItem = nil
            saveContentOffset(from: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling(in: scrollView) else { return }
            let offsetY = scrollView.contentOffset.y
            defer {
                lastScrollOffsetY = offsetY
            }

            guard let previousOffsetY = lastScrollOffsetY else { return }
            let delta = offsetY - previousOffsetY
            guard abs(delta) > 4 else { return }

            if offsetY <= -scrollView.adjustedContentInset.top + 8 {
                reportScrollDirection(.up)
            } else if isNearBottom(scrollView), delta < 0 {
                return
            } else {
                reportScrollDirection(delta > 0 ? .down : .up)
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                saveContentOffset(from: scrollView)
                endSuppressingAutomaticSelectionScrolling(in: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            saveContentOffset(from: scrollView)
            endSuppressingAutomaticSelectionScrolling(in: scrollView)
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

        private func reportScrollDirection(_ direction: ManuscriptTextEditorScrollDirection) {
            guard lastReportedScrollDirection != direction else { return }
            lastReportedScrollDirection = direction
            parent.onScrollDirectionChange(direction)
        }

        private func isNearBottom(_ scrollView: UIScrollView) -> Bool {
            let inset = scrollView.adjustedContentInset
            let minY = -inset.top
            let maxY = max(scrollView.contentSize.height - scrollView.bounds.height + inset.bottom, minY)
            return scrollView.contentOffset.y >= maxY - 12
        }

        private var isSuppressingAutomaticSelectionScrolling: Bool {
            guard let suppressesSelectionScrollingUntil else { return false }
            return suppressesSelectionScrollingUntil == .distantFuture || Date() < suppressesSelectionScrollingUntil
        }

        private func beginSuppressingAutomaticSelectionScrolling(in scrollView: UIScrollView) {
            suppressesSelectionScrollingUntil = .distantFuture
            (scrollView as? ManuscriptUIKitTextView)?.suppressesAutomaticSelectionScrolling = true
        }

        private func endSuppressingAutomaticSelectionScrolling(in scrollView: UIScrollView) {
            let suppressionEnd = Date().addingTimeInterval(0.8)
            suppressesSelectionScrollingUntil = suppressionEnd

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) { [weak self, weak scrollView] in
                guard let self,
                      let scrollView,
                      self.suppressesSelectionScrollingUntil == suppressionEnd,
                      !self.isUserScrolling(in: scrollView) else { return }
                self.suppressesSelectionScrollingUntil = nil
                (scrollView as? ManuscriptUIKitTextView)?.suppressesAutomaticSelectionScrolling = false
            }
        }

        private func allowingAutomaticSelectionScrolling(in textView: UITextView, _ updates: () -> Void) {
            guard let textView = textView as? ManuscriptUIKitTextView else {
                updates()
                return
            }

            let previousValue = textView.allowsAutomaticSelectionScrolling
            textView.allowsAutomaticSelectionScrolling = true
            updates()
            textView.allowsAutomaticSelectionScrolling = previousValue
        }

        private func commitTextChange(from textView: UITextView) {
            let originalText = textView.text ?? ""
            let originalSelection = textView.selectedRange
            parent.text = originalText
            if parent.selectedRange != originalSelection {
                parent.selectedRange = originalSelection
            }
        }

        private func applyFormatIfNeeded(to textView: UITextView) {
            let originalText = textView.text ?? ""
            let originalSelection = textView.selectedRange
            let originalOffset = textView.contentOffset
            guard parent.formatSettings.validated.enableAutoFormat else {
                commitTextChange(from: textView)
                return
            }
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
            } else {
                commitTextChange(from: textView)
            }
        }

        @objc private func keyboardWillChangeFrame(_ notification: Notification) {
            guard let textView = observedTextView,
                  textView.isFirstResponder,
                  !isUserScrolling(in: textView),
                  !isSuppressingAutomaticSelectionScrolling else { return }

            keyboardTransitionOffset = textView.contentOffset
            keyboardTransitionWorkItem?.cancel()

            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                .doubleValue ?? 0.25
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.restoreOffsetAfterKeyboardTransition(in: textView)
            }
            keyboardTransitionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03, execute: workItem)
        }

        private func restoreOffsetAfterKeyboardTransition(in textView: UITextView) {
            defer {
                keyboardTransitionOffset = nil
                keyboardTransitionWorkItem = nil
            }

            guard !isUserScrolling(in: textView), !isSuppressingAutomaticSelectionScrolling else { return }
            let preservedOffset = keyboardTransitionOffset ?? textView.contentOffset
            let clampedOffset = clampedContentOffset(preservedOffset, in: textView)
            textView.setContentOffset(clampedOffset, animated: false)

            saveContentOffset(from: textView)
        }

        private func revealSelectionIfNeeded(
            _ range: NSRange,
            in textView: UITextView,
            savesOffset: Bool
        ) {
            guard !isSelectionVisible(range, in: textView, verticalMargin: 20),
                  let caretRect = caretRect(for: range, in: textView) else {
                if savesOffset {
                    saveContentOffset(from: textView)
                }
                return
            }

            let visibleRect = visibleContentRect(in: textView, verticalMargin: 20)
            var targetOffset = textView.contentOffset
            if caretRect.minY < visibleRect.minY {
                targetOffset.y -= visibleRect.minY - caretRect.minY
            } else if caretRect.maxY > visibleRect.maxY {
                targetOffset.y += caretRect.maxY - visibleRect.maxY
            }

            textView.setContentOffset(clampedContentOffset(targetOffset, in: textView), animated: false)
            if savesOffset {
                saveContentOffset(from: textView)
            }
        }

        private func isSelectionVisible(
            _ range: NSRange,
            in textView: UITextView,
            verticalMargin: CGFloat
        ) -> Bool {
            guard let caretRect = caretRect(for: range, in: textView) else { return true }
            return visibleContentRect(in: textView, verticalMargin: verticalMargin).contains(caretRect)
        }

        private func caretRect(for range: NSRange, in textView: UITextView) -> CGRect? {
            let textLength = ((textView.text ?? "") as NSString).length
            let location = min(max(range.location, 0), textLength)
            guard let position = textView.position(
                from: textView.beginningOfDocument,
                offset: location
            ) else { return nil }
            return textView.caretRect(for: position)
        }

        private func visibleContentRect(in textView: UITextView, verticalMargin: CGFloat) -> CGRect {
            let inset = textView.adjustedContentInset
            return CGRect(
                x: textView.contentOffset.x + inset.left,
                y: textView.contentOffset.y + inset.top + verticalMargin,
                width: max(textView.bounds.width - inset.left - inset.right, 1),
                height: max(textView.bounds.height - inset.top - inset.bottom - verticalMargin * 2, 1)
            )
        }

        private func clampedContentOffset(_ offset: CGPoint, in textView: UITextView) -> CGPoint {
            let inset = textView.adjustedContentInset
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(textView.contentSize.width - textView.bounds.width + inset.right, minX)
            let maxY = max(textView.contentSize.height - textView.bounds.height + inset.bottom, minY)
            return CGPoint(
                x: min(max(offset.x, minX), maxX),
                y: min(max(offset.y, minY), maxY)
            )
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

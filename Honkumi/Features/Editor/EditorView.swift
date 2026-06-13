import SwiftUI

struct EditorView: View {
    @StateObject var viewModel: EditorViewModel
    @Binding var scrollOffset: CGPoint
    @Binding var isEditorChromeVisible: Bool
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var requestedSelectedRange: NSRange?
    @State private var isBodyEditorActive = false
    @State private var editorCommand: ManuscriptTextEditorCommand?
    @State private var showsSearchReplaceSheet = false
    @State private var searchText = ""
    @State private var replacementText = ""
    @State private var searchMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            if isEditorChromeVisible {
                chapterNavigationToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showsSearchReplaceSheet {
                searchReplacePanel
            }

            ManuscriptTextEditor(
                text: Binding(
                    get: { viewModel.body },
                    set: { viewModel.body = $0 }
                ),
                selectedRange: $selectedRange,
                requestedSelectedRange: $requestedSelectedRange,
                contentOffset: $scrollOffset,
                isEditing: $isBodyEditorActive,
                command: $editorCommand,
                editorFontId: viewModel.document.settings.editorFontId,
                editorFontSize: viewModel.document.settings.editorFontSize,
                isAdditionalFontPackUnlocked: viewModel.isAdditionalFontPackUnlocked,
                formatSettings: viewModel.formatSettings,
                formatOptions: viewModel.formatOptions,
                onScrollDirectionChange: handleScrollDirection
            )
            .padding(8)
            .overlay(alignment: .topLeading) {
                if viewModel.body.isEmpty && !isBodyEditorActive {
                    Text("本文を入力")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            insertionToolbar
        }
        .animation(.easeInOut(duration: 0.18), value: isEditorChromeVisible)
    }

    private var editorCounts: some View {
        HStack(spacing: 10) {
            Text("\(viewModel.characterCount)文字")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(viewModel.pageCount)ページ")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var chapterNavigationToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Button {
                        moveToTop()
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .accessibilityLabel("一番上まで移動")
                    .disabled(selectedRange.location == 0)

                    Button {
                        moveUp()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityLabel("上に移動")
                    .disabled(!viewModel.canMoveUp(from: selectedRange))

                    Button {
                        moveDown()
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .accessibilityLabel("下に移動")
                    .disabled(!viewModel.canMoveDown(from: selectedRange))

                    Button {
                        moveToBottom()
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .accessibilityLabel("一番下に移動")
                    .disabled(!viewModel.canMoveDown(from: selectedRange))
                }
                .buttonStyle(EditorToolButtonStyle())

                editorCounts

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
    }

    private var insertionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button {
                    applyUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("取り消す")

                Button {
                    applyRedo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .accessibilityLabel("やり直す")

                insertionButton("「」", cursorOffsetFromEnd: 1)
                insertionButton("（）", cursorOffsetFromEnd: 1)
                insertionButton("\"\"", cursorOffsetFromEnd: 1)
                insertionButton("…", inserts: "……")
                insertionButton("〜")
                insertionButton("─", inserts: "──")
                insertionButton("ー", inserts: "ーー")
                Button {
                    insertText("# ")
                } label: {
                    ChapterTitleBannerIcon()
                        .frame(width: 16, height: 13)
                }
                .accessibilityLabel("章タイトル")
                insertionIconButton(
                    systemImage: "arrow.turn.down.left",
                    accessibilityLabel: "改ページ",
                    inserts: "\n\(ManuscriptMarkupParser.pageBreakTag)\n"
                )
                insertionTextButton(
                    title: "＿",
                    accessibilityLabel: "全角スペース",
                    inserts: "　"
                )
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showsSearchReplaceSheet.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("検索と置換")
            }
            .buttonStyle(EditorToolButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
    }

    private func insertionButton(_ title: String, inserts text: String? = nil, cursorOffsetFromEnd: Int = 0) -> some View {
        Button(title) {
            insertText(text ?? title, cursorOffsetFromEnd: cursorOffsetFromEnd)
        }
    }

    private func insertionTextButton(
        title: String,
        accessibilityLabel: String,
        inserts text: String,
        cursorOffsetFromEnd: Int = 0
    ) -> some View {
        Button(title) {
            insertText(text, cursorOffsetFromEnd: cursorOffsetFromEnd)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func insertionIconButton(
        systemImage: String,
        accessibilityLabel: String,
        inserts text: String,
        cursorOffsetFromEnd: Int = 0
    ) -> some View {
        Button {
            insertText(text, cursorOffsetFromEnd: cursorOffsetFromEnd)
        } label: {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var searchReplacePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("検索／置換")
                    .font(.headline)
                Spacer()
                Button {
                    showsSearchReplaceSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("閉じる")
            }

            HStack(spacing: 8) {
                TextField("検索文字列", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                TextField("置換後文字列", text: $replacementText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button("検索") {
                    findNext()
                }
                .disabled(searchText.isEmpty)

                Button("前へ") {
                    findPrevious()
                }
                .disabled(searchText.isEmpty)

                Button("次へ") {
                    findNext()
                }
                .disabled(searchText.isEmpty)

                Button("置換") {
                    replaceCurrentOrNext()
                }
                .disabled(searchText.isEmpty)

                Button("全て置換") {
                    replaceAll()
                }
                .disabled(searchText.isEmpty)
            }
            .buttonStyle(.bordered)

            if !searchMessage.isEmpty {
                Text(searchMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func insertText(_ text: String, cursorOffsetFromEnd: Int = 0) {
        let insertedRange = viewModel.insert(
            text,
            replacing: selectedRange,
            cursorOffsetFromEnd: cursorOffsetFromEnd
        )
        selectedRange = insertedRange
        requestedSelectedRange = insertedRange
    }

    private func handleScrollDirection(_ direction: ManuscriptTextEditorScrollDirection) {
        if !isEditorChromeVisible {
            isEditorChromeVisible = true
        }
    }

    private func moveUp() {
        guard let range = viewModel.rangeForMovingUp(from: selectedRange) else { return }
        selectedRange = range
        requestedSelectedRange = range
    }

    private func moveToTop() {
        let range = viewModel.rangeForMovingToTop()
        selectedRange = range
        requestedSelectedRange = range
    }

    private func moveDown() {
        guard let range = viewModel.rangeForMovingDown(from: selectedRange) else { return }
        selectedRange = range
        requestedSelectedRange = range
    }

    private func moveToBottom() {
        let range = viewModel.rangeForMovingToBottom()
        selectedRange = range
        requestedSelectedRange = range
    }

    private func findNext() {
        guard let range = viewModel.rangeOfNextMatch(searchText: searchText, after: selectedRange) else {
            searchMessage = "見つかりません"
            return
        }

        selectedRange = range
        requestedSelectedRange = range
        searchMessage = "見つかりました"
    }

    private func findPrevious() {
        guard let range = viewModel.rangeOfPreviousMatch(searchText: searchText, before: selectedRange) else {
            searchMessage = "見つかりません"
            return
        }

        selectedRange = range
        requestedSelectedRange = range
        searchMessage = "見つかりました"
    }

    private func replaceCurrentOrNext() {
        let replacementRange: NSRange

        if viewModel.selectedText(in: selectedRange) == searchText {
            replacementRange = selectedRange
        } else if let nextRange = viewModel.rangeOfNextMatch(searchText: searchText, after: selectedRange) {
            replacementRange = nextRange
        } else {
            searchMessage = "見つかりません"
            return
        }

        let range = viewModel.replace(in: replacementRange, with: replacementText)
        selectedRange = range
        requestedSelectedRange = range
        searchMessage = "置換しました"

        if let nextRange = viewModel.rangeOfNextMatch(searchText: searchText, after: range) {
            DispatchQueue.main.async {
                selectedRange = nextRange
                requestedSelectedRange = nextRange
            }
        }
    }

    private func replaceAll() {
        let count = viewModel.replaceAll(searchText: searchText, replacementText: replacementText)
        if count > 0 {
            let range = NSRange(location: 0, length: 0)
            selectedRange = range
            requestedSelectedRange = range
        }
        searchMessage = "\(count)件置換しました"
    }

    private func applyUndo() {
        guard let range = viewModel.undo(currentRange: selectedRange) else { return }
        selectedRange = range
        requestedSelectedRange = range
    }

    private func applyRedo() {
        guard let range = viewModel.redo(currentRange: selectedRange) else { return }
        selectedRange = range
        requestedSelectedRange = range
    }
}

private struct EditorToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.42))
            .frame(minWidth: 34, minHeight: 34)
            .padding(.horizontal, 1)
            .contentShape(Rectangle())
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                }
            }
    }
}

private struct ChapterTitleBannerIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let rect = geometry.frame(in: .local)
            let width = rect.width
            let height = rect.height

            Path { path in
                path.move(to: CGPoint(x: rect.minX + width * 0.08, y: rect.minY + height * 0.16))
                path.addLine(to: CGPoint(x: rect.minX + width * 0.78, y: rect.minY + height * 0.16))
                path.addLine(to: CGPoint(x: rect.minX + width * 0.96, y: rect.minY + height * 0.50))
                path.addLine(to: CGPoint(x: rect.minX + width * 0.78, y: rect.minY + height * 0.84))
                path.addLine(to: CGPoint(x: rect.minX + width * 0.08, y: rect.minY + height * 0.84))
                path.addLine(to: CGPoint(x: rect.minX + width * 0.24, y: rect.minY + height * 0.50))
                path.closeSubpath()
            }
            .stroke(
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

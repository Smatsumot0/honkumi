import SwiftUI

struct EditorView: View {
    @StateObject var viewModel: EditorViewModel
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var requestedSelectedRange: NSRange?
    @State private var isBodyEditorActive = false
    @State private var editorCommand: ManuscriptTextEditorCommand?
    @State private var showsChapterTitleAlert = false
    @State private var chapterTitle = ""
    @State private var showsSearchReplaceSheet = false
    @State private var searchText = ""
    @State private var replacementText = ""
    @State private var searchMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ManuscriptTextEditor(text: Binding(
                get: { viewModel.body },
                set: { viewModel.body = $0 }
            ), selectedRange: $selectedRange, requestedSelectedRange: $requestedSelectedRange, isEditing: $isBodyEditorActive, command: $editorCommand, fontName: viewModel.document.settings.japaneseFont.postScriptName)
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

            HStack {
                Text("\(viewModel.characterCount)文字")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.pageCount)ページ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            insertionToolbar
        }
        .alert("章タイトルを挿入", isPresented: $showsChapterTitleAlert) {
            TextField("章タイトル", text: $chapterTitle)
            Button("挿入") {
                insertChapterTitle()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showsSearchReplaceSheet) {
            searchReplaceSheet
        }
    }

    private var insertionToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                insertionButton("「」", cursorOffsetFromEnd: 1)
                insertionButton("（）", cursorOffsetFromEnd: 1)
                insertionButton("……")
                insertionButton("──")
            }

            HStack(spacing: 8) {
                Button("章タイトル") {
                    chapterTitle = ""
                    showsChapterTitleAlert = true
                }
                .buttonStyle(.bordered)
                insertionButton("目次", inserts: "\n\(ManuscriptMarkupParser.tableOfContentsTag)\n")
                insertionButton("改ページ", inserts: "\n\(ManuscriptMarkupParser.pageBreakTag)\n")
                insertionButton("全角スペース", inserts: "　")
            }

            HStack(spacing: 8) {
                Button {
                    applyUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("取り消す")
                .buttonStyle(.bordered)

                Button {
                    applyRedo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .accessibilityLabel("やり直す")
                .buttonStyle(.bordered)

                Button {
                    showsSearchReplaceSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("検索と置換")
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func insertionButton(_ title: String, inserts text: String? = nil, cursorOffsetFromEnd: Int = 0) -> some View {
        Button(title) {
            let insertedRange = viewModel.insert(
                text ?? title,
                replacing: selectedRange,
                cursorOffsetFromEnd: cursorOffsetFromEnd
            )
            selectedRange = insertedRange
            requestedSelectedRange = insertedRange
        }
        .buttonStyle(.bordered)
    }

    private var searchReplaceSheet: some View {
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

            TextField("検索文字列", text: $searchText)
                .textFieldStyle(.roundedBorder)

            TextField("置換後文字列", text: $replacementText)
                .textFieldStyle(.roundedBorder)

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
        .padding()
        .presentationDetents([.height(searchMessage.isEmpty ? 210 : 235)])
        .presentationDragIndicator(.visible)
    }

    private func insertChapterTitle() {
        let trimmedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let insertedRange = viewModel.insert(
            "\n\(ManuscriptMarkupParser.chapterTag(for: trimmedTitle))\n",
            replacing: selectedRange
        )
        selectedRange = insertedRange
        requestedSelectedRange = insertedRange
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

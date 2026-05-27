import SwiftUI

struct WorkListView: View {
    @ObservedObject var documentStore: DocumentStore
    let onSelectWork: () -> Void
    let onShowDefaultSettings: () -> Void
    let onShowDefaultColophonSettings: () -> Void

    @State private var categoryName = ""
    @State private var workTitle = ""
    @State private var newWorkCategoryId: UUID?
    @State private var editingCategory: WorkCategory?
    @State private var editingWork: ManuscriptDocument?
    @State private var movingWork: ManuscriptDocument?
    @State private var targetedDropCategoryId: UUID?
    @State private var showsNewCategoryAlert = false
    @State private var showsNewWorkAlert = false
    @State private var showsRenameCategoryAlert = false
    @State private var showsRenameWorkAlert = false

    var body: some View {
        List {
            ForEach(documentStore.categories) { category in
                categorySection(category)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    onShowDefaultSettings()
                } label: {
                    Label("デフォルト設定", systemImage: "gearshape")
                }

                Button {
                    onShowDefaultColophonSettings()
                } label: {
                    Label("発行者情報", systemImage: "person.crop.rectangle")
                }

                Button {
                    workTitle = ""
                    newWorkCategoryId = nil
                    showsNewWorkAlert = true
                } label: {
                    Label("作品を追加", systemImage: "doc.badge.plus")
                }

                Button {
                    categoryName = ""
                    showsNewCategoryAlert = true
                } label: {
                    Label("カテゴリを追加", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("カテゴリを作成", isPresented: $showsNewCategoryAlert) {
            TextField("カテゴリ名", text: $categoryName)
            Button("作成") {
                documentStore.createCategory(name: categoryName)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("作品を作成", isPresented: $showsNewWorkAlert) {
            TextField("タイトル", text: $workTitle)
            Button("作成") {
                documentStore.createWork(title: workTitle, in: newWorkCategoryId)
                newWorkCategoryId = nil
                onSelectWork()
            }
            Button("キャンセル", role: .cancel) {
                newWorkCategoryId = nil
            }
        }
        .alert("カテゴリ名を変更", isPresented: $showsRenameCategoryAlert) {
            TextField("カテゴリ名", text: $categoryName)
            Button("変更") {
                if let editingCategory {
                    documentStore.renameCategory(id: editingCategory.id, name: categoryName)
                }
                editingCategory = nil
            }
            Button("キャンセル", role: .cancel) {
                editingCategory = nil
            }
        }
        .alert("作品タイトルを変更", isPresented: $showsRenameWorkAlert) {
            TextField("タイトル", text: $workTitle)
            Button("変更") {
                if let editingWork {
                    documentStore.updateTitle(for: editingWork.id, title: workTitle)
                }
                editingWork = nil
            }
            Button("キャンセル", role: .cancel) {
                editingWork = nil
            }
        }
        .confirmationDialog("移動先カテゴリ", isPresented: Binding(
            get: { movingWork != nil },
            set: { isPresented in
                if !isPresented {
                    movingWork = nil
                }
            }
        )) {
            if let work = movingWork {
                ForEach(documentStore.categories) { category in
                    Button(category.name) {
                        documentStore.moveWork(id: work.id, to: category.id)
                        movingWork = nil
                    }
                }
            }
        }
    }

    private func categorySection(_ category: WorkCategory) -> some View {
        Section {
            let works = documentStore.works(in: category)

            if works.isEmpty {
                Text("作品はありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(works) { work in
                    workButton(work)
                }
            }
        } header: {
            categoryHeader(category)
        }
        .dropDestination(
            for: String.self,
            action: { items, _ in
                moveDraggedWorks(items, to: category.id)
            },
            isTargeted: { isTargeted in
                targetedDropCategoryId = isTargeted ? category.id : nil
            }
        )
    }

    private func categoryHeader(_ category: WorkCategory) -> some View {
        HStack {
            Text(category.name)
            Spacer()
            Button {
                workTitle = ""
                newWorkCategoryId = category.id
                showsNewWorkAlert = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            if category.id != WorkCategory.uncategorizedId {
                Button("カテゴリ名を変更") {
                    editingCategory = category
                    categoryName = category.name
                    showsRenameCategoryAlert = true
                }

                Button("カテゴリを削除", role: .destructive) {
                    documentStore.deleteCategory(id: category.id)
                }
            }
        }
        .background {
            if targetedDropCategoryId == category.id {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
    }

    private func workButton(_ work: ManuscriptDocument) -> some View {
        Button {
            documentStore.selectWork(id: work.id)
            onSelectWork()
        } label: {
            WorkRow(work: work, isActive: work.id == documentStore.document.id)
        }
        .draggable(work.id.uuidString)
        .contextMenu {
            Button("タイトルを変更") {
                editingWork = work
                workTitle = work.title
                showsRenameWorkAlert = true
            }

            Button("移動") {
                movingWork = work
            }

            Button("削除", role: .destructive) {
                documentStore.deleteWork(id: work.id)
            }
        }
    }

    private func moveDraggedWorks(_ items: [String], to categoryId: UUID) -> Bool {
        var didMoveWork = false

        for item in items {
            guard let workId = UUID(uuidString: item),
                  let work = documentStore.works.first(where: { $0.id == workId }),
                  work.categoryId != categoryId else {
                continue
            }

            documentStore.moveWork(id: workId, to: categoryId)
            didMoveWork = true
        }

        targetedDropCategoryId = nil
        return didMoveWork
    }
}

private struct WorkRow: View {
    let work: ManuscriptDocument
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .foregroundStyle(.primary)
                Text(Self.updatedDateFormatter.string(from: work.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private static let updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}

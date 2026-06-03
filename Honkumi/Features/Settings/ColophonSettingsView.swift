import PhotosUI
import SwiftUI
import UIKit

struct ColophonSettingsView: View {
    enum Mode {
        case userDefault
        case activeWork
    }

    @StateObject var viewModel: SettingsViewModel
    let mode: Mode

    @State private var selectedCircleImageItem: PhotosPickerItem?
    @State private var showsPaidFeatureAlert = false

    var body: some View {
        Form {
            switch mode {
            case .userDefault:
                defaultColophonSection
            case .activeWork:
                activeWorkColophonSection
            }
        }
        .onChange(of: selectedCircleImageItem) { _, item in
            loadImageData(from: item, keyPath: \.circleImageData)
        }
        .alert("有料機能です", isPresented: $showsPaidFeatureAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private var defaultColophonSection: some View {
        Section("奥付") {
            TextField("作者名", text: colophonBinding(\.authorName))
            TextField("サークル名", text: colophonBinding(\.circleName))
            circleLogoControls

            TextField("HP", text: colophonBinding(\.websiteURL))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("x（旧Twitter）", text: colophonBinding(\.xURL))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("pixiv", text: colophonBinding(\.pixivURL))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("連絡先", text: colophonBinding(\.contact))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("その他", text: colophonBinding(\.notes), axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var activeWorkColophonSection: some View {
        Section("奥付") {
            Toggle("奥付を追加", isOn: colophonBinding(\.isEnabled))

            if viewModel.settings.colophon.isEnabled {
                if viewModel.settings.colophon.publicationDate != nil {
                    DatePicker(
                        "発行日",
                        selection: publicationDateBinding,
                        displayedComponents: .date
                    )
                    Button("発行日を空欄にする") {
                        viewModel.updateColophon { colophon in
                            colophon.publicationDate = nil
                        }
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("発行日を入力") {
                        viewModel.updateColophon { colophon in
                            colophon.publicationDate = Date()
                        }
                    }
                }

                TextField("印刷所名", text: colophonBinding(\.printerName))
            }
        }
    }

    @ViewBuilder
    private var circleLogoControls: some View {
        let isPaid = viewModel.subscriptionStatus == .paid

        HStack {
            Toggle("サークルロゴを使用", isOn: circleImageUsageBinding)

            if !isPaid {
                paidFeatureBadge
                    .accessibilityLabel("有料コンテンツ")
            }
        }

        if viewModel.settings.colophon.usesCircleImageForCreator {
            circleLogoImportRow(isPaid: isPaid)
        }
    }

    @ViewBuilder
    private func circleLogoImportRow(isPaid: Bool) -> some View {
        let imageData = viewModel.settings.colophon.circleImageData

        if viewModel.subscriptionStatus == .paid {
            HStack {
                imagePreview(data: imageData)

                PhotosPicker(selection: $selectedCircleImageItem, matching: .images) {
                    Label("サークルロゴ画像をインポート", systemImage: "photo.badge.plus")
                }

                Spacer()

                if imageData != nil {
                    Button(role: .destructive) {
                        clearImage(\.circleImageData)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("サークルロゴ画像を削除")
                }
            }
        } else {
            Button {
                showsPaidFeatureAlert = true
            } label: {
                HStack {
                    Text("サークルロゴ画像をインポート")
                    paidFeatureBadge
                }
            }
        }
    }

    @ViewBuilder
    private func imagePreview(data: Data?) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func colophonBinding<Value>(_ keyPath: WritableKeyPath<ColophonSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings.colophon[keyPath: keyPath] },
            set: { newValue in
                viewModel.updateColophon { colophon in
                    colophon[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var circleImageUsageBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.colophon.usesCircleImageForCreator },
            set: { newValue in
                guard viewModel.subscriptionStatus == .paid else {
                    showsPaidFeatureAlert = true
                    return
                }

                viewModel.updateColophon { colophon in
                    colophon.usesCircleImageForCreator = newValue
                }
            }
        )
    }

    private var publicationDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.settings.colophon.publicationDate ?? Date() },
            set: { newValue in
                viewModel.updateColophon { colophon in
                    colophon.publicationDate = newValue
                }
            }
        )
    }

    private func loadImageData(
        from item: PhotosPickerItem?,
        keyPath: WritableKeyPath<ColophonSettings, Data?>
    ) {
        guard let item else { return }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            await MainActor.run {
                viewModel.updateColophon { colophon in
                    colophon[keyPath: keyPath] = data
                }
            }
        }
    }

    private func clearImage(_ keyPath: WritableKeyPath<ColophonSettings, Data?>) {
        viewModel.updateColophon { colophon in
            colophon[keyPath: keyPath] = nil
        }
    }

    private var paidFeatureBadge: some View {
        Text("有料")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue, in: Capsule())
    }
}

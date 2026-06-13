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
    @ObservedObject var proStore: HonkumiProStore

    @State private var selectedCircleImageItem: PhotosPickerItem?
    @State private var isProPurchasePresented = false
    @State private var presentedProFeature: HonkumiProFeature?

    var body: some View {
        Form {
            switch mode {
            case .userDefault:
                defaultColophonSection
            case .activeWork:
                activeWorkColophonSection
            }
        }
        .listSectionSpacing(.compact)
        .onChange(of: selectedCircleImageItem) { _, item in
            loadImageData(from: item, keyPath: \.circleImageData)
        }
        .sheet(isPresented: $isProPurchasePresented) {
            HonkumiProPurchaseView(proStore: proStore, feature: presentedProFeature)
        }
        .alert(item: purchaseMessageBinding) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.body),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var defaultColophonSection: some View {
        Section("奥付") {
            colophonIdentityFields
        }
    }

    private var activeWorkColophonSection: some View {
        Section("奥付") {
            Toggle("奥付を追加", isOn: colophonBinding(\.isEnabled))

            if viewModel.settings.colophon.isEnabled {
                Toggle("発行日を表示", isOn: colophonBinding(\.showsPublicationDate))
                PublicationDateField(date: publicationDateOptionalBinding)
                    .disabled(!viewModel.settings.colophon.showsPublicationDate)

                Toggle("印刷所を表示", isOn: colophonBinding(\.showsPrinterName))
                TextField("印刷所名", text: colophonBinding(\.printerName))
                    .disabled(!viewModel.settings.colophon.showsPrinterName)
            }
        }
    }

    private var colophonIdentityFields: some View {
        Group {
            Toggle("作者名を表示", isOn: colophonBinding(\.showsAuthorName))
            if viewModel.settings.colophon.showsAuthorName {
                TextField("作者名", text: colophonBinding(\.authorName))
            }

            Toggle("サークル名を表示", isOn: colophonBinding(\.showsCircleName))
            if viewModel.settings.colophon.showsCircleName {
                TextField("サークル名", text: colophonBinding(\.circleName))
            }
            circleLogoControls

            Toggle("URLを表示", isOn: colophonBinding(\.showsWebsiteURL))
            Toggle("QRコードを表示", isOn: colophonBinding(\.showsQRCode))
            TextField("HP", text: colophonBinding(\.websiteURL))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!viewModel.settings.colophon.showsWebsiteURL && !viewModel.settings.colophon.showsQRCode)
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

    @ViewBuilder
    private var circleLogoControls: some View {
        let isPaid = proStore.isProUnlocked

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

        if isPaid {
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
                presentProPurchase()
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
                guard proStore.isProUnlocked else {
                    presentProPurchase()
                    return
                }

                viewModel.updateColophon { colophon in
                    colophon.usesCircleImageForCreator = newValue
                }
            }
        )
    }

    private var publicationDateOptionalBinding: Binding<Date?> {
        Binding(
            get: { viewModel.settings.colophon.publicationDate },
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
        Label("有料", systemImage: "lock.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.blue, in: Capsule())
    }

    private var purchaseMessageBinding: Binding<HonkumiProPurchaseMessage?> {
        Binding(
            get: { proStore.purchaseMessage },
            set: { _ in proStore.clearPurchaseMessage() }
        )
    }

    private func presentProPurchase() {
        presentedProFeature = .circleLogo
        isProPurchasePresented = true
    }
}

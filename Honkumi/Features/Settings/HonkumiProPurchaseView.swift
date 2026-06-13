import StoreKit
import SwiftUI

struct HonkumiProPurchaseView: View {
    @ObservedObject var proStore: HonkumiProStore
    let feature: HonkumiProFeature?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(proStore.isProUnlocked ? "Honkumi Pro 購入済み" : "Honkumi Pro")
                            .font(.title3.weight(.semibold))

                        Text("買い切りで、入稿向けPDFと制作補助の有料機能を解放します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let feature {
                    Section("選択した機能") {
                        featureRow(feature)
                    }
                }

                Section("解放される機能") {
                    ForEach(HonkumiProFeature.allCases) { feature in
                        featureRow(feature)
                    }
                }

                Section {
                    Button {
                        Task {
                            await proStore.purchase()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if proStore.isPurchasing || proStore.isLoadingProducts {
                                ProgressView()
                            } else {
                                Text(purchaseButtonTitle)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(proStore.isProUnlocked || proStore.isBusy)

                    Button {
                        Task {
                            await proStore.restorePurchases()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if proStore.isRestoring {
                                ProgressView()
                            } else {
                                Text("購入を復元")
                            }
                            Spacer()
                        }
                    }
                    .disabled(proStore.isBusy)
                } footer: {
                    Text("購入状態はStoreKit 2のTransaction.currentEntitlementsから確認し、アプリ起動時と復元時に再読み込みします。")
                }
            }
            .navigationTitle("Honkumi Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .task {
                proStore.start()
            }
            .alert(item: purchaseMessageBinding) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.body),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var purchaseButtonTitle: String {
        guard !proStore.isProUnlocked else {
            return "購入済み"
        }

        guard !proStore.displayPrice.isEmpty else {
            return "商品情報を読み込み中"
        }

        return "Honkumi Proを購入 \(proStore.displayPrice)"
    }

    private var purchaseMessageBinding: Binding<HonkumiProPurchaseMessage?> {
        Binding(
            get: { proStore.purchaseMessage },
            set: { _ in proStore.clearPurchaseMessage() }
        )
    }

    private func featureRow(_ feature: HonkumiProFeature) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: feature.systemImage)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 2)
    }
}

import Combine
import Foundation
import StoreKit

enum HonkumiProFeature: String, CaseIterable, Identifiable {
    case pageNumberFonts
    case circleLogo
    case formatting
    case poweredByHonkumi
    case pdfExportAds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pageNumberFonts:
            "有料ノンブルフォント"
        case .circleLogo:
            "サークルロゴ"
        case .formatting:
            "有料整形機能"
        case .poweredByHonkumi:
            "Powered by Honkumi非表示"
        case .pdfExportAds:
            "PDF出力時の広告非表示"
        }
    }

    var description: String {
        switch self {
        case .pageNumberFonts:
            "ノンブルと目次ページ番号に選択したフォントを反映できます。"
        case .circleLogo:
            "サークルロゴを設定し、PDFの奥付に出力できます。"
        case .formatting:
            "三点リーダー、ダッシュ、句読点、括弧などの有料整形ルールを利用できます。"
        case .poweredByHonkumi:
            "PDF内のPowered by Honkumi表示を非表示にできます。"
        case .pdfExportAds:
            "PDF出力時の広告表示をスキップできます。"
        }
    }

    var systemImage: String {
        switch self {
        case .pageNumberFonts:
            "textformat.123"
        case .circleLogo:
            "photo.badge.plus"
        case .formatting:
            "wand.and.sparkles"
        case .poweredByHonkumi:
            "eye.slash"
        case .pdfExportAds:
            "rectangle.slash"
        }
    }
}

struct HonkumiProPurchaseMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
}

@MainActor
final class HonkumiProStore: ObservableObject {
    static let productID = "honkumi.pro"

    @Published private(set) var product: Product?
    @Published private(set) var isProUnlocked = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var purchaseMessage: HonkumiProPurchaseMessage?

    private var transactionUpdatesTask: Task<Void, Never>?

    var displayPrice: String {
        product?.displayPrice ?? ""
    }

    var isBusy: Bool {
        isLoadingProducts || isPurchasing || isRestoring
    }

    func start() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }

        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshPurchasedStatus()
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                purchaseMessage = HonkumiProPurchaseMessage(
                    title: "商品情報を取得できません",
                    body: "Honkumi Proの商品情報が見つかりませんでした。StoreKit設定またはApp Store ConnectのProduct IDを確認してください。"
                )
            }
        } catch {
            purchaseMessage = HonkumiProPurchaseMessage(
                title: "商品情報を取得できません",
                body: error.localizedDescription
            )
        }
    }

    func refreshPurchasedStatus() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == Self.productID else { continue }
                guard transaction.revocationDate == nil else { continue }
                unlocked = true
            case .unverified(let transaction, _):
                guard transaction.productID == Self.productID else { continue }
                purchaseMessage = HonkumiProPurchaseMessage(
                    title: "購入情報を検証できません",
                    body: "Honkumi Proの購入情報を検証できなかったため、有料機能を解放しませんでした。"
                )
            }
        }

        isProUnlocked = unlocked
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let storeProduct = try await purchasableProduct()
            let result = try await storeProduct.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard transaction.productID == Self.productID else {
                        purchaseMessage = HonkumiProPurchaseMessage(
                            title: "購入情報が一致しません",
                            body: "購入された商品がHonkumi Proではありませんでした。"
                        )
                        return
                    }

                    await transaction.finish()
                    await refreshPurchasedStatus()
                    isProUnlocked = true
                    purchaseMessage = HonkumiProPurchaseMessage(
                        title: "購入が完了しました",
                        body: "Honkumi Proの機能を利用できます。"
                    )
                case .unverified:
                    purchaseMessage = HonkumiProPurchaseMessage(
                        title: "購入を検証できません",
                        body: "App Storeの検証に失敗したため、有料機能を解放しませんでした。"
                    )
                }
            case .userCancelled:
                purchaseMessage = HonkumiProPurchaseMessage(
                    title: "購入をキャンセルしました",
                    body: "購入は完了していません。"
                )
            case .pending:
                purchaseMessage = HonkumiProPurchaseMessage(
                    title: "購入が保留中です",
                    body: "承認が完了するとHonkumi Proが利用可能になります。"
                )
            @unknown default:
                purchaseMessage = HonkumiProPurchaseMessage(
                    title: "購入を完了できません",
                    body: "不明な購入状態が返されました。"
                )
            }
        } catch {
            purchaseMessage = HonkumiProPurchaseMessage(
                title: "購入に失敗しました",
                body: error.localizedDescription
            )
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshPurchasedStatus()
            purchaseMessage = HonkumiProPurchaseMessage(
                title: isProUnlocked ? "購入を復元しました" : "購入が見つかりません",
                body: isProUnlocked ? "Honkumi Proの機能を利用できます。" : "このApple IDで復元できるHonkumi Proの購入はありませんでした。"
            )
        } catch {
            purchaseMessage = HonkumiProPurchaseMessage(
                title: "購入を復元できません",
                body: error.localizedDescription
            )
        }
    }

    func clearPurchaseMessage() {
        purchaseMessage = nil
    }

    private func purchasableProduct() async throws -> Product {
        if let product {
            return product
        }

        let products = try await Product.products(for: [Self.productID])
        guard let product = products.first else {
            throw HonkumiProStoreError.productNotFound
        }

        self.product = product
        return product
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else { return }
            await refreshPurchasedStatus()
            await transaction.finish()
        case .unverified(let transaction, _):
            guard transaction.productID == Self.productID else { return }
            purchaseMessage = HonkumiProPurchaseMessage(
                title: "購入情報を検証できません",
                body: "Honkumi Proの取引更新を検証できませんでした。"
            )
        }
    }
}

private enum HonkumiProStoreError: LocalizedError {
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            "Honkumi Proの商品情報が見つかりませんでした。"
        }
    }
}

import Darwin
import Foundation

#if DEBUG
nonisolated enum VerticalTypesettingSamplePDFExporter {
    static func exportIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HONKUMI_EXPORT_VERTICAL_TYPESETTING_SAMPLES"] == "1" else { return }

        do {
            let destinationDirectory = try sampleOutputDirectory()
            let exporter = BodyPDFExportService()
            let publisherSettings = samplePublisherSettings()

            for document in sampleDocuments() {
                let outputDocument = document.applyingPublisherInfo(from: publisherSettings)
                let temporaryURL = try exporter.export(document: outputDocument, subscriptionStatus: .free)
                let outputURL = destinationDirectory
                    .appendingPathComponent(document.title)
                    .appendingPathExtension("pdf")
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: temporaryURL, to: outputURL)
                print("Exported vertical typesetting sample PDF:", outputURL.path)
            }

            if environment["HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT"] == "1" {
                exit(0)
            }
        } catch {
            fputs("Failed to export vertical typesetting sample PDFs: \(error)\n", stderr)
            if environment["HONKUMI_EXPORT_VERTICAL_TYPESETTING_EXIT"] == "1" {
                exit(1)
            }
        }
    }

    private static func sampleOutputDirectory() throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDirectory = documentsDirectory.appendingPathComponent("VerticalTypesettingSamples", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
    }

    private static func sampleDocuments() -> [ManuscriptDocument] {
        [
            sampleDocument(title: "サンプル", orientation: .tateChuYoko),
            sampleDocument(title: "サンプル 英数字縦中央", orientation: .tateChuYoko),
            sampleDocument(title: "サンプル 英数字横倒し", orientation: .sideways)
        ]
    }

    private static func sampleDocument(
        title: String,
        orientation: AlphanumericOrientation
    ) -> ManuscriptDocument {
        var settings = EditorSettings.default.validated
        settings.charactersPerLine = 34
        settings.linesPerPage = 16
        settings.fontSize = 9
        settings.showTableOfContents = true
        settings.showChapterTitle = true
        settings.alphanumericOrientation = orientation

        var colophon = ColophonSettings.default
        colophon.isEnabled = true
        colophon.printerName = "サンプル印刷所"
        colophon.publicationDate = samplePublicationDate
        settings.colophon = colophon

        return ManuscriptDocument(
            title: title,
            body: sampleBody,
            settings: settings
        )
    }

    private static func samplePublisherSettings() -> EditorSettings {
        var settings = EditorSettings.default.validated
        var colophon = ColophonSettings.default
        colophon.publisherName = "山田太郎"
        colophon.authorName = "Honkumi確認用"
        colophon.circleName = "サンプルサークル"
        colophon.websiteURL = "https://example.com"
        colophon.contact = "typesetting@example.com"
        colophon.notes = "句読点・英数字・括弧・リーダー・奥付の確認用サンプルです。"
        settings.colophon = colophon
        return settings
    }

    private static var samplePublicationDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)
        components.year = 2026
        components.month = 6
        components.day = 3
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private static let sampleBody = """
    [[toc]]
    [[CHAPTER: 句読点確認]]
    句読点の位置を確認します。本文中の、句点。全角コンマ，ピリオド．縦書き記号︑︒が右上に浮かないことを見ます。
    きゃきゅきょ、しゃしゅしょ、ちゃちゅちょ、ぎゃぎゅぎょを続けて確認します。
    あった、いっしょ、ちょっと、プレビュー、プレビューモードで小書き文字の大きさと位置を見ます。
    今日は良い天気ですね。
    そうやって、次に来る流れを予測しているのだろう。
    空には白い雲がゆっくりと流れていた……。
    プレビュー、プレビュ、きゃ、しゅ、ちょ、あっ、ちょっと、きゃりー、シュッとした小書き文字を続けます。
    小書き仮名の確認として、ぁぃぅぇぉゃゅょっゎ、ァィゥェォャュョッヮヵヶを並べます。
    本文中の……。三点リーダーと句点の間隔、そして……連続したリーダーが分離しないことを確認します。
    [[PAGE_BREAK]]
    [[CHAPTER: 英数字確認]]
    TypeScriptとNext.js、React、Hello World、abcdef、ABCDEF、1234567890を本文の中で確認します。
    12、123、1234567890などの半角数字は横倒しのランとして配置されることを確認します。
    API Client v2.1.0やfoo_bar-baz/test+demo&copyも、半角英数字と記号のランだけが横倒しになります。
    日本語本文、全角数字１２３４５、全角記号！？「」は通常の縦書きのまま残します。
    [[PAGE_BREAK]]
    [[CHAPTER: 括弧確認]]
    「かぎ括弧」『二重かぎ括弧』（丸括弧）【隅付き括弧】〈山括弧〉《二重山括弧》を確認します。
    【隅付き括弧】の内外に不要な空きがなく、開き括弧と閉じ括弧が本文の中心に揃うことを見ます。
    「これは本当に大丈夫!?」という文で、!?」だけが次の行に送られないことを確認します。
    （開き括弧が行末に残らず）閉じ括弧だけが行頭に出ないようにします。
    [[PAGE_BREAK]]
    [[CHAPTER: 長文確認]]
    長文ページでは、改ページという語の最後のジだけが単独で次の行や段に送られないかを確認します。
    文章を続けます。これは縦書きPDF出力の確認用の長い本文です。句読点、括弧、三点リーダー……。そして英数字TypeScriptやNext.jsを交ぜても段組みが乱れないことを確認します。
    さらに本文を続けます。プレビューのュ、きゃ、しゅ、ちょ、あっ、などが本文の字枠内で自然に見えるか確認します。終端の!?」が孤立しないことも見ます。
    改ページ、改ページ、改ページ。短い語尾だけが泣き別れしないよう、行末と行頭の禁則処理を確認します。
    [[colophon]]
    """
}
#endif

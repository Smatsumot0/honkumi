import Foundation

nonisolated enum InitialSampleWork {
    static let userDefaultsKey = "honkumi.initialSampleWorkCreated"
    static let title = "Honkumiの使い方サンプル"

    struct SeedResult: Equatable {
        var data: AppData
        var didCreateSample: Bool
    }

    static func document(
        settings: EditorSettings,
        createdAt: Date = Date()
    ) -> ManuscriptDocument {
        ManuscriptDocument(
            categoryId: WorkCategory.uncategorizedId,
            title: title,
            body: sampleBody,
            settings: settings.validated,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func seedIfNeeded(
        in data: AppData,
        hasCreatedInitialSample: Bool,
        settings: EditorSettings,
        createdAt: Date = Date()
    ) -> SeedResult {
        guard !hasCreatedInitialSample, data.works.isEmpty else {
            return SeedResult(data: data, didCreateSample: false)
        }

        var seededData = data
        if !seededData.categories.contains(where: { $0.id == WorkCategory.uncategorizedId }) {
            seededData.categories.insert(.uncategorized, at: 0)
        }

        let sample = document(settings: settings, createdAt: createdAt)
        seededData.works.insert(sample, at: 0)
        seededData.activeWorkId = sample.id
        return SeedResult(data: seededData, didCreateSample: true)
    }

    static let sampleBody = """
    [[toc]]

    # はじめに

    　これは、Honkumiの使い方を確認するためのサンプル作品です。
    　本文を書きながら、目次、章タイトル、改ページ、編集アイコン、奥付、PDF出力の見え方を試せるようになっています。

    　Honkumiでは、スマートフォンやタブレットだけで小説本文を書き、印刷所へ入稿しやすいPDFとして出力できます。
    　まずはこのサンプルを自由に編集して、文字数、行数、余白、ノンブル、目次の表示を確認してみてください。

    # 編集アイコンの使い方

    　Honkumiの編集画面には、本文を書きやすくするためのアイコンがあります。
    　上部のアイコンは本文内の移動、下部のアイコンは入力補助や編集操作に使います。

    　上部のアイコン

    　⇤　一番上へ移動します。
    　↑　前の位置へ移動します。
    　↓　次の位置へ移動します。
    　⇥　一番下へ移動します。

    　下部のアイコン

    　↶　ひとつ前の操作に戻します。
    　↷　戻した操作をやり直します。
    　「」　かぎかっこを入力します。
    　（）　丸かっこを入力します。
    　〝〟　ダブルミュートを入力します。
    　…　三点リーダを入力します。
    　〜　波線を入力します。
    　―　ダッシュを入力します。
    　#　章タイトルを入力します。
    　↵　改ページを入力します。
    　＿　全角空白を入力します。
    　虫眼鏡　本文を検索します。

    　章タイトルは、本文中では「# 第一章」のように入力されます。
    　改ページは、本文中では [[PAGE_BREAK]] として入力されます。
    　目次を使う場合、章タイトルは目次にも反映されます。

    # 本文を書いてみる

    　縦書きの小説では、段落の先頭を一字下げると読みやすくなります。
    　Honkumiの整形機能を使うと、字下げや記号の統一を自動で行えます。

    「会話文も、このように入力できます」
    　会話のあとに地の文を続ける場合も、実際の本に近い形で確認できます。

    　小説本文では、三点リーダは……、ダッシュは――のようにそろえると、印刷時の見た目が整いやすくなります。
    　長音符のー、波線の〜、半角英数字や記号も、入稿前にチェックできます。

    # 目次と章タイトル

    　行頭に「# 」を付けると、章タイトルとして扱われます。
    　本文の好きな位置に [[toc]] を入れると、目次を表示できます。

    　目次を使わない作品では、印刷設定から目次をオフにできます。
    　短い作品やコピー本では目次なし、長めの同人誌では目次ありにすると便利です。

    [[PAGE_BREAK]]

    # 改ページを試す

    　この章の前には、改ページタグを入れています。
    　[[PAGE_BREAK]] と書くと、その位置でページを分けられます。

    　章の始まりを必ず新しいページにしたいときや、あとがき、奥付を本文と分けたいときに使ってください。

    　プレビューでは、実際のPDFに近い形でページの切れ目を確認できます。
    　文字サイズや余白を変えた場合は、ページ数やノンブル位置も確認しておくと安心です。

    # 入稿前に確認すること

    　PDFを出力する前に、入稿チェックを行います。
    　Honkumiでは、修正できる項目や自動修正できる項目を中心に警告を表示します。

    　特に確認したい項目は、次のようなものです。

    　・本文がページからはみ出していないか
    　・ノンブルが本文に近すぎないか
    　・奥付に必要な情報が入っているか
    　・印刷に向かない文字や記号が残っていないか
    　・目次や奥付にもノンブルを振るかどうか

    # 奥付について

    　同人誌では、最後のページに奥付を入れることが多くあります。
    　作者名、サークル名、発行日、連絡先、印刷所などを必要に応じて設定してください。

    　表示しない項目は、印刷設定でオフにできます。
    　オフにした項目は、PDFにも表示されません。

    # おわりに

    　このサンプルは、削除しても問題ありません。
    　新しい作品を作成し、本文を書き始めたら、プレビューと入稿チェックを使いながらPDFを出力してみてください。

    　Honkumiが、あなたの本づくりの手助けになりますように。
    """
}

import Foundation

struct ManuscriptDocument: Codable, Equatable, Identifiable {
    var id: UUID
    var categoryId: UUID
    var title: String
    var body: String
    var settings: EditorSettings
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        categoryId: UUID = WorkCategory.uncategorizedId,
        title: String = "無題の原稿",
        body: String = ManuscriptDocument.sampleBody,
        settings: EditorSettings = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryId = categoryId
        self.title = title
        self.body = body
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ManuscriptDocument {
    private enum CodingKeys: String, CodingKey {
        case id
        case categoryId
        case title
        case body
        case settings
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            categoryId: try container.decodeIfPresent(UUID.self, forKey: .categoryId) ?? WorkCategory.uncategorizedId,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "無題の作品",
            body: try container.decodeIfPresent(String.self, forKey: .body) ?? "",
            settings: try container.decodeIfPresent(EditorSettings.self, forKey: .settings) ?? .default,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }
}

extension ManuscriptDocument {
    static let sampleBody = """
    [[CHAPTER: 第一章]]
    あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよ
    らりるれろわをん
    アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨ
    ラリルレロワヲン

    これは縦書きプレビュー確認用のサンプル本文です。一行あたりの文字数を変更すると、縦方向に入る文字数が変わります。
    [[PAGE_BREAK]]
    [[CHAPTER: 第二章]]
    改ページ後のサンプルです。五十音を入れて、文字数と行数の設定が見えやすいようにしています。
    """
}

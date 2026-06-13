import Foundation

nonisolated enum PrintTextReplacementKind: String, Equatable {
    case heart
    case unsupportedEmoji
}

nonisolated enum PrintTextReplacementLocation: Equatable {
    case title
    case body(offset: Int)
    case colophon(field: String)

    var displayName: String {
        switch self {
        case .title:
            "作品名"
        case let .body(offset):
            "本文 \(offset + 1)文字目付近"
        case let .colophon(field):
            "奥付 \(field)"
        }
    }
}

nonisolated struct PrintTextReplacement: Equatable {
    let location: PrintTextReplacementLocation
    let original: String
    let replacement: String
    let kind: PrintTextReplacementKind
}

nonisolated struct PrintTextNormalizationResult: Equatable {
    let text: String
    let replacements: [PrintTextReplacement]
}

nonisolated struct PrintTextNormalizationReport: Equatable {
    let replacements: [PrintTextReplacement]

    var heartReplacementCount: Int {
        replacements.filter { $0.kind == .heart }.count
    }

    var unsupportedEmojiReplacementCount: Int {
        replacements.filter { $0.kind == .unsupportedEmoji }.count
    }

    var totalReplacementCount: Int {
        replacements.count
    }

    var containsEmojiFontRisk: Bool {
        totalReplacementCount > 0
    }

    var sampleLocations: String {
        replacements
            .prefix(5)
            .map { "\($0.location.displayName): \($0.original)→\($0.replacement)" }
            .joined(separator: " / ")
    }
}

nonisolated enum PrintTextNormalizer {
    static let printableHeart = "♡"
    static let unsupportedEmojiReplacement = "□×"

    static func normalizedDocument(_ document: ManuscriptDocument) -> ManuscriptDocument {
        var normalizedDocument = document
        normalizedDocument.title = normalize(document.title, location: .title).text
        var settings = document.settings
        settings.colophon = normalizedColophon(settings.colophon)
        normalizedDocument.settings = settings
        normalizedDocument.body = normalize(document.body, location: nil).text
        return normalizedDocument
    }

    static func report(
        title: String,
        body: String,
        colophon: ColophonSettings
    ) -> PrintTextNormalizationReport {
        var replacements: [PrintTextReplacement] = []
        replacements.append(contentsOf: normalize(title, location: .title).replacements)
        replacements.append(contentsOf: normalize(body, location: nil).replacements)

        for field in colophonTextFields(from: colophon) {
            replacements.append(contentsOf: normalize(
                field.value,
                location: .colophon(field: field.label)
            ).replacements)
        }

        return PrintTextNormalizationReport(replacements: replacements)
    }

    static func normalize(
        _ text: String,
        location: PrintTextReplacementLocation?
    ) -> PrintTextNormalizationResult {
        var output = ""
        var replacements: [PrintTextReplacement] = []
        var characterOffset = 0
        var skipsVariationSelector = false

        for character in text {
            let original = String(character)

            if skipsVariationSelector, isVariationSelectorOnly(character) {
                characterOffset += 1
                continue
            }

            skipsVariationSelector = false
            if isHeart(character) {
                output += printableHeart
                if original != printableHeart {
                    replacements.append(PrintTextReplacement(
                        location: location ?? .body(offset: characterOffset),
                        original: original,
                        replacement: printableHeart,
                        kind: .heart
                    ))
                }
                skipsVariationSelector = true
            } else if isUnsupportedEmoji(character) {
                output += unsupportedEmojiReplacement
                replacements.append(PrintTextReplacement(
                    location: location ?? .body(offset: characterOffset),
                    original: original,
                    replacement: unsupportedEmojiReplacement,
                    kind: .unsupportedEmoji
                ))
            } else {
                output += original
            }

            characterOffset += 1
        }

        return PrintTextNormalizationResult(text: output, replacements: replacements)
    }

    private static func normalizedColophon(_ colophon: ColophonSettings) -> ColophonSettings {
        var normalized = colophon
        normalized.workTitle = normalize(colophon.workTitle, location: nil).text
        normalized.publisherName = normalize(colophon.publisherName, location: nil).text
        normalized.authorName = normalize(colophon.authorName, location: nil).text
        normalized.circleName = normalize(colophon.circleName, location: nil).text
        normalized.printerName = normalize(colophon.printerName, location: nil).text
        normalized.websiteURL = normalize(colophon.websiteURL, location: nil).text
        normalized.xURL = normalize(colophon.xURL, location: nil).text
        normalized.pixivURL = normalize(colophon.pixivURL, location: nil).text
        normalized.contact = normalize(colophon.contact, location: nil).text
        normalized.notes = normalize(colophon.notes, location: nil).text
        return normalized
    }

    private static func colophonTextFields(from colophon: ColophonSettings) -> [(label: String, value: String)] {
        [
            ("作品名", colophon.workTitle),
            ("発行者", colophon.publisherName),
            ("作者", colophon.authorName),
            ("サークル", colophon.circleName),
            ("印刷所", colophon.printerName),
            ("HP", colophon.websiteURL),
            ("x", colophon.xURL),
            ("pixiv", colophon.pixivURL),
            ("連絡先", colophon.contact),
            ("その他", colophon.notes)
        ]
    }

    private static func isHeart(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2661, 0x2665, 0x2763, 0x2764,
                 0x1F493...0x1F49F,
                 0x1F5A4,
                 0x1F90D...0x1F90E,
                 0x1F9E1,
                 0x1FA75...0x1FA77:
                true
            default:
                false
            }
        }
    }

    private static func isUnsupportedEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return scalar.properties.isEmojiPresentation
                || scalar.properties.isEmojiModifier
                || scalar.properties.isEmojiModifierBase
                || value == 0xFE0F
                || value == 0x200D
                || (0x1F000...0x1FAFF).contains(value)
        }
    }

    private static func isVariationSelectorOnly(_ character: Character) -> Bool {
        !character.unicodeScalars.isEmpty
            && character.unicodeScalars.allSatisfy { scalar in
                (0xFE00...0xFE0F).contains(scalar.value)
                    || (0xE0100...0xE01EF).contains(scalar.value)
            }
    }
}

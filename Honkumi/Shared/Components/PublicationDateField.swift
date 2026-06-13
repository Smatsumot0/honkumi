import SwiftUI

struct PublicationDateField: View {
    @Binding var date: Date?
    @State private var draftText = ""
    @State private var validationState: ValidationState = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("yyyy/mm/dd", text: $draftText)
                    .publicationDateTextInputStyle()
                    .onSubmit {
                        commitDraft()
                    }
                    .onChange(of: draftText) { _, _ in
                        commitDraft(allowsPartialInput: true)
                    }

                Button {
                    draftText = ""
                    date = nil
                    validationState = .empty
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("発行日を空欄にする")
                .disabled(draftText.isEmpty && date == nil)
            }

            if let message = validationState.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(validationState.messageColor)
            }
        }
        .onAppear {
            draftText = Self.string(from: date)
            validationState = draftText.isEmpty ? .empty : .valid
        }
    }

    private func commitDraft(allowsPartialInput: Bool = false) {
        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            date = nil
            validationState = .empty
            return
        }

        let result = PublicationDateNormalizer.parse(trimmedText)
        guard case let .valid(parsedDate) = result else {
            validationState = allowsPartialInput && Self.isPotentialPartialInput(trimmedText) ? .partial : .invalid
            return
        }

        date = parsedDate
        validationState = .valid
        if !allowsPartialInput || Self.isCompleteInput(trimmedText) {
            let normalizedText = Self.string(from: parsedDate)
            if draftText != normalizedText {
                draftText = normalizedText
            }
        }
    }

    private static func string(from date: Date?) -> String {
        guard let date else { return "" }
        return formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static func isCompleteInput(_ text: String) -> Bool {
        if text.contains("/") || text.contains("-") {
            let parts = text.replacingOccurrences(of: "-", with: "/").split(separator: "/", omittingEmptySubsequences: false)
            return (parts.count == 2 || parts.count == 3) && parts.allSatisfy { !$0.isEmpty }
        }

        return [3, 4, 5, 6, 8].contains(text.count)
    }

    private static func isPotentialPartialInput(_ text: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789/-")
        guard text.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return false }
        let digitCount = text.filter(\.isNumber).count
        if text.contains("/") || text.contains("-") {
            return digitCount < 8
        }
        return digitCount < 3
    }

    private enum ValidationState {
        case empty
        case partial
        case invalid
        case valid

        var message: String? {
            switch self {
            case .empty, .valid:
                nil
            case .partial:
                "日付が未確定です"
            case .invalid:
                "日付を確認してください"
            }
        }

        var messageColor: Color {
            switch self {
            case .invalid:
                .red
            default:
                .secondary
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func publicationDateTextInputStyle() -> some View {
        #if os(iOS)
        self
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

nonisolated enum PublicationDateParseResult: Equatable {
    case valid(Date)
    case invalid
}

nonisolated enum PublicationDateNormalizer {
    static func parse(_ input: String, currentYear: Int = Calendar.current.component(.year, from: Date())) -> PublicationDateParseResult {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .invalid }

        if text.contains("/") || text.contains("-") {
            return parseSeparated(text.replacingOccurrences(of: "-", with: "/"), currentYear: currentYear)
        }

        guard text.allSatisfy(\.isNumber) else { return .invalid }
        return parseDigits(text, currentYear: currentYear)
    }

    private static func parseSeparated(_ text: String, currentYear: Int) -> PublicationDateParseResult {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (parts.count == 2 || parts.count == 3),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return .invalid
        }

        let numbers = parts.compactMap(Int.init)
        guard numbers.count == parts.count else { return .invalid }

        if parts.count == 2 {
            return validatedDate(year: currentYear, month: numbers[0], day: numbers[1])
        }

        let year = normalizedYear(numbers[0], digitCount: parts[0].count)
        return validatedDate(year: year, month: numbers[1], day: numbers[2])
    }

    private static func parseDigits(_ text: String, currentYear: Int) -> PublicationDateParseResult {
        guard let value = Int(text) else { return .invalid }

        switch text.count {
        case 8:
            let year = value / 10_000
            let month = (value / 100) % 100
            let day = value % 100
            return validatedDate(year: year, month: month, day: day)
        case 6:
            let year = normalizedYear(value / 10_000, digitCount: 2)
            let month = (value / 100) % 100
            let day = value % 100
            return validatedDate(year: year, month: month, day: day)
        case 5:
            let year = normalizedYear(value / 1_000, digitCount: 2)
            let month = (value / 100) % 10
            let day = value % 100
            return validatedDate(year: year, month: month, day: day)
        case 4:
            let month = value / 100
            let day = value % 100
            return validatedDate(year: currentYear, month: month, day: day)
        case 3:
            let month = value / 100
            let day = value % 100
            return validatedDate(year: currentYear, month: month, day: day)
        default:
            return .invalid
        }
    }

    private static func normalizedYear(_ year: Int, digitCount: Int) -> Int {
        digitCount == 2 ? 2000 + year : year
    }

    private static func validatedDate(year: Int, month: Int, day: Int) -> PublicationDateParseResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60) ?? .current

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return .invalid
        }

        return .valid(date)
    }
}

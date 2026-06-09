import SwiftUI

struct PublicationDateField: View {
    @Binding var date: Date?
    @State private var draftText = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("yyyy/mm/dd", text: $draftText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    commitDraft()
                }
                .onChange(of: draftText) { _, _ in
                    commitDraft(allowsPartialInput: true)
                }

            Button {
                draftText = ""
                date = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("発行日を空欄にする")
            .disabled(draftText.isEmpty && date == nil)
        }
        .onAppear {
            draftText = Self.string(from: date)
        }
    }

    private func commitDraft(allowsPartialInput: Bool = false) {
        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            date = nil
            return
        }

        guard let parsedDate = Self.date(from: trimmedText) else { return }
        date = parsedDate
        if !allowsPartialInput || trimmedText.count >= 8 {
            draftText = Self.string(from: parsedDate)
        }
    }

    private static func string(from date: Date?) -> String {
        guard let date else { return "" }
        return formatter.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        inputFormatters.compactMap { $0.date(from: string) }.first
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let inputFormatters: [DateFormatter] = {
        ["yyyy/MM/dd", "yyyy/M/d", "yyyy-MM-dd"].map { format in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }
    }()
}

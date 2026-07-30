import SwiftUI

nonisolated enum CommonSettingsReviewCopy {
    static let title = "共通設定が変更されています"
    static let message = "この作品に適用する設定を選択してください。"
    static let editor = "エディタ設定"
    static let circle = "サークル設定"
    static let format = "フォーマット設定"
    static let print = "印刷設定"
    static let apply = "適用して開く"
    static let keepCurrent = "適用せず開く"
    static let cancel = "キャンセル"
}

nonisolated struct CommonSettingsReviewPresentation:
    Identifiable,
    Equatable {
    let request: UserDefaultSettingsReviewRequest
    var selection: UserDefaultSettingsSelection = .all

    var id: UUID { request.workID }
    var canApply: Bool { !selection.isEmpty }
}

struct CommonSettingsReviewDialog: View {
    @Binding var selection: UserDefaultSettingsSelection
    let onApply: () -> Void
    let onKeepCurrent: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CommonSettingsReviewCopy.title)
                .font(.headline)
            Text(CommonSettingsReviewCopy.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            selectionRow(
                CommonSettingsReviewCopy.editor,
                isOn: binding(\.editor)
            )
            selectionRow(
                CommonSettingsReviewCopy.circle,
                isOn: binding(\.circle)
            )
            selectionRow(
                CommonSettingsReviewCopy.format,
                isOn: binding(\.format)
            )
            selectionRow(
                CommonSettingsReviewCopy.print,
                isOn: binding(\.print)
            )

            Button(CommonSettingsReviewCopy.apply, action: onApply)
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
                .frame(maxWidth: .infinity)

            Button(CommonSettingsReviewCopy.keepCurrent, action: onKeepCurrent)
                .frame(maxWidth: .infinity)

            Button(
                CommonSettingsReviewCopy.cancel,
                role: .cancel,
                action: onCancel
            )
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 24, y: 8)
    }

    private func selectionRow(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName: isOn.wrappedValue
                        ? "checkmark.square.fill"
                        : "square"
                )
                .foregroundStyle(
                    isOn.wrappedValue ? Color.accentColor : Color.secondary
                )
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(
            isOn.wrappedValue ? "選択済み" : "未選択"
        )
        .accessibilityAddTraits(.isButton)
    }

    private func binding(
        _ keyPath: WritableKeyPath<UserDefaultSettingsSelection, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { selection[keyPath: keyPath] },
            set: { selection[keyPath: keyPath] = $0 }
        )
    }
}

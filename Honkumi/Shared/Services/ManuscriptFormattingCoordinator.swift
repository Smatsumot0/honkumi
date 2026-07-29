import Combine
import Foundation

@MainActor
final class ManuscriptFormattingCoordinator: ObservableObject {
    typealias FormatOperation = @Sendable (
        _ text: String,
        _ settings: FormatSettings,
        _ options: FormatOptions
    ) async -> String

    @Published private(set) var isFormatting = false

    private struct Request {
        let generation: Int
        let documentID: UUID
        let body: String
        let settings: FormatSettings
        let options: FormatOptions
    }

    private let documentStore: DocumentStore
    private let editDebounce: Duration
    private let formatOperation: FormatOperation
    private var cancellables = Set<AnyCancellable>()
    private var observedDocument: ManuscriptDocument
    private var generation = 0
    private var pendingRequest: Request?
    private var runningTask: Task<Void, Never>?
    private var editDebounceTask: Task<Void, Never>?
    private var isApplyingResult = false

    init(
        documentStore: DocumentStore,
        editDebounce: Duration = .milliseconds(250),
        formatOperation: @escaping FormatOperation =
            ManuscriptFormattingCoordinator.defaultFormatOperation
    ) {
        self.documentStore = documentStore
        self.editDebounce = editDebounce
        self.formatOperation = formatOperation
        self.observedDocument = documentStore.document

        documentStore.$document
            .dropFirst()
            .sink { [weak self] document in
                self?.documentDidChange(document)
            }
            .store(in: &cancellables)
    }

    deinit {
        runningTask?.cancel()
        editDebounceTask?.cancel()
    }

    func requestFormatting() {
        let document = documentStore.document
        let settings = document.settings.validated.formatSettings
        guard settings.enableAutoFormat else {
            cancelPendingRequests()
            return
        }

        generation += 1
        pendingRequest = Request(
            generation: generation,
            documentID: document.id,
            body: document.body,
            settings: settings,
            options: currentFormatOptions
        )
        isFormatting = true
        startNextRequestIfPossible()
    }

    func settingsDidDismiss(initial: ManuscriptFormatSessionSnapshot) {
        let document = documentStore.document
        let current = ManuscriptFormatSessionSnapshot(
            documentID: document.id,
            formatSettings: document.settings.formatSettings,
            formatOptions: currentFormatOptions
        )
        guard ManuscriptFullFormattingTrigger.shouldFormatAfterSettingsDismissal(
            initial: initial,
            current: current
        ) else { return }
        requestFormatting()
    }

    func proDidUnlockOutsideSettings() {
        guard ManuscriptFullFormattingTrigger.shouldFormatAfterProUnlock(
            settings: documentStore.document.settings.formatSettings
        ) else { return }
        requestFormatting()
    }

    private var currentFormatOptions: FormatOptions {
        FormatOptions(
            isPremiumUser: documentStore.subscriptionStatus == .paid
        )
    }

    private func startNextRequestIfPossible() {
        guard runningTask == nil, let request = pendingRequest else { return }
        pendingRequest = nil
        let operation = formatOperation
        runningTask = Task { [weak self] in
            let body = await operation(
                request.body,
                request.settings,
                request.options
            )
            self?.complete(request, formattedBody: body)
        }
    }

    private func complete(
        _ request: Request,
        formattedBody: String
    ) {
        let current = documentStore.document
        let canApply =
            request.generation == generation &&
            current.id == request.documentID &&
            current.body == request.body &&
            current.settings.validated.formatSettings == request.settings &&
            currentFormatOptions == request.options

        if canApply, formattedBody != request.body {
            isApplyingResult = true
            documentStore.updateBody(formattedBody)
            isApplyingResult = false
        }

        runningTask = nil
        startNextRequestIfPossible()
        refreshFormattingState()
    }

    private func documentDidChange(_ document: ManuscriptDocument) {
        defer { observedDocument = document }

        guard document.id == observedDocument.id else {
            generation += 1
            pendingRequest = nil
            editDebounceTask?.cancel()
            editDebounceTask = nil
            isFormatting = false
            return
        }

        guard !isApplyingResult,
              isFormatting,
              document.body != observedDocument.body else {
            return
        }

        generation += 1
        pendingRequest = nil
        editDebounceTask?.cancel()
        editDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: editDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            editDebounceTask = nil
            requestFormatting()
        }
    }

    private func refreshFormattingState() {
        isFormatting =
            runningTask != nil ||
            pendingRequest != nil ||
            editDebounceTask != nil
    }

    private func cancelPendingRequests() {
        generation += 1
        pendingRequest = nil
        editDebounceTask?.cancel()
        editDebounceTask = nil
        isFormatting = false
    }

    nonisolated static func defaultFormatOperation(
        text: String,
        settings: FormatSettings,
        options: FormatOptions
    ) async -> String {
        await Task.detached(priority: .userInitiated) {
            ManuscriptFormatter.formatManuscriptText(
                text,
                settings: settings,
                options: options
            )
        }.value
    }
}

# PDF Timeout and Emoji Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** プリフライト後のPDF生成に30秒上限を設け、タイムアウト時に生成を中止・後始末して即再試行可能にする。未対応絵文字の代替表示は現在の白い四角1文字だけにする。

**Architecture:** `PDFExportFlowCoordinator`に注入可能なtimeout sleeperとone-shot完了ゲートを置き、生成成功・通常失敗・30秒timeoutの最初の結果だけを採用する。生成タスクは非構造化Taskとして監視し、timeout後に遅れて返ったURLも削除する。`PDFExportService`は親キャンセルをdetached描画へ伝播し、`BodyPDFExportService`は主要段階とページループでキャンセルを確認して部分ファイルを削除する。絵文字は共通`PrintTextNormalizer`の定数だけを変更し、全利用箇所を同時に揃える。

**Tech Stack:** Swift Concurrency、UIKit PDF Renderer、Foundation、XCTest、XcodeBuild

## Global Constraints

- Depends on: chapter header plan may modify `PDFExportService.swift`; when both are implemented, merge the renderer arguments without戻し変更を行う。
- 30秒に含めるのは`PDFExportProducing.export`の開始からURL取得まで。プリフライト、広告、共有sheetは含めない。
- timeout後は広告、共有、`storeGeneratedURL`を呼ばない。
- success/failure/timeoutの完了通知は1回だけにする。
- すべての終了経路でcoordinator内部の`isExporting`と画面側`isExportingPDF`を解除する。
- timeout testで実時間30秒を待たず、手動発火できるsleeperを注入する。

---

## Task 1: 30秒timeoutを表すエラーと注入可能なsleeperを追加する

**Files:**

- Create: `Honkumi/Shared/Services/PDFExportTimeout.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`

**Produces:**

- `PDFExportFlowError.timedOut`
- `PDFExportTimeoutSleeping`
- `TaskPDFExportTimeoutSleeper`

### Steps

- [ ] 1. exact messageの失敗テストを追加する。

```swift
func testTimeoutErrorHasRetryableUserMessage() {
    XCTAssertEqual(
        PDFExportFlowError.timedOut.localizedDescription,
        "PDF生成が30秒以内に完了しませんでした。もう一度お試しください。"
    )
}
```

- [ ] 2. テストを実行し、型が未定義で失敗することを確認する。

- [ ] 3. 最小実装を作成する。

```swift
import Foundation

nonisolated enum PDFExportFlowError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "PDF生成が30秒以内に完了しませんでした。もう一度お試しください。"
        }
    }
}

@MainActor
protocol PDFExportTimeoutSleeping: AnyObject {
    func sleep(for duration: Duration) async throws
}

@MainActor
final class TaskPDFExportTimeoutSleeper: PDFExportTimeoutSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
```

- [ ] 4. exact messageテストを成功させる。

- [ ] 5. コミットする。

```bash
git add Honkumi/Shared/Services/PDFExportTimeout.swift \
  HonkumiTests/PDFExportFlowCoordinatorTests.swift
git commit -m "Define PDF export timeout"
```

---

## Task 2: 生成とtimeoutをone-shotで競合させる

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportFlowCoordinator.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`

**Consumes:**

- Task 1のtimeout error/sleeper

**Produces:**

- `PDFExportFlowCoordinator.init(timeout:sleeper:fileManager:)`
- 30秒deadline race

### Steps

- [ ] 1. テスト用の手動sleeperを追加する。

```swift
@MainActor
private final class ManualPDFExportTimeoutSleeper: PDFExportTimeoutSleeping {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        requestedDurations.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation = $0
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func fire() {
        continuation?.resume()
        continuation = nil
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
```

- [ ] 2. 次の失敗テストを先に追加する。

  - suspended exporter中にmanual sleeperを発火すると`timedOut`が1件だけ渡る。
  - timeout時にad/share/storeGeneratedURLが0回。
  - requested durationが`.seconds(30)`。
  - timeout完了後に同じcoordinatorで2回目の成功を実行できる。
  - export成功後にsleeperを発火してもエラー/共有が増えない。
  - timeout後にsuspended exporterが遅れてURLを返しても、そのURLは共有されずファイルが削除される。

遅延成功テストでは一時ファイルを先に作成し、timeout完了を待ってから`exporter.resume(with:)`し、削除をpollする。

- [ ] 3. テストを実行し、initializerとtimeout動作がないため失敗することを確認する。

- [ ] 4. coordinatorへ依存を追加する。

```swift
private let timeout: Duration
private let timeoutSleeper: PDFExportTimeoutSleeping
private let fileManager: FileManager

init(
    timeout: Duration = .seconds(30),
    timeoutSleeper: PDFExportTimeoutSleeping = TaskPDFExportTimeoutSleeper(),
    fileManager: FileManager = .default
) {
    self.timeout = timeout
    self.timeoutSleeper = timeoutSleeper
    self.fileManager = fileManager
}
```

- [ ] 5. one-shotゲートを同じファイルへ追加する。

```swift
@MainActor
private final class PDFExportCompletionGate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var resolvedResult: Result<URL, Error>?

    func value() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            if let resolvedResult {
                continuation.resume(with: resolvedResult)
            } else {
                self.continuation = continuation
            }
        }
    }

    @discardableResult
    func resolve(_ result: Result<URL, Error>) -> Bool {
        guard case nil = resolvedResult else { return false }
        resolvedResult = result
        continuation?.resume(with: result)
        continuation = nil
        return true
    }
}
```

- [ ] 6. `exportWithTimeout`を追加する。TaskはいずれもMainActorを継承し、exporterのasync処理を待っている間はUI threadをブロックしない。

```swift
private func exportWithTimeout(
    document: ManuscriptDocument,
    subscriptionStatus: SubscriptionStatus,
    pdfExporter: PDFExportProducing
) async throws -> URL {
    let gate = PDFExportCompletionGate()

    let exportTask = Task { @MainActor in
        do {
            let url = try await pdfExporter.export(
                document: document,
                subscriptionStatus: subscriptionStatus
            )
            if !gate.resolve(.success(url)) {
                try? fileManager.removeItem(at: url)
            }
        } catch {
            _ = gate.resolve(.failure(error))
        }
    }

    let timeoutTask = Task { @MainActor in
        do {
            try await timeoutSleeper.sleep(for: timeout)
        } catch {
            return
        }
        if gate.resolve(.failure(PDFExportFlowError.timedOut)) {
            exportTask.cancel()
        }
    }

    defer {
        exportTask.cancel()
        timeoutTask.cancel()
    }
    return try await gate.value()
}
```

- [ ] 7. `exportAndShare`の直接export呼び出しを`exportWithTimeout`へ置換する。`defer { isExporting = false }`は残す。timeoutでthrowした場合、既存catchが`handleError`を呼ぶためad/share/storeは実行されない。

- [ ] 8. `FakePDFExportAdPresenter`はTask 5の作品ID変更前の現行signatureのままでこのタスクを通す。

- [ ] 9. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests
```

- [ ] 10. コミットする。

```bash
git add Honkumi/Shared/Services/PDFExportFlowCoordinator.swift \
  HonkumiTests/PDFExportFlowCoordinatorTests.swift
git commit -m "Stop stalled PDF exports after thirty seconds"
```

---

## Task 3: detached PDF生成へキャンセルを伝播する

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportService.swift`
- Create: `HonkumiTests/PDFExportCancellationTests.swift`

**Consumes:**

- Task 2が`PDFExportProducing.export`のTaskをcancelする

### Steps

- [ ] 1. 大量ページのdocumentでexport Taskを開始し、直後にcancelした時に`CancellationError`となり、既知の出力URLが残らない失敗テストを追加する。

- [ ] 2. 見開きpreview exportにも同じテストを追加する。

- [ ] 3. テストから出力先を固定できるよう、現在の`BodyPDFExportService.private export(document:subscriptionStatus:previewKind:to:)`をinternalへ変更する。製品のpublic APIは増やさず、`@testable import Honkumi`からだけ一時URLを指定する。

- [ ] 4. 現状は親Task cancellationがdetached Taskへ伝わらないため、短いpoll上限内に終了しないかファイルが残ることを確認する。

- [ ] 5. `PDFExportService.export`と`exportPreviewPDF`でdetached Task handleを保持し、親cancelを伝播する。

```swift
let task = Task.detached(priority: .userInitiated) {
    try exporter.export(document: document, subscriptionStatus: subscriptionStatus)
}
return try await withTaskCancellationHandler {
    try await task.value
} onCancel: {
    task.cancel()
}
```

- [ ] 6. `BodyPDFExportService`のinternal exportの開始、pagination後、書き込み前、normalize前後へ`try Task.checkCancellation()`を追加する。

- [ ] 7. normal PDFのrenderer actionはthrowing closureではないため、`var wasCancelled = false`を外側に置く。各ページの先頭で次を実行し、キャンセル後は追加ページを描かない。

```swift
guard !Task.isCancelled else {
    wasCancelled = true
    return
}
```

`writePDF`終了直後に:

```swift
if wasCancelled || Task.isCancelled {
    try? FileManager.default.removeItem(at: outputURL)
    throw CancellationError()
}
```

- [ ] 8. spread previewの見開きloopにも同じ確認を入れ、`writeSpreadPreviewPDF`からキャンセル状態をthrowできる形にする。

- [ ] 9. internal export全体を`do/catch`で囲み、通常描画error、cancellation、normalize errorのいずれでも`outputURL`を削除してから再throwする。成功時だけURLを返す。

- [ ] 10. 対象テストを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportCancellationTests \
  -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests
```

- [ ] 11. コミットする。

```bash
git add Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/PDFExportCancellationTests.swift
git commit -m "Cancel PDF rendering and remove partial output"
```

---

## Task 4: 画面側の出力状態が全終了経路で解除されることを固定する

**Files:**

- Modify: `Honkumi/ContentView.swift`
- Modify: `HonkumiTests/PDFExportFlowCoordinatorTests.swift`

### Steps

- [ ] 1. coordinatorの返り値を利用しなくても、success shareとerror handlerの双方で`isExportingPDF = false`になる現状を確認する。

- [ ] 2. timeout testでerror handlerが1回呼ばれた直後、同じcoordinatorの2回目が`true`を返して開始されることを明示的にassertする。これが出力ボタン解放のサービス境界テストになる。

- [ ] 3. `ContentView.exportPDF`で、`storeGeneratedURL`はsuccess後だけ、`share`/`handleError`の双方が`isExportingPDF = false`を実行する現行構造を保持する。追加のcleanup Taskは置かず、coordinatorの全終了経路が必ずこの2クロージャのどちらかへ到達することをflow testsで固定する。

- [ ] 4. `CancellationError`がアプリの能動的画面破棄由来の場合とtimeout由来を混同しない。timeoutは必ず`PDFExportFlowError.timedOut`として表示する。

- [ ] 5. Debugビルドとflow testsを実行してコミットする。コード変更がなければコミットは作らない。

---

## Task 5: 未対応絵文字を白い四角1文字へ統一する

**Files:**

- Modify: `Honkumi/Shared/Services/PrintTextNormalizer.swift`
- Create: `HonkumiTests/PrintTextNormalizerTests.swift`

### Steps

- [ ] 1. 次の失敗テストを追加する。

```swift
final class PrintTextNormalizerTests: XCTestCase {
    func testUnsupportedEmojiBecomesOneWhiteSquareWithoutCross() {
        let result = PrintTextNormalizer.normalize("前😀後", location: nil)

        XCTAssertEqual(result.text, "前□後")
        XCTAssertFalse(result.text.contains("×"))
        XCTAssertEqual(result.replacements.count, 1)
        XCTAssertEqual(result.replacements[0].replacement, "□")
        XCTAssertEqual(result.replacements[0].kind, .unsupportedEmoji)
    }

    func testHeartReplacementRemainsOpenHeart() {
        XCTAssertEqual(
            PrintTextNormalizer.normalize("❤️", location: nil).text,
            "♡"
        )
    }

    func testReportSampleUsesSingleSquare() {
        let report = PrintTextNormalizer.report(
            title: "題😀",
            body: "本文",
            colophon: .default
        )
        XCTAssertEqual(report.unsupportedEmojiReplacementCount, 1)
        XCTAssertTrue(report.sampleLocations.contains("😀→□"))
        XCTAssertFalse(report.sampleLocations.contains("×"))
    }
}
```

- [ ] 2. 現在の`□×`で失敗することを確認する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PrintTextNormalizerTests
```

- [ ] 3. 共通定数だけを変更する。

```swift
static let unsupportedEmojiReplacement = "□"
```

作品名、本文、奥付、プリフライトreport、プレビュー、PDFは既に`normalizedDocument`/`report`を共有しているため、個別置換を追加しない。

- [ ] 4. title/body/全colophon text fieldで同じ置換になるparameterized testを追加する。

- [ ] 5. 対象テストとManuscriptRenderPipeline関連テストを実行する。

- [ ] 6. コミットする。

```bash
git add Honkumi/Shared/Services/PrintTextNormalizer.swift \
  HonkumiTests/PrintTextNormalizerTests.swift
git commit -m "Replace unsupported emoji with one square"
```

---

## Task 6: timeoutの実時間境界と全体回帰を確認する

**Files:**

- No source changes expected

### Steps

- [ ] 1. 単体テストではmanual sleeperを使い、`.seconds(30)`が渡ること、29.999秒相当のsuccessが採用され、timeout発火が後から無視されることを確認する。

- [ ] 2. Debug専用の遅延fakeまたはテストscheme引数で31秒以上生成を保留し、Simulatorでexact message、広告なし、共有なし、ボタン再有効化を目視確認する。製品コードへ恒久的なsleepを残さない。

- [ ] 3. timeout errorを閉じ、同じ作品ですぐ再出力してsuccess/shareへ進むことを確認する。

- [ ] 4. 全関連テストとDebugビルドを実行する。

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' \
  test -only-testing:HonkumiTests/PDFExportFlowCoordinatorTests \
  -only-testing:HonkumiTests/PDFExportCancellationTests \
  -only-testing:HonkumiTests/PrintTextNormalizerTests
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi -configuration Debug \
  -destination 'platform=iOS Simulator,id=6C9E009C-5004-4C8D-8627-753D6CE09EBF' build
```

## Completion Evidence

- timeoutは`.seconds(30)`で、広告/共有前にだけ適用される。
- timeout後の遅延URLと部分ファイルが削除される。
- error後に同じcoordinatorと同じ作品で直ちに再試行できる。
- 未対応絵文字の出力とreplacement reportが`□`1文字で一致する。

# SVG Circle Logo Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let paid users upload raster images or SVG circle logos through one button and a centered rounded source alert, converting SVG once to a transparent high-resolution PNG for all existing preview and PDF paths.

**Architecture:** Extend `CircleLogoImageImporter` with a content-type-aware import boundary: raster bytes are validated and preserved, while SVG bytes are decoded with the system image decoder and rendered to a transparent PNG whose long edge is 2048 pixels. Keep `CircleLogoImportPresentation` as the exclusive modal state machine and replace the adaptive `confirmationDialog` with a native centered `alert`.

**Tech Stack:** Swift 6, SwiftUI, UIKit, PhotosUI, UniformTypeIdentifiers, XCTest, Xcode 26

## Global Constraints

- Minimum deployment target remains iOS 26.2.
- Do not add third-party SVG libraries or any other dependency.
- The paid logo row has one visible source-entry button named exactly `アップロード`.
- Show exactly `ロゴはモノクロを推奨します。` directly below that button in small secondary text.
- The source chooser uses a native centered rounded alert, not `confirmationDialog` or a popover.
- Source actions are exactly `写真から選択`, `ファイルから選択`, and `キャンセル`.
- The file importer explicitly allows `UTType.svg` in addition to image types.
- Raster PNG/JPEG/HEIC data remains byte-for-byte unchanged after successful validation.
- SVG is converted at upload time only; preview and PDF generation must not re-convert it.
- SVG output is PNG with a transparent-capable bitmap, long edge at most 2048 pixels, and short edge at least 1 pixel.
- Preserve SVG aspect ratio except for the unavoidable one-pixel minimum on extreme aspect ratios.
- A cancelled photo or file picker does not show an error and does not change the stored logo.
- Read, security-scope, validation, decode, dimension, and PNG-render failures preserve the stored logo and show `画像を読み込めませんでした` with the localized reason.
- Keep `CircleLogoImportPresentation`'s stale-dismiss protection.
- Existing `circleImageData`, preview, preflight, and PDF drawing interfaces remain unchanged.
- Preserve unrelated and currently untracked documents and scripts.
- New Swift files are automatically included by File System Synchronized Groups; do not edit `project.pbxproj`.
- Do not run the all-paper-size or all-font-size sample PDF batches.
- Use RED/GREEN test cycles and commit every independently reviewable task.

---

### Task 1: Convert SVG bytes to transparent 2048-pixel PNG data

**Files:**

- Modify: `Honkumi/Shared/Services/CircleLogoImageImporter.swift`
- Modify: `HonkumiTests/CircleLogoImageImporterTests.swift`

**Interfaces:**

- Produces: `CircleLogoImageImporter.importedImageData(_:contentType:)`.
- Changes: `loadImageData(from:)` to resolve URL content type and route through `importedImageData`.
- Preserves: `validatedImageData(_:)` for photo-picker raster validation.

- [ ] **Step 1: Write failing SVG and raster-boundary tests**

Add `UniformTypeIdentifiers` to `CircleLogoImageImporterTests` and add:

```swift
func testImportedRasterImageKeepsOriginalBytes() throws {
    let image = UIGraphicsImageRenderer(
        size: CGSize(width: 4, height: 3)
    ).image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
    }
    let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.77))

    XCTAssertEqual(
        try CircleLogoImageImporter.importedImageData(
            data,
            contentType: .jpeg
        ),
        data
    )
}

func testSVGConvertsToPNGWith2048PixelLongEdge() throws {
    let data = Data(Self.transparentSVG.utf8)

    let pngData = try CircleLogoImageImporter.importedImageData(
        data,
        contentType: .svg
    )
    let image = try XCTUnwrap(UIImage(data: pngData))
    let cgImage = try XCTUnwrap(image.cgImage)

    XCTAssertEqual(cgImage.width, 1024)
    XCTAssertEqual(cgImage.height, 2048)
    XCTAssertEqual(Array(pngData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    XCTAssertTrue(
        [
            CGImageAlphaInfo.premultipliedFirst,
            .premultipliedLast,
            .first,
            .last
        ].contains(cgImage.alphaInfo)
    )
}

func testExtremeSVGAspectRatioKeepsShortEdgeAtLeastOnePixel() throws {
    let data = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" width="1" height="100000">
      <rect width="1" height="100000" fill="#000000"/>
    </svg>
    """.utf8)

    let pngData = try CircleLogoImageImporter.importedImageData(
        data,
        contentType: .svg
    )
    let cgImage = try XCTUnwrap(UIImage(data: pngData)?.cgImage)

    XCTAssertEqual(cgImage.width, 1)
    XCTAssertEqual(cgImage.height, 2048)
}

func testInvalidSVGThrowsSpecificImportError() {
    XCTAssertThrowsError(
        try CircleLogoImageImporter.importedImageData(
            Data("<svg width=\"0\" height=\"0\"></svg>".utf8),
            contentType: .svg
        )
    ) { error in
        XCTAssertEqual(
            error as? CircleLogoImageImportError,
            .invalidSVG
        )
    }
}

private static let transparentSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="10" height="20">
  <rect x="0" y="0" width="5" height="20" fill="#000000"/>
</svg>
"""
```

- [ ] **Step 2: Run importer tests and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests test
```

Expected: compilation fails because `.invalidSVG` and `importedImageData(_:contentType:)` do not exist.

- [ ] **Step 3: Add content-type-aware validation**

Import `UniformTypeIdentifiers` in `CircleLogoImageImporter.swift`. Extend the error:

```swift
nonisolated enum CircleLogoImageImportError: LocalizedError, Equatable {
    case invalidImage
    case invalidSVG
    case svgConversionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "選択したファイルを画像として読み込めませんでした。"
        case .invalidSVG:
            "選択したSVGのサイズまたは内容を読み込めませんでした。"
        case .svgConversionFailed:
            "選択したSVGをPNG画像へ変換できませんでした。"
        }
    }
}
```

Add:

```swift
static func importedImageData(
    _ data: Data,
    contentType: UTType?
) throws -> Data {
    if contentType?.conforms(to: .svg) == true {
        return try pngData(fromSVG: data)
    }
    return try validatedImageData(data)
}
```

- [ ] **Step 4: Render SVG with an explicit transparent one-scale bitmap**

Add:

```swift
private static let maximumSVGPixelDimension: CGFloat = 2048

private static func pngData(fromSVG data: Data) throws -> Data {
    guard let image = UIImage(data: data) else {
        throw CircleLogoImageImportError.invalidSVG
    }
    let sourceSize = image.size
    guard sourceSize.width.isFinite,
          sourceSize.height.isFinite,
          sourceSize.width > 0,
          sourceSize.height > 0 else {
        throw CircleLogoImageImportError.invalidSVG
    }

    let scale = maximumSVGPixelDimension /
        max(sourceSize.width, sourceSize.height)
    let pixelWidth = max(
        Int((sourceSize.width * scale).rounded()),
        1
    )
    let pixelHeight = max(
        Int((sourceSize.height * scale).rounded()),
        1
    )
    let targetSize = CGSize(width: pixelWidth, height: pixelHeight)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    format.preferredRange = .standard
    let renderer = UIGraphicsImageRenderer(
        size: targetSize,
        format: format
    )
    let rendered = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let pngData = rendered.pngData(),
          UIImage(data: pngData)?.cgImage != nil else {
        throw CircleLogoImageImportError.svgConversionFailed
    }
    return pngData
}
```

The renderer always emits a long edge of 2048 for a valid SVG, so it also satisfies the at-most-2048 requirement.

- [ ] **Step 5: Detect SVG when loading a security-scoped file URL**

Inside `loadImageData(from:)`, after reading bytes, determine the type:

```swift
let values = try? url.resourceValues(forKeys: [.contentTypeKey])
let filenameType = UTType(
    filenameExtension: url.pathExtension.lowercased()
)
let contentType =
    filenameType?.conforms(to: .svg) == true
        ? filenameType
        : values?.contentType ?? filenameType
return try importedImageData(data, contentType: contentType)
```

Keep `startAccessingSecurityScopedResource` and its `defer` unchanged. Use one `Data(contentsOf:)` read and one conversion only.

- [ ] **Step 6: Run importer tests**

Run the Step 2 command again.

Expected: raster, valid SVG, aspect-ratio, invalid SVG, and existing file-copy tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add Honkumi/Shared/Services/CircleLogoImageImporter.swift \
  HonkumiTests/CircleLogoImageImporterTests.swift
git commit -m "Convert SVG circle logos to PNG"
```

---

### Task 2: Centralize source-chooser copy, file types, and cancellation detection

**Files:**

- Modify: `Honkumi/Features/Settings/CircleLogoImportPresentation.swift`
- Modify: `Honkumi/Shared/Services/CircleLogoImageImporter.swift`
- Modify: `HonkumiTests/CircleLogoImportPresentationTests.swift`
- Modify: `HonkumiTests/CircleLogoImageImporterTests.swift`

**Interfaces:**

- Produces: `CircleLogoImportCopy` constants used directly by the view.
- Produces: `CircleLogoImportFileTypes.allowed`.
- Produces: `CircleLogoImageImporter.isCancellation(_:)`.

- [ ] **Step 1: Write failing copy and allowed-type tests**

Add to `CircleLogoImportPresentationTests`:

```swift
import UniformTypeIdentifiers

func testApprovedCircleLogoCopy() {
    XCTAssertEqual(CircleLogoImportCopy.uploadButton, "アップロード")
    XCTAssertEqual(
        CircleLogoImportCopy.monochromeRecommendation,
        "ロゴはモノクロを推奨します。"
    )
    XCTAssertEqual(CircleLogoImportCopy.photoSource, "写真から選択")
    XCTAssertEqual(CircleLogoImportCopy.fileSource, "ファイルから選択")
    XCTAssertEqual(CircleLogoImportCopy.cancel, "キャンセル")
}

func testFileTypesExplicitlyContainImageAndSVG() {
    XCTAssertTrue(CircleLogoImportFileTypes.allowed.contains(.image))
    XCTAssertTrue(CircleLogoImportFileTypes.allowed.contains(.svg))
}
```

Add to `CircleLogoImageImporterTests`:

```swift
func testCancellationErrorsAreRecognized() {
    XCTAssertTrue(
        CircleLogoImageImporter.isCancellation(CancellationError())
    )
    XCTAssertTrue(
        CircleLogoImageImporter.isCancellation(
            NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.Code.userCancelled.rawValue
            )
        )
    )
    XCTAssertFalse(
        CircleLogoImageImporter.isCancellation(
            CircleLogoImageImportError.invalidImage
        )
    )
}
```

- [ ] **Step 2: Run both focused test classes and verify RED**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests test
```

Expected: compilation fails because the copy, file-type, and cancellation helpers do not exist.

- [ ] **Step 3: Add copy and file-type constants**

In `CircleLogoImportPresentation.swift`, import `UniformTypeIdentifiers` and add:

```swift
nonisolated enum CircleLogoImportCopy {
    static let sourceTitle = "サークルロゴの選択方法"
    static let sourceMessage = "アップロード元を選択してください。"
    static let uploadButton = "アップロード"
    static let monochromeRecommendation =
        "ロゴはモノクロを推奨します。"
    static let photoSource = "写真から選択"
    static let fileSource = "ファイルから選択"
    static let cancel = "キャンセル"
}

nonisolated enum CircleLogoImportFileTypes {
    static let allowed: [UTType] = [.image, .svg]
}
```

- [ ] **Step 4: Add cancellation classification**

In `CircleLogoImageImporter` add:

```swift
static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    let error = error as NSError
    return error.domain == NSCocoaErrorDomain &&
        error.code == CocoaError.Code.userCancelled.rawValue
}
```

- [ ] **Step 5: Run copy/type/cancellation tests**

Run the Step 2 command again.

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add Honkumi/Features/Settings/CircleLogoImportPresentation.swift \
  Honkumi/Shared/Services/CircleLogoImageImporter.swift \
  HonkumiTests/CircleLogoImportPresentationTests.swift \
  HonkumiTests/CircleLogoImageImporterTests.swift
git commit -m "Define circle logo import boundaries"
```

---

### Task 3: Replace the source popover with one upload button and centered alert

**Files:**

- Modify: `Honkumi/Features/Settings/ColophonSettingsView.swift`

**Interfaces:**

- Consumes: Task 2's copy and allowed types.
- Preserves: `CircleLogoImportPresentation` as the only photo/file presentation state.
- Produces: paid row copy and centered native alert.

- [ ] **Step 1: Replace the adaptive confirmation dialog**

Delete the complete `.confirmationDialog("サークルロゴの選択方法", …)` modifier from `ColophonSettingsView`.

Add:

```swift
.alert(
    CircleLogoImportCopy.sourceTitle,
    isPresented: circleLogoPresentationBinding(for: .sourceChooser)
) {
    Button(CircleLogoImportCopy.photoSource) {
        circleLogoImportPresentation.present(.photoLibrary)
    }
    Button(CircleLogoImportCopy.fileSource) {
        circleLogoImportPresentation.present(.fileImporter)
    }
    Button(CircleLogoImportCopy.cancel, role: .cancel) {}
} message: {
    Text(CircleLogoImportCopy.sourceMessage)
}
```

The existing destination-aware `dismiss(_:)` guard must remain unchanged so the old alert's dismissal callback cannot clear a newly selected picker.

- [ ] **Step 2: Explicitly allow SVG files**

Change the file importer to:

```swift
.fileImporter(
    isPresented: circleLogoPresentationBinding(for: .fileImporter),
    allowedContentTypes: CircleLogoImportFileTypes.allowed,
    allowsMultipleSelection: false,
    onCompletion: handleCircleImageFileImport
)
```

- [ ] **Step 3: Update the paid upload row copy and layout**

Replace the paid button label with:

```swift
VStack(alignment: .leading, spacing: 4) {
    Button {
        circleLogoImportPresentation.present(.sourceChooser)
    } label: {
        Label(
            CircleLogoImportCopy.uploadButton,
            systemImage: "photo.on.rectangle"
        )
    }
    .accessibilityIdentifier("colophon.circleLogo.select")

    Text(CircleLogoImportCopy.monochromeRecommendation)
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

Keep the current preview on the left, delete button on the right, paid entitlement check, and unpaid purchase route unchanged.

- [ ] **Step 4: Suppress cancellation alerts and preserve existing data**

In both photo and file catch blocks:

```swift
} catch {
    guard !CircleLogoImageImporter.isCancellation(error) else {
        return
    }
    circleImageImportErrorMessage = error.localizedDescription
}
```

Do not clear `circleImageData` before loading. Assign the returned data only inside the successful branch:

```swift
viewModel.updateColophon { colophon in
    colophon.circleImageData = data
}
```

For the file importer result, a successful empty URL array is treated like cancellation and returns without an alert.

- [ ] **Step 5: Run logo tests and Debug build**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImportPresentationTests \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests test

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: tests pass, Debug builds, and no `confirmationDialog` remains in `ColophonSettingsView`.

- [ ] **Step 6: Commit Task 3**

```bash
git add Honkumi/Features/Settings/ColophonSettingsView.swift
git commit -m "Center circle logo source selection"
```

---

### Task 4: Verify converted PNG compatibility with preview, preflight, and PDF drawing

**Files:**

- Modify: `HonkumiTests/CircleLogoImageImporterTests.swift`
- Modify only if a regression is found: `Honkumi/Shared/Services/PDFPreflightService.swift`
- Modify only if a regression is found: `Honkumi/Shared/Services/PDFExportService.swift`

**Interfaces:**

- Verifies the unchanged `circleImageData` consumer boundary.

- [ ] **Step 1: Add a converted-data compatibility test**

Add to `CircleLogoImageImporterTests`:

```swift
func testConvertedSVGDataSupportsExistingUIImageAndCGImageConsumers() throws {
    let pngData = try CircleLogoImageImporter.importedImageData(
        Data(Self.transparentSVG.utf8),
        contentType: .svg
    )

    let uiImage = try XCTUnwrap(UIImage(data: pngData))
    let cgImage = try XCTUnwrap(uiImage.cgImage)

    XCTAssertEqual(cgImage.width, 1024)
    XCTAssertEqual(cgImage.height, 2048)
    XCTAssertNotNil(uiImage.pngData())
}
```

This directly covers the existing preview (`UIImage(data:)`), preflight (`image.cgImage`), and PDF (`UIImage(data:)`) decode boundaries without adding conversion work to any of them.

- [ ] **Step 2: Run importer and preflight regressions**

Run:

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/CircleLogoImageImporterTests \
  -only-testing:HonkumiTests/PDFPreflightEmojiWarningTests \
  -only-testing:HonkumiTests/PDFPreflightChapterHeaderTests test
```

Expected: all selected tests pass. No changes to preview, preflight, or PDF source files are expected because the saved data is now ordinary PNG.

- [ ] **Step 3: Search for accidental runtime SVG conversion**

Run:

```bash
rg -n "pngData\\(fromSVG|importedImageData|UTType\\.svg" Honkumi
```

Expected: conversion appears only in `CircleLogoImageImporter` and file-type/UI wiring; preview and PDF paths continue to decode `circleImageData` directly.

- [ ] **Step 4: Commit the compatibility test**

```bash
git add HonkumiTests/CircleLogoImageImporterTests.swift
git commit -m "Verify converted logo image compatibility"
```

---

### Task 5: Verify failure preservation and all build configurations

**Files:**

- No source changes expected.
- Modify only files from Tasks 1–4 if a reproducible regression is found.

**Interfaces:**

- Verifies visible copy, modal behavior, transparent output, and release builds.

- [ ] **Step 1: Run the complete XCTest suite**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build Debug, Staging, and Release**

```bash
xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' build

xcodebuild -project Honkumi.xcodeproj -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: all three builds succeed.

- [ ] **Step 3: Manually verify the paid logo UI**

1. Open default publisher information while Pro is unlocked.
2. Turn on circle-logo use and verify the only source-entry button is `アップロード`.
3. Verify `ロゴはモノクロを推奨します。` is directly below the button.
4. Tap `アップロード` and verify a centered rounded alert—not a bubble/popover—offers the three approved actions.
5. Repeat on iPhone and iPad simulator sizes to confirm the alert stays centered.

- [ ] **Step 4: Manually verify PNG, JPEG, and SVG imports**

1. Select a PNG from Files and verify its preview appears.
2. Replace it with a JPEG and verify the preview updates.
3. Replace it with a transparent SVG and verify transparent areas remain transparent in the preview and generated PDF.
4. Export one ordinary PDF and visually verify the converted logo is sharp and keeps its aspect ratio.
5. Do not run an all-paper-size or all-font-size PDF batch.

- [ ] **Step 5: Manually verify cancellation and failure preservation**

1. Store a valid logo, open the photo picker, and cancel; verify the logo remains and no error appears.
2. Open the file picker and cancel; verify the same.
3. Select malformed SVG and non-image bytes; verify the old logo remains.
4. Verify each real failure shows `画像を読み込めませんでした` and a localized reason.

- [ ] **Step 6: Record final evidence**

Include focused tests, complete-suite output, all three build results, one converted PNG dimension check, one PDF screenshot, and cancellation/failure outcomes in the implementation handoff.

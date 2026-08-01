# PDF/X-4 Metadata Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize Honkumi's populated Document Info and XMP fields, normalize both producers to `Honkumi`, emit the requested PDF/X-4 identifier, and prove page rendering and print-production structures are unchanged.

**Architecture:** Build one immutable metadata value per export and use it to generate both renderer Info values and canonical XMP. Pass the same value into the existing byte-level finalizer so it repairs only the Info entries Quartz can override while copying every non-Info object body unchanged.

**Tech Stack:** Swift 6, Foundation, Core Graphics, PDFKit, UIKit, XCTest, Xcode, bundled Python/pypdf, Poppler `pdfinfo` and `pdftoppm`

## Global Constraints

- Treat `docs/superpowers/specs/2026-08-01-pdf-x4-metadata-sync-design.md` as the source of truth.
- Keep Info `/Author` and XMP `dc:creator` both absent.
- Do not copy colophon author name, circle name, contact information, or URLs into Info or XMP.
- Synchronize only metadata fields that the current export already populates on one or both sides.
- Normalize Info `/Producer` and XMP `pdf:Producer` to exactly `Honkumi`.
- Emit exactly one `pdfxid:GTS_PDFXVersion="PDF/X-4"` and no `pdfxid:GTS_PDFXConformance`.
- Keep the current Output Intent and Generic CMYK ICC profile unchanged when validation passes.
- Do not change page geometry, crop-mark geometry, pagination, vertical typesetting, drawing, font selection, embedding, or subsetting.
- Preserve unrelated working-tree edits, deleted artifacts, untracked output, and the user's current project-file changes.
- Do not add a new production source file or modify `Honkumi.xcodeproj/project.pbxproj`.
- Do not claim complete PDF/X-4 conformance without a PDF/X-4 product preflight.

## File Structure

- Modify `Honkumi/Shared/Services/PDFPrintProduction.swift`
  - Owns the immutable PDF/X-4 metadata value, date formatting, Document Info input, and canonical XMP construction.
- Modify `Honkumi/Shared/Services/PDFExportService.swift`
  - Creates one metadata value per export and passes it to normal/spread rendering and finalization without changing drawing.
- Modify `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift`
  - Normalizes mapped Info entries from the immutable value while preserving non-Info objects.
- Modify `HonkumiTests/PDFX4StructureFinalizerTests.swift`
  - Covers Info replacement/insertion, Unicode strings, dates, Producer normalization, duplicate entries, and atomic failure.
- Modify `HonkumiTests/PDFX4GeneratedPDFTests.swift`
  - Checks generated Info/XMP equality, PDF/X identification, Output Intent, ICC, fonts, encryption, and privacy omissions.
- Modify `HonkumiTests/PDFX4TestSupport.swift`
  - Extends XMP, Info, Output Intent, date, finalizer-capture, and artifact inspection helpers.
- Modify `HonkumiTests/PrintSettingSamplePDFTests.swift`
  - Adds A6, B6, and shinsho crop-mark finalization regressions.

---

### Task 1: Build Canonical Metadata and XMP from One Value

**Files:**

- Modify: `Honkumi/Shared/Services/PDFPrintProduction.swift:72-201`
- Modify: `HonkumiTests/PDFX4GeneratedPDFTests.swift:1-85`
- Modify: `HonkumiTests/PDFX4TestSupport.swift:1145-1210`

**Interfaces:**

- Produces: `PDFX4DocumentMetadata.make(title:documentID:exportedAt:instanceID:)`
- Produces: immutable properties `title`, `author`, `subject`, `keywords`, `creatorTool`, `producer`, `creationDate`, `modificationDate`, `documentID`, and `instanceID`
- Produces: `PDFX4DocumentMetadata.pdfDateString(_:) -> String`
- Produces: `PDFX4DocumentMetadata.xmpDateString(_:) -> String`
- Produces: `PDFX4ProductionProfile.documentInfo(for:) -> [String: Any]`
- Produces: `PDFX4ProductionProfile.xmpMetadataData(for:) -> Data`
- Preserves temporarily: the old `documentInfo(title:)` and `xmpMetadataData(title:documentID:createdAt:)` entry points so production compiles until Task 3

- [ ] **Step 1: Add a failing canonical-XMP test**

Name the production breaks: independently captured timestamps, missing Subject/Keywords/ModifyDate, duplicate or wrong PDF/X identifiers, or accidental author creation.

Expose a test-only XMP parser as `PDFX4TestInspector.inspectXMP(_:)` and add this test to `PDFX4GeneratedPDFTests.swift` before adding the production type:

```swift
func testCanonicalMetadataBuildsCompleteSynchronizedXMPWithoutAuthor() throws {
    let exportedAt = Date(timeIntervalSince1970: 1_785_888_496.875)
    let metadata = PDFX4DocumentMetadata.make(
        title: "題名 & <確認>",
        documentID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        exportedAt: exportedAt,
        instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )

    let xmp = try PDFX4TestInspector.inspectXMP(
        PDFPrintProduction.pdfX4Profile.xmpMetadataData(for: metadata)
    )

    XCTAssertEqual(metadata.creationDate.timeIntervalSince1970, 1_785_888_496)
    XCTAssertEqual(metadata.modificationDate, metadata.creationDate)
    XCTAssertEqual(xmp.title, "題名 & <確認>")
    XCTAssertEqual(xmp.description, "Print-ready PDF generated by Honkumi")
    XCTAssertEqual(xmp.keywords, "print, novel, Honkumi")
    XCTAssertEqual(xmp.creatorTool, "Honkumi")
    XCTAssertEqual(xmp.producer, "Honkumi")
    XCTAssertEqual(xmp.creatorCount, 0)
    XCTAssertEqual(xmp.pdfXVersionCount, 1)
    XCTAssertEqual(xmp.pdfXConformanceCount, 0)
    XCTAssertEqual(xmp.createDate, "2026-08-05T00:08:16Z")
    XCTAssertEqual(xmp.modifyDate, xmp.createDate)
    XCTAssertEqual(xmp.metadataDate, xmp.modifyDate)
}
```

The epoch above is the hand-checked UTC value for `2026-08-05T00:08:16Z`.
Do not derive the expected string with production formatters.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests/testCanonicalMetadataBuildsCompleteSynchronizedXMPWithoutAuthor \
  test
```

Expected: build failure because `PDFX4DocumentMetadata`, `xmpMetadataData(for:)`, and the expanded XMP snapshot do not exist.

- [ ] **Step 3: Add the immutable metadata value**

Add this shape in `PDFPrintProduction.swift`, keeping it in the existing file so the dirty Xcode project file is untouched:

```swift
nonisolated struct PDFX4DocumentMetadata: Equatable, Sendable {
    let title: String
    let author: String?
    let subject: String
    let keywords: String
    let creatorTool: String
    let producer: String
    let creationDate: Date
    let modificationDate: Date
    let documentID: UUID
    let instanceID: UUID

    static func make(
        title: String,
        documentID: UUID,
        exportedAt: Date = Date(),
        instanceID: UUID = UUID()
    ) -> PDFX4DocumentMetadata {
        let wholeSecond = Date(
            timeIntervalSince1970: floor(exportedAt.timeIntervalSince1970)
        )
        return PDFX4DocumentMetadata(
            title: title,
            author: nil,
            subject: "Print-ready PDF generated by Honkumi",
            keywords: "print, novel, Honkumi",
            creatorTool: "Honkumi",
            producer: "Honkumi",
            creationDate: wholeSecond,
            modificationDate: wholeSecond,
            documentID: documentID,
            instanceID: instanceID
        )
    }
}
```

Implement `pdfDateString(_:)` with an `en_US_POSIX` Gregorian formatter in UTC and format `D:yyyyMMddHHmmssZ`. Implement `xmpDateString(_:)` with `ISO8601DateFormatter` using `.withInternetDateTime` and UTC, with no fractional seconds.

- [ ] **Step 4: Generate canonical XMP and renderer Info from the value**

Add `documentInfo(for:)` and `xmpMetadataData(for:)`. Use the metadata value for every mapped field and retain the existing Output Intent injection. The XMP must have this semantic shape:

```xml
<rdf:Description rdf:about=""
  xmlns:pdfxid="http://www.npes.org/pdfx/ns/id/"
  pdfxid:GTS_PDFXVersion="PDF/X-4" />
<rdf:Description rdf:about=""
  xmlns:pdf="http://ns.adobe.com/pdf/1.3/"
  pdf:Producer="Honkumi"
  pdf:Keywords="print, novel, Honkumi" />
<rdf:Description rdf:about=""
  xmlns:xmp="http://ns.adobe.com/xap/1.0/"
  xmp:CreatorTool="Honkumi"
  xmp:CreateDate="2026-08-05T00:08:16Z"
  xmp:ModifyDate="2026-08-05T00:08:16Z"
  xmp:MetadataDate="2026-08-05T00:08:16Z" />
```

Keep `dc:format` and `dc:title`. Add `dc:description` as an `rdf:Alt` with one `x-default` item. Emit a `dc:creator` `rdf:Seq` only when `author` is non-nil and non-empty; the production factory always supplies nil. Escape every interpolated XML value with the existing `xmlEscaped` helper.

Make `xmpMetadataData(for:)` return non-optional `Data` with `Data(xmp.utf8)`. Do not remove the legacy entry points until Task 3.

- [ ] **Step 5: Expand the XMP test parser and verify GREEN**

Expand `PDFXMPTestSnapshot` and its XML delegate to capture:

```swift
struct PDFXMPTestSnapshot {
    let pdfXVersionCount: Int
    let pdfXConformanceCount: Int
    let title: String
    let description: String
    let keywords: String
    let creatorTool: String
    let producer: String
    let createDate: String
    let modifyDate: String
    let metadataDate: String
    let creatorCount: Int
}
```

Count every `dc:creator` element, capture `dc:title` and `dc:description` default-language text independently, and capture the `pdf:*` and `xmp:*` attributes. Run the Step 2 command again.

Expected: PASS with one PDF/X version, zero conformance identifiers, no creator, and all mapped XMP values present.

- [ ] **Step 6: Commit the canonical metadata cycle**

```bash
git diff --check -- \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Add canonical PDF X-4 metadata"
```

---

### Task 2: Normalize Document Info After Quartz Rendering

**Files:**

- Modify: `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift:82-161,1034-1133`
- Modify: `HonkumiTests/PDFX4StructureFinalizerTests.swift:1-278`
- Modify: `HonkumiTests/PDFX4TestSupport.swift:1-340`

**Interfaces:**

- Produces: `PDFX4StructureFinalizer.finalizedData(from:metadata:) throws -> Data`
- Produces: `PDFX4StructureFinalizer.finalize(at:metadata:) throws`
- Produces: `PDFInfoDictionaryNormalizer.normalized(in:metadata:) throws -> Data`
- Preserves: `finalizedData(from:)` and `finalize(at:)` for structural-only tests
- Preserves: every non-Info object body byte-for-byte

- [ ] **Step 1: Add failing Producer, dates, Unicode, and absence tests**

Extend the synthetic fixture builder so object 3 can be created with this Info body:

```pdf
<< /Title (Old) /Producer (iOS Version 26.5 Quartz PDFContext)
   /Creator (Old Tool) /CreationDate (D:20000101000000Z)
   /ModDate (D:20000101000000Z) >>
```

Add a test that calls the new overload with fixed metadata and uses Core Graphics to inspect the rebuilt Info dictionary:

```swift
func testMetadataFinalizationSynchronizesInfoWithoutCreatingAuthor() throws {
    let metadata = PDFX4DocumentMetadata.make(
        title: "日本語の題名",
        documentID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        exportedAt: Date(timeIntervalSince1970: 1_785_888_496),
        instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )
    let output = try PDFX4StructureFinalizer.finalizedData(
        from: PDFTestFixtureBuilder.malformedQuartzStylePDF(
            infoEntries: " /Title (Old) /Producer (iOS Version 26.5 Quartz PDFContext)"
                + " /Creator (Old Tool) /CreationDate (D:20000101000000Z)"
                + " /ModDate (D:20000101000000Z)"
        ),
        metadata: metadata
    )
    let info = try PDFX4TestInspector.infoStrings(in: output)

    XCTAssertEqual(info["Title"], "日本語の題名")
    XCTAssertEqual(info["Subject"], "Print-ready PDF generated by Honkumi")
    XCTAssertEqual(info["Keywords"], "print, novel, Honkumi")
    XCTAssertEqual(info["Creator"], "Honkumi")
    XCTAssertEqual(info["Producer"], "Honkumi")
    XCTAssertEqual(info["CreationDate"], "D:20260805000816Z")
    XCTAssertEqual(info["ModDate"], "D:20260805000816Z")
    XCTAssertNil(info["Author"])
}
```

Also add one test with duplicate `/Producer` entries and require `.invalidInfoDictionary`, and keep the existing `/Trapped /False` name-object assertion.

- [ ] **Step 2: Run the finalizer tests and verify RED**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4StructureFinalizerTests \
  test
```

Expected: build failure because the metadata-aware finalizer overload and Info inspection helper do not exist.

- [ ] **Step 3: Add safe PDF text-string encoding**

Encode every synchronized Info text value as a UTF-16BE hexadecimal PDF text string with a `FEFF` byte-order mark. Implement a helper that appends each UTF-16 code unit in big-endian order and serializes uppercase hexadecimal between `<` and `>`. This prevents literal-string escaping defects and round-trips Japanese text through Core Graphics.

Use text strings for `Title`, optional `Author`, `Subject`, `Keywords`, `Creator`, `Producer`, `CreationDate`, and `ModDate`. Keep `/Trapped /False` as a PDF Name Object.

- [ ] **Step 4: Generalize the top-level Info normalizer**

Change the existing entry parser to reject duplicate synchronized names from this set:

```swift
let synchronizedNames: Set<String> = [
    "Title", "Author", "Subject", "Keywords", "Creator", "Producer",
    "CreationDate", "ModDate", "Trapped"
]
```

Build replacements for every populated metadata field plus `Trapped`. Do not include `Author` when `metadata.author == nil`; because the renderer input also omits Author, the production Info remains absent.

Insert missing populated entries immediately before the top-level `>>`. Replace existing values from highest source offset to lowest so recorded ranges remain valid. Reject duplicate mapped entries rather than choosing one.

- [ ] **Step 5: Add metadata-aware rebuild and atomic file overloads**

Refactor the rebuild into a private function that accepts `PDFX4DocumentMetadata?`:

```swift
static func finalizedData(from source: Data) throws -> Data {
    try finalizedData(from: source, metadata: nil)
}

static func finalizedData(
    from source: Data,
    metadata: PDFX4DocumentMetadata
) throws -> Data {
    try rebuild(source, metadata: metadata)
}
```

When metadata is nil, preserve the current trapped-only behavior used by structure tests. When it is present, call `normalized(in:metadata:)`. Add matching `finalize(at:metadata:)` that validates and reopens the output before the existing atomic write.

- [ ] **Step 6: Run finalizer tests and verify GREEN**

Run the Step 2 command again.

Expected: all existing structure tests and the new synchronization tests PASS. Verify that a deliberately malformed file still remains byte-for-byte unchanged after failed `finalize(at:)`.

- [ ] **Step 7: Commit the Info finalization cycle**

```bash
git diff --check -- \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Synchronize PDF Info metadata"
```

---

### Task 3: Use the Same Metadata in Normal and Spread Export Paths

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportService.swift:248-475`
- Modify: `Honkumi/Shared/Services/PDFPrintProduction.swift:134-191`
- Modify: `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift:72-80`
- Modify: `HonkumiTests/PDFX4GeneratedPDFTests.swift:5-83`
- Modify: `HonkumiTests/PDFX4TestSupport.swift:1-20,120-320`

**Interfaces:**

- Changes: `PDFFileFinalizing.finalize(at:metadata:) throws`
- Changes: `PassthroughPDFFinalizer.finalize(at:metadata:) throws`
- Produces: one metadata value shared by renderer Info, normal XMP, spread XMP, and finalizer Info repair
- Removes: the legacy title/document-ID metadata methods after all callers migrate

- [ ] **Step 1: Change generated-PDF expectations and verify RED**

Before connecting the production export path, update `assertRequiredStructure` so it expects:

```swift
XCTAssertEqual(semantic.pdfXVersionCount, 1, label)
XCTAssertEqual(semantic.pdfXConformanceCount, 0, label)
XCTAssertEqual(semantic.infoProducer, "Honkumi", label)
XCTAssertEqual(semantic.infoProducer, semantic.xmpProducer, label)
XCTAssertEqual(semantic.infoSubject, semantic.xmpDescription, label)
XCTAssertEqual(semantic.infoKeywords, semantic.xmpKeywords, label)
XCTAssertEqual(semantic.infoCreator, semantic.xmpCreatorTool, label)
XCTAssertNil(semantic.infoAuthor, label)
XCTAssertEqual(semantic.xmpCreatorCount, 0, label)
XCTAssertEqual(semantic.infoCreationDate, semantic.xmpCreateDateAsDate, label)
XCTAssertEqual(semantic.infoModificationDate, semantic.xmpModifyDateAsDate, label)
XCTAssertEqual(semantic.xmpModifyDateAsDate, semantic.xmpMetadataDateAsDate, label)
```

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests/testRequiredFontSizesProduceValidStructuresForNormalAndSpreadPDFs \
  test
```

Expected: FAIL because the production exporter still emits the old XMP and Quartz Producer.

- [ ] **Step 2: Expand semantic inspection with independent date parsing**

Add Info/XMP fields listed in Step 1 to `PDFX4SemanticSnapshot`. Read Info strings through Core Graphics. Parse PDF dates with a test-only UTC `DateFormatter` using the literal PDF format, and parse XMP with `ISO8601DateFormatter` configured for internet date-time without fractional seconds. The expected side must not call production date helpers.

Keep the Output Intent and font traversal in the same inspector so a metadata assertion cannot bypass structural checks.

- [ ] **Step 3: Change the finalizer protocol and test doubles**

Use this production protocol:

```swift
nonisolated protocol PDFFileFinalizing: Sendable {
    func finalize(at url: URL, metadata: PDFX4DocumentMetadata) throws
}

nonisolated struct PDFX4FileFinalizer: PDFFileFinalizing {
    func finalize(at url: URL, metadata: PDFX4DocumentMetadata) throws {
        try PDFX4StructureFinalizer.finalize(at: url, metadata: metadata)
    }
}
```

Update `PassthroughPDFFinalizer` to accept and ignore the metadata. Add a test-only lock-protected `CapturingPDFX4Finalizer` that records source bytes before finalization, runs the real metadata-aware finalizer, and records final bytes. Mark the class `@unchecked Sendable` only because every mutable access is protected by `NSLock`.

- [ ] **Step 4: Wire one metadata value through both export branches**

Immediately after computing `pdfTitle`, create:

```swift
let metadata = PDFX4DocumentMetadata.make(
    title: pdfTitle,
    documentID: document.id
)
```

Use `documentInfo(for: metadata)` for `rendererFormat.documentInfo`. Pass `metadata` into `writeSpreadPreviewPDF`, and in both renderer closures call:

```swift
context.cgContext.addDocumentMetadata(
    PDFPrintProduction.pdfX4Profile.xmpMetadataData(for: metadata) as CFData
)
```

Call `finalizer.finalize(at: outputURL, metadata: metadata)` in both branches. Do not alter any line from `context.beginPage` through crop-mark drawing, page translation, or page content drawing.

Remove the old `documentInfo(title:)` and `xmpMetadataData(title:documentID:createdAt:)` methods only after `rg` confirms there are no callers.

- [ ] **Step 5: Run generated-PDF tests and verify GREEN**

Run the Step 1 command again, then run the focused finalizer suite from Task 2.

Expected: both PASS; normal and spread outputs have synchronized metadata, zero conformance identifiers, embedded fonts, unencrypted files, and unchanged structural validation.

- [ ] **Step 6: Commit the export integration cycle**

```bash
git diff --check -- \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Apply synchronized metadata to PDF exports"
```

---

### Task 4: Lock Privacy, Output Intent, ICC, and Crop-Mark Regressions

**Files:**

- Modify: `HonkumiTests/PDFX4GeneratedPDFTests.swift:5-118`
- Modify: `HonkumiTests/PDFX4TestSupport.swift:120-320,1212-1390`
- Modify: `HonkumiTests/PrintSettingSamplePDFTests.swift:6-130`

**Interfaces:**

- Produces: semantic Output Intent fields `outputIntentCount`, `registryName`, `outputCondition`, and `outputIntentInfo`
- Produces: test helper `PDFX4TestInspector.infoStrings(in:)`
- Produces: test helper `PDFX4TestInspector.xmpData(in:)`
- Produces: exact before/after snapshots for A6, B6, and shinsho crop-mark PDFs

- [ ] **Step 1: Add failing Output Intent completeness assertions**

Extend the generated-PDF assertions:

```swift
XCTAssertEqual(semantic.outputIntentCount, 1, label)
XCTAssertEqual(semantic.outputIntentSubtype, "GTS_PDFX", label)
XCTAssertFalse(semantic.outputConditionIdentifier.isEmpty, label)
XCTAssertFalse(semantic.registryName.isEmpty, label)
XCTAssertFalse(
    semantic.outputCondition.isEmpty && semantic.outputIntentInfo.isEmpty,
    label
)
XCTAssertEqual(semantic.iccComponentCount, 4, label)
XCTAssertFalse(semantic.iccData.isEmpty, label)
XCTAssertEqual(semantic.iccData.subdata(in: 36..<40), Data("acsp".utf8), label)
```

The inspector already rejects an Output Intent array whose count is not one; expose the count and remaining required strings so every requested field is visible in the test result.

- [ ] **Step 2: Add a failing colophon privacy test**

Create a document whose enabled colophon uses unique values for author, circle, contact, and URL. Export it, then assert:

```swift
let semantic = try PDFX4TestInspector.inspect(data)
XCTAssertNil(semantic.infoAuthor)
XCTAssertEqual(semantic.xmpCreatorCount, 0)

let xmpText = try XCTUnwrap(
    String(data: PDFX4TestInspector.xmpData(in: data), encoding: .utf8)
)
for secret in [author, circle, contact, url] {
    XCTAssertFalse(xmpText.contains(secret))
}
let infoValues = try PDFX4TestInspector.infoStrings(in: data)
for secret in [author, circle, contact, url] {
    XCTAssertFalse(infoValues.values.contains(secret))
}
```

This tests only Info and XMP; the values may legitimately appear in the drawn colophon page.

- [ ] **Step 3: Add failing A6/B6/shinsho crop-mark regression coverage**

Add a `testPDFX4MetadataFinalizationPreservesCropMarkedProductionSizes` test. For each `PageSize.selectableCases` value, take the existing representative 1-48-page sample, set only `settings.showsCropMarks = true`, and export through `CapturingPDFX4Finalizer`.

For each size require:

```swift
XCTAssertEqual(
    try PDFPageRegressionInspector.snapshots(from: capture.beforeData),
    try PDFPageRegressionInspector.snapshots(from: capture.afterData),
    pageSize.displayName
)
try PDFX4TestInspector.assertNonInfoObjectBodiesEqual(
    before: capture.beforeData,
    after: capture.afterData,
    context: pageSize.displayName
)
```

Also assert that page count is nonzero and the first page's TrimBox differs from MediaBox, proving crop marks are actually enabled. Persist the three finalized PDFs when `HONKUMI_PDF_X4_ARTIFACT_DIR` is set, using stable filenames `A6-cropmarks.pdf`, `B6-cropmarks.pdf`, and `Shinsho-cropmarks.pdf`.

- [ ] **Step 4: Run the new tests and verify RED for each added behavior**

Run:

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests/testPDFX4MetadataFinalizationPreservesCropMarkedProductionSizes \
  test
```

Expected: compile or assertion failures for the not-yet-exposed Output Intent values, privacy helpers, capture helper, and crop-mark regression.

- [ ] **Step 5: Implement only the missing test inspection support**

Expose the existing decoded Metadata stream through `xmpData(in:)`. Enumerate all Info dictionary entries whose values are PDF strings through `infoStrings(in:)`. Add the Output Intent count and strings to the semantic snapshot. Complete the lock-protected capture helper and the three-size artifact persistence helper.

Do not change production Output Intent, ICC, fonts, page sizes, crop-mark settings, or drawing.

- [ ] **Step 6: Run the new tests and verify GREEN**

Run the Step 4 command again.

Expected: PASS with one complete Output Intent, an embedded four-component ICC profile, absent author metadata, no colophon values in metadata, and exact page/content/text/pixel equality for all three crop-mark sizes.

- [ ] **Step 7: Commit the verification cycle**

```bash
git diff --check -- \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift \
  HonkumiTests/PrintSettingSamplePDFTests.swift
git add \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift \
  HonkumiTests/PrintSettingSamplePDFTests.swift
git commit -m "Test PDF X-4 metadata and layout invariants"
```

---

### Task 5: Run Full Verification and Produce the Three Requested PDFs

**Files:**

- Verify only: all changed files from Tasks 1-4
- Generate without committing: `output/pdf/PDFX4MetadataSync-2026-08-01/*.pdf`

**Interfaces:**

- Consumes: the completed production export path and test artifact environment variable
- Produces: A6, B6, and shinsho crop-mark PDFs for structural and external inspection
- Produces: evidence for every requested completion-report item

- [ ] **Step 1: Review the production diff for scope violations**

Run:

```bash
git diff HEAD~4 -- \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift
git diff HEAD~4 --name-only
```

Confirm that no layout, typesetter, crop-mark drawing, page geometry, font, colophon drawing, or Xcode project file changed. If unrelated files appear because the branch contains pre-existing work, compare against the Task 1 starting commit and list only this plan's commits.

- [ ] **Step 2: Run focused PDF/X-4 suites and generate artifacts**

```bash
mkdir -p output/pdf/PDFX4MetadataSync-2026-08-01
HONKUMI_PDF_X4_ARTIFACT_DIR="$PWD/output/pdf/PDFX4MetadataSync-2026-08-01" \
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4StructureFinalizerTests \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests \
  test
```

Expected: exit 0 with the A6, B6, and shinsho crop-mark PDFs written to the artifact directory.

- [ ] **Step 3: Run the complete XCTest suite**

```bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  test
```

Expected: exit 0 with zero test failures.

- [ ] **Step 4: Inspect every generated PDF with pypdf strict mode**

Use the bundled Python runtime and read every object, page box, font descendant, Metadata stream, Output Intent, ICC stream, Info field, and encryption state. The script must exit nonzero unless all three files satisfy:

```python
assert not reader.is_encrypted
assert len(reader.pages) > 0
assert len(root["/OutputIntents"].get_object()) == 1
assert output_intent["/S"] == "/GTS_PDFX"
assert output_intent["/DestOutputProfile"].get_object().get("/N") == 4
assert info["/Producer"] == "Honkumi"
assert b"pdfxid:GTS_PDFXVersion=\"PDF/X-4\"" in xmp
assert b"pdfxid:GTS_PDFXConformance" not in xmp
```

Parse the XMP XML rather than using byte matching for the final Info/XMP value report. Convert PDF and XMP dates to timezone-aware UTC datetimes and compare them.

- [ ] **Step 5: Run Poppler metadata, encryption, font, and render checks**

Use the bundled Poppler binaries:

```bash
PDFTOOLS=/Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override
for pdf in output/pdf/PDFX4MetadataSync-2026-08-01/*.pdf; do
  "$PDFTOOLS/pdfinfo" "$pdf"
  "$PDFTOOLS/pdfinfo" -meta "$pdf"
  name=$(basename "$pdf" .pdf)
  "$PDFTOOLS/pdftoppm" -png -r 144 "$pdf" "/tmp/$name"
done
```

Expected: Producer `Honkumi`, metadata stream present, encryption `no`, expected page geometry, and successful rendering for all pages. Visually inspect representative first-page PNGs for A6, B6, and shinsho crop marks and text.

- [ ] **Step 6: Check product preflight availability without overstating results**

```bash
for tool in qpdf gs verapdf pdfcpu mutool; do
  command -v "$tool" || true
done
```

If no PDF/X-4-capable product preflight is installed, report the product preflight as unavailable and unverified. Do not translate successful XCTest, pypdf, or Poppler checks into a claim of full PDF/X-4 conformance.

- [ ] **Step 7: Run final diff and repository checks**

```bash
git diff --check
git status --short
git log -5 --oneline
```

Separate this task's commits and generated artifacts from the user's pre-existing dirty files. Do not stage generated PDFs or unrelated changes.

- [ ] **Step 8: Prepare the completion report**

Report:

- changed production and test files;
- synchronized metadata fields and absent Author/dc:creator;
- Producer normalization through metadata-aware post-render Info finalization;
- field-by-field Info/XMP comparison results;
- Output Intent and embedded ICC results;
- all-used-font embedding result;
- encryption and restriction result;
- actual PDF/X-4 product-preflight result or explicit unavailability;
- A6/B6/shinsho page-count, page-box, content-stream, extracted-text, and pixel comparison results;
- generated PDF artifact paths.

# PDF/X-4 Internal Structure Finalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair Honkumi's normal and spread-preview PDFs into self-consistent PDF 1.6 files with a valid classic xref table, `/Trapped /False`, retained PDF/X-4 metadata, retained CMYK Output Intent, and unchanged page rendering and typesetting.

**Architecture:** Keep the existing Core Graphics renderer and every page-drawing path unchanged. Add a deterministic byte-level finalizer that parses Quartz's single classic xref table, copies every non-Info indirect object body unchanged, normalizes the Info Dictionary, and serializes a new xref/free list/trailer/startxref before atomically replacing the rendered file.

**Tech Stack:** Swift 6, Foundation, Core Graphics, PDFKit, XCTest, Xcode, bundled Python/pypdf, Poppler pdfinfo and pdftoppm

## Global Constraints

- Treat `docs/superpowers/specs/2026-07-31-pdf-x4-internal-structure-design.md` as the source of truth.
- Apply the same structural finalization to normal PDF export and spread-preview PDF export.
- Keep PDF version 1.6, `pdfxid:GTS_PDFXVersion="PDF/X-4"`, the existing `pdfxid:GTS_PDFXConformance="PDF/X-4"`, `/S /GTS_PDFX`, the Generic CMYK ICC profile, and embedded fonts.
- Set the Info Dictionary value as the PDF Name Object `/Trapped /False`, never the string `(False)`.
- Do not change body, chapter-title, or page-number font sizes.
- Do not change character advance, line advance, characters per line, lines per page, margins, page size, vertical layout, odd/even inner/outer reversal, punctuation adjustment, kinsoku, pagination, table of contents, colophon, or Powered by Honkumi.
- Do not rasterize or outline text and do not reduce text search or extraction behavior.
- Do not modify page content streams, page resources, font streams, ICC streams, or XMP streams during finalization.
- Do not introduce encryption, JavaScript, forms, file attachments, media, external content references, or print-changing optional content.
- Reject unsupported or ambiguous input instead of emitting a PDF that needs parser repair.
- Preserve unrelated working-tree edits, deleted artifacts, untracked output, and the user's current project-file changes.
- The current environment has no Adobe Acrobat Pro, qpdf, Ghostscript, or PDF/X validator; report full PDF/X-4 product preflight separately from the strict structural checks that are actually run.

## File Structure

- Create `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift`
  - Owns classic-xref parsing, object-boundary recovery from xref offsets, Info Dictionary normalization, reference validation, deterministic serialization, and atomic file replacement.
- Modify `Honkumi/Shared/Services/PDFPrintProduction.swift`
  - Removes fixed-width-only header normalization and updates capability descriptions without changing XMP, Output Intent, ICC selection, or page geometry.
- Modify `Honkumi/Shared/Services/PDFExportService.swift`
  - Injects a small file-finalization boundary and invokes it after both normal and spread rendering paths.
- Create `HonkumiTests/PDFX4StructureFinalizerTests.swift`
  - Covers malformed xref repair, free-list generation, `/Trapped /False`, offsets, trailer values, duplicate IDs, missing references, and atomic failure behavior with small synthetic PDFs.
- Create `HonkumiTests/PDFX4GeneratedPDFTests.swift`
  - Generates the five required font sizes through normal and spread paths and checks PDF/X-related dictionaries, ICC, XMP, forbidden features, and font embedding.
- Create `HonkumiTests/PDFX4TestSupport.swift`
  - Contains test-only synthetic PDF construction, Core Graphics dictionary traversal, XML capture, page fingerprints, and deterministic bitmap rendering.
- Modify `HonkumiTests/PrintSettingSamplePDFTests.swift`
  - Adds finalization-before/after regression coverage using the existing font-size sample manifest.

---

### Task 1: Parse and Rebuild a Quartz Classic Xref Table

**Files:**

- Create: `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift`
- Create: `HonkumiTests/PDFX4StructureFinalizerTests.swift`
- Create: `HonkumiTests/PDFX4TestSupport.swift`

**Interfaces:**

- Produces: `PDFObjectReference(number:generation:)`
- Produces: `PDFXRefEntry.Kind.inUse(offset:)` and `.free(nextFreeObject:generation:)`
- Produces: `PDFX4StructureSnapshot` with `xrefOffset`, `declaredSize`, `rootReference`, `infoReference`, `entries`, and `objectBodies`
- Produces: `PDFX4StructureFinalizer.structure(in:allowRepairableZeroOffsets:) throws`
- Produces: `PDFX4StructureFinalizer.finalizedData(from:) throws -> Data`
- Preserves: every non-Info `objectBody` byte-for-byte

- [ ] **Step 1: Read the test-quality rules before writing the first test**

Read:

~~~bash
sed -n '1,320p' /Users/orca/.codex/plugins/cache/openai-curated-remote/superpowers/6.2.0/skills/test-driven-development/writing-good-tests.md
~~~

Name the production mutation each test catches: restoring an offset-zero in-use entry, emitting a stale `startxref`, or writing `(False)` instead of `/False`.

- [ ] **Step 2: Add a real malformed-Quartz fixture and the first failing tests**

In `PDFX4TestSupport.swift`, add a builder that records real object offsets but deliberately emits object 4 as `0000000000 00000 n`:

~~~swift
enum PDFTestFixtureBuilder {
    static func malformedQuartzStylePDF(trappedValue: String? = nil) -> Data {
        var data = Data("%PDF-1.3\n".utf8)
        var offsets: [Int: Int] = [:]

        func appendObject(_ number: Int, _ body: String) {
            offsets[number] = data.count
            data.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
        }

        appendObject(1, "<< /Type /Catalog /Pages 2 0 R >>")
        appendObject(2, "<< /Type /Pages /Count 0 /Kids [] >>")
        let trapped = trappedValue.map { " /Trapped \($0)" } ?? ""
        appendObject(3, "<< /Title (Fixture)\(trapped) >>")

        let xrefOffset = data.count
        data.append(Data("xref\n0 5\n".utf8))
        data.append(Data("0000000000 65535 f \n".utf8))
        for number in 1...3 {
            data.append(Data(String(format: "%010d 00000 n \n", offsets[number]! ).utf8))
        }
        data.append(Data("0000000000 00000 n \n".utf8))
        data.append(Data("""
        trailer
        << /Size 5 /Root 1 0 R /Info 3 0 R >>
        startxref
        \(xrefOffset)
        %%EOF
        """.utf8))
        return data
    }
}
~~~

Add the behavior tests:

~~~swift
final class PDFX4StructureFinalizerTests: XCTestCase {
    func testFinalizationTurnsOffsetZeroInUseEntryIntoFreeEntry() throws {
        let output = try PDFX4StructureFinalizer.finalizedData(
            from: PDFTestFixtureBuilder.malformedQuartzStylePDF()
        )
        let structure = try PDFX4StructureFinalizer.structure(in: output)

        XCTAssertEqual(structure.entries[4]?.kind, .free(nextFreeObject: 0, generation: 1))
        XCTAssertEqual(structure.entries[0]?.kind, .free(nextFreeObject: 4, generation: 65_535))
        XCTAssertEqual(output[structure.xrefOffset...].prefix(4), Data("xref".utf8))
        XCTAssertEqual(structure.declaredSize, 5)
    }

    func testFinalizationAddsTrappedAsFalseName() throws {
        let output = try PDFX4StructureFinalizer.finalizedData(
            from: PDFTestFixtureBuilder.malformedQuartzStylePDF()
        )
        let structure = try PDFX4StructureFinalizer.structure(in: output)
        let info = try XCTUnwrap(structure.objectBodies[structure.infoReference])

        XCTAssertTrue(info.contains(Data("/Trapped /False".utf8)))
        XCTAssertFalse(info.contains(Data("/Trapped (False)".utf8)))
    }
}
~~~

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4StructureFinalizerTests \
  test
~~~

Expected: build failure because `PDFX4StructureFinalizer` and its snapshot types do not exist. This is the expected missing-production-code failure.

- [ ] **Step 4: Add the parser and explicit error model**

Create these internal types in `PDFX4StructureFinalizer.swift`:

~~~swift
import CoreGraphics
import Foundation

nonisolated struct PDFObjectReference: Hashable, Equatable {
    let number: Int
    let generation: Int
}

nonisolated struct PDFXRefEntry: Equatable {
    enum Kind: Equatable {
        case inUse(offset: Int)
        case free(nextFreeObject: Int, generation: Int)
    }

    let reference: PDFObjectReference
    let kind: Kind
}

nonisolated struct PDFX4StructureSnapshot {
    let xrefOffset: Int
    let declaredSize: Int
    let rootReference: PDFObjectReference
    let infoReference: PDFObjectReference
    let entries: [Int: PDFXRefEntry]
    let objectBodies: [PDFObjectReference: Data]
}

nonisolated enum PDFX4FinalizationError: Error, Equatable {
    case malformedHeader
    case missingStartXRef
    case invalidStartXRef(Int)
    case unsupportedXRefStream
    case unsupportedIncrementalUpdate
    case malformedXRef
    case duplicateObjectNumber(Int)
    case invalidObjectOffset(Int)
    case objectHeaderMismatch(Int)
    case missingRoot
    case missingInfo
    case invalidTrailerSize
    case missingReference(PDFObjectReference)
    case encryptedPDF
    case invalidInfoDictionary
    case outputTooLarge
    case unreadableFinalizedPDF
}
~~~

Implement a private byte cursor that reads ASCII PDF structural tokens directly from `Data`. It must:

- skip PDF whitespace and `%` comments;
- parse all xref subsections rather than assuming only `0 N`;
- reject duplicate object numbers across subsections;
- read `trailer`, `/Size`, `/Root`, `/Info`, `/ID`, `/Prev`, `/XRefStm`, and `/Encrypt`;
- preserve the raw values of other supported top-level trailer entries while always rebuilding `/Size` and rejecting `/Prev`, `/XRefStm`, and `/Encrypt`;
- use xref offsets, not `endobj` searches inside streams, to determine object slices;
- treat only offset-zero in-use entries as repairable when `allowRepairableZeroOffsets` is true;
- verify every positive in-use offset starts with the matching `number generation obj` header.

Expose the parser through:

~~~swift
nonisolated enum PDFX4StructureFinalizer {
    static func structure(
        in data: Data,
        allowRepairableZeroOffsets: Bool = false
    ) throws -> PDFX4StructureSnapshot {
        try PDFClassicXRefParser(data: data).parse(
            allowRepairableZeroOffsets: allowRepairableZeroOffsets
        )
    }
}
~~~

- [ ] **Step 5: Implement deterministic serialization and `/Trapped /False` insertion**

Implement `finalizedData(from:)` with these exact ordering rules:

~~~swift
static func finalizedData(from source: Data) throws -> Data {
    let parsed = try structure(in: source, allowRepairableZeroOffsets: true)
    let infoBody = try PDFInfoDictionaryNormalizer.trappedFalse(
        in: parsed.objectBodies[parsed.infoReference]!
    )

    var output = PDFSerialization.header(version: "1.6", source: source)
    var newOffsets: [PDFObjectReference: Int] = [:]

    for object in parsed.objectBodies.keys.sorted(by: parsed.originalOffsetOrder) {
        newOffsets[object] = output.count
        output.append(object == parsed.infoReference ? infoBody : parsed.objectBodies[object]!)
        output.append(PDFSerialization.objectSeparator)
    }

    let xrefOffset = output.count
    let size = max(parsed.entries.keys.max() ?? 0, parsed.objectBodies.keys.map(\.number).max() ?? 0) + 1
    output.append(PDFSerialization.xrefTable(
        size: size,
        originalEntries: parsed.entries,
        objectOffsets: newOffsets
    ))
    output.append(PDFSerialization.trailer(
        size: size,
        root: parsed.rootReference,
        info: parsed.infoReference,
        idValue: parsed.rawIDValue,
        startXRef: xrefOffset
    ))

    _ = try structure(in: output)
    return output
}
~~~

The concrete snapshot must also include immutable internal `originalOffsets`, `rawIDValue`, and `preservedTrailerEntries` properties needed by this code. `PDFSerialization.header` must retain the original line ending and binary marker bytes between the first header line and the first indirect object while changing only the version token to 1.6.

`PDFInfoDictionaryNormalizer` must locate the top-level `<< ... >>`, skip strings/comments/hex strings, replace an existing top-level `/Trapped` value, or insert one immediately before the matching `>>`. It must not perform a global string replacement.

Format every xref row as exactly 10 offset digits, one space, 5 generation digits, one space, `n` or `f`, one space, and newline. Set object 0 to generation 65535. Link every free object in ascending order and use generation 1 for a former generation-0 offset-zero in-use entry.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the Step 3 command again.

Expected: both tests PASS; the rebuilt `startxref` points to `xref`, object 4 is free, and the Info body contains the Name Object `/False`.

- [ ] **Step 7: Commit the parser/rebuilder cycle**

Run:

~~~bash
git diff --check -- \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Add deterministic PDF xref finalizer"
~~~

Expected: only the new finalizer and its focused test support are committed.

---

### Task 2: Reject Broken References and Replace Files Atomically

**Files:**

- Modify: `Honkumi/Shared/Services/PDFX4StructureFinalizer.swift`
- Modify: `HonkumiTests/PDFX4StructureFinalizerTests.swift`
- Modify: `HonkumiTests/PDFX4TestSupport.swift`

**Interfaces:**

- Consumes: `PDFX4StructureFinalizer.finalizedData(from:)`
- Produces: `PDFX4StructureFinalizer.finalize(at:) throws`
- Produces: complete indirect-reference validation outside stream payload bytes
- Guarantees: source URL is replaced only after rebuilt Data passes internal parsing and `CGPDFDocument` reopening

- [ ] **Step 1: Add failing malformed-input and atomicity tests**

Add fixture variants for an incorrect positive offset, duplicate xref object number, `/Prev`, `/Encrypt`, and a Catalog reference to `99 0 R`. Implement `pdfWithCatalogReference(_:)` by using the Task 1 builder with object 1 body `<< /Type /Catalog /Pages 2 0 R /Broken <reference> >>`; implement the other variants by replacing only the xref/trailer text produced by the fixture builder before the production finalizer sees it.

Add tests with explicit expected errors:

~~~swift
func testFinalizationRejectsMissingIndirectReference() {
    let input = PDFTestFixtureBuilder.pdfWithCatalogReference("99 0 R")

    XCTAssertThrowsError(try PDFX4StructureFinalizer.finalizedData(from: input)) {
        XCTAssertEqual($0 as? PDFX4FinalizationError, .missingReference(.init(number: 99, generation: 0)))
    }
}

func testFinalizationNormalizesExistingStringTrappedValue() throws {
    let input = PDFTestFixtureBuilder.malformedQuartzStylePDF(trappedValue: "(False)")
    let output = try PDFX4StructureFinalizer.finalizedData(from: input)
    let info = try PDFX4TestInspector.infoObjectBody(in: output)

    XCTAssertEqual(
        PDFX4TestInspector.occurrenceCount(of: Data("/Trapped /False".utf8), in: info),
        1
    )
    XCTAssertFalse(info.contains(Data("/Trapped (False)".utf8)))
}

func testFileFinalizationLeavesOriginalBytesWhenValidationFails() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
    let malformed = Data("%PDF-1.3\nnot a pdf".utf8)
    try malformed.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertThrowsError(try PDFX4StructureFinalizer.finalize(at: url))
    XCTAssertEqual(try Data(contentsOf: url), malformed)
}
~~~

Add these test-helper signatures with byte-wise implementations; `occurrenceCount` repeatedly calls `Data.range(of:in:)` with a strictly advancing lower bound, and `infoObjectBody` obtains the parsed Info reference instead of searching arbitrary PDF text:

~~~swift
enum PDFX4TestInspector {
    static func infoObjectBody(in data: Data) throws -> Data
    static func occurrenceCount(of needle: Data, in haystack: Data) -> Int
}
~~~

- [ ] **Step 2: Run the focused tests and verify RED**

Run the Task 1 focused test command.

Expected: the new tests FAIL because indirect references are not fully validated and `finalize(at:)` does not exist.

- [ ] **Step 3: Add a lexical structural-token scan**

Implement a private `PDFLexicalScanner` that:

- skips nested literal strings including escapes;
- skips hex strings and comments;
- recognizes names, integers, delimiters, `obj`, `stream`, `endstream`, and `R`;
- obtains each stream length from the owning dictionary and skips exactly that many payload bytes;
- resolves an indirect `/Length N G R` through a non-stream integer object;
- records every structural `N G R` reference outside stream payloads;
- rejects references that do not exist in `objectBodies` with the same generation.

Run reference validation before serialization and again on the rebuilt output.

- [ ] **Step 4: Add atomic file finalization and Core Graphics reopening**

Implement:

~~~swift
static func finalize(at url: URL) throws {
    let source = try Data(contentsOf: url)
    let output = try finalizedData(from: source)

    guard
        let provider = CGDataProvider(data: output as CFData),
        CGPDFDocument(provider) != nil
    else {
        throw PDFX4FinalizationError.unreadableFinalizedPDF
    }

    try output.write(to: url, options: .atomic)
}
~~~

Because all parsing and reopening occur before `.atomic`, any validation error leaves the renderer's original file bytes unchanged. The exporter's existing catch block remains responsible for deleting a failed export.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Task 1 focused command.

Expected: every malformed input is rejected with its precise error, string-valued Trapped is normalized exactly once, and a failed file finalization preserves its original bytes.

- [ ] **Step 6: Commit validation and atomic replacement**

Run:

~~~bash
git diff --check -- \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Validate finalized PDF object references"
~~~

---

### Task 3: Finalize Normal and Spread PDF Export

**Files:**

- Modify: `Honkumi/Shared/Services/PDFExportService.swift:190-332`
- Modify: `Honkumi/Shared/Services/PDFPrintProduction.swift:4-58`
- Modify: `Honkumi/Shared/Services/PDFPrintProduction.swift:102-121`
- Create: `HonkumiTests/PDFX4GeneratedPDFTests.swift`
- Modify: `HonkumiTests/PDFX4TestSupport.swift`

**Interfaces:**

- Produces: `PDFFileFinalizing.finalize(at:) throws`
- Produces: `PDFX4FileFinalizer`
- Changes: `BodyPDFExportService.init(finalizer:)`
- Guarantees: finalizer invocation after both normal and `.spread` rendering
- Preserves: existing public `PDFExportService` and `PreviewPDFExporting` APIs

- [ ] **Step 1: Add the five-size, two-path generated-PDF acceptance test**

Add `PDFX4TestInspector.inspect(_:)` in test support using Core Graphics:

~~~swift
struct PDFX4SemanticSnapshot {
    let version: String
    let trappedName: String
    let outputIntentSubtype: String
    let outputConditionIdentifier: String
    let catalogVersion: String?
    let iccComponentCount: Int
    let iccData: Data
    let iccLoadsAsFourComponentColorSpace: Bool
    let pdfXVersionCount: Int
    let pdfXConformanceCount: Int
    let infoTitle: String
    let xmpTitle: String
    let infoCreator: String
    let xmpCreatorTool: String
    let isEncrypted: Bool
    let hasAcroForm: Bool
    let hasJavaScript: Bool
    let hasEmbeddedFiles: Bool
    let hasExternalReferences: Bool
    let unresolvedColorSpaceNames: Set<String>
    let embeddedBaseFontNames: Set<String>
}

enum PDFX4TestInspector {
    static func inspect(_ data: Data) throws -> PDFX4SemanticSnapshot
}
~~~

The inspector must use:

- `CGPDFDocumentGetInfo` and `CGPDFDictionaryGetName` for `/Trapped`;
- Catalog `/OutputIntents`, `/S`, `/OutputConditionIdentifier`, and `/DestOutputProfile`;
- `CGPDFStreamCopyData` for decoded ICC and XMP bytes;
- ICC byte range `36..<40` for the `acsp` signature;
- `CGColorSpace(iccData:)` to prove the decoded profile is loadable and has four components;
- `XMLParser` with a delegate counting the two `pdfxid` attributes;
- the same XML delegate capturing `dc:title` and `xmp:CreatorTool` for Info/XMP consistency checks;
- recursive page Resource/Font traversal, including Type0 `/DescendantFonts`, `/FontDescriptor`, and non-empty `/FontFile`, `/FontFile2`, or `/FontFile3`;
- recursive page Resource/ColorSpace traversal that resolves every named or indirect color-space definition and accepts the existing DeviceGray, DeviceRGB, DeviceCMYK, Pattern, and ICCBased families;
- Catalog checks for `/AcroForm`, `/JavaScript`, `/Names` → `/EmbeddedFiles`, `/OCProperties`, remote-go-to/file-spec external references, and page annotation subtypes.

Add the generated test:

~~~swift
final class PDFX4GeneratedPDFTests: XCTestCase {
    private let requiredSizes: Set<CGFloat> = [7, 10, 12, 12.5, 16.5]

    func testRequiredFontSizesProduceValidStructuresForNormalAndSpreadPDFs() throws {
        let samples = PrintSettingSampleManifest.fontSizeCases().filter {
            requiredSizes.contains($0.document.settings.fontSize)
        }
        XCTAssertEqual(samples.count, requiredSizes.count)

        for sample in samples {
            let normalURL = try BodyPDFExportService().export(
                document: sample.document,
                subscriptionStatus: .free
            )
            try assertRequiredStructure(at: normalURL, label: "\(sample.fileName) normal")

            let spreadURL = try BodyPDFExportService().exportPreviewPDF(
                document: sample.document,
                subscriptionStatus: .free,
                previewKind: .spread,
                generationID: UUID()
            )
            try assertRequiredStructure(at: spreadURL, label: "\(sample.fileName) spread")
        }
    }

    private func persistArtifactIfRequested(
        sourceURL: URL,
        fontSize: CGFloat,
        kind: String
    ) throws {
        guard let directory = ProcessInfo.processInfo.environment["HONKUMI_PDF_X4_ARTIFACT_DIR"] else {
            return
        }
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let name = String(format: "font-%04.1f-%@.pdf", Double(fontSize), kind)
        let destination = directoryURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}
~~~

Call `persistArtifactIfRequested` after each normal and spread assertion. This hook remains inert during ordinary test runs and is committed with the acceptance test, so Task 5 performs verification only.

`assertRequiredStructure` must assert:

- strict `PDFX4StructureFinalizer.structure(in:)` success;
- no in-use entry at offset 0;
- every in-use offset has the expected object header;
- xref location equals parsed `startxref`;
- `/Size`, `/Root`, and Catalog are valid;
- `version == "1.6"`;
- Catalog `/Version` is absent or exactly `1.6`;
- `trappedName == "False"`;
- `/S == "GTS_PDFX"` and OutputConditionIdentifier is non-empty;
- ICC `/N == 4`, decoded data is non-empty, and bytes 36–39 are `acsp`;
- decoded ICC data creates a four-component `CGColorSpace` successfully;
- exactly one PDF/X-4 version and conformance attribute;
- Info Title equals XMP default Title and Info Creator equals XMP CreatorTool;
- no encryption, form, JavaScript, embedded files, external references, print annotations, or invalid references;
- every used color-space name resolves and DeviceCMYK use has the retained CMYK Output Intent;
- embedded font names contain `BIZUDMincho-Regular` and `HiraginoSans-W3`;
- every encountered FontDescriptor has a non-empty embedded font stream.

- [ ] **Step 2: Run the generated acceptance test and verify RED**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  test
~~~

Expected: FAIL on the current exports because `/Trapped` is missing and the Quartz-reserved object has an offset-zero in-use xref entry.

- [ ] **Step 3: Add the injectable finalization boundary**

In `PDFX4StructureFinalizer.swift`, add:

~~~swift
nonisolated protocol PDFFileFinalizing: Sendable {
    func finalize(at url: URL) throws
}

nonisolated struct PDFX4FileFinalizer: PDFFileFinalizing {
    func finalize(at url: URL) throws {
        try PDFX4StructureFinalizer.finalize(at: url)
    }
}
~~~

In `BodyPDFExportService`, add a Sendable dependency with the production default:

~~~swift
nonisolated struct BodyPDFExportService {
    private let finalizer: any PDFFileFinalizing

    init(finalizer: any PDFFileFinalizing = PDFX4FileFinalizer()) {
        self.finalizer = finalizer
    }

    // Existing export methods remain unchanged.
}
~~~

- [ ] **Step 4: Replace both header-only calls with full finalization**

In both existing post-render locations, replace:

~~~swift
try PDFPrintProduction.normalizePDFVersionHeader(at: outputURL)
~~~

with:

~~~swift
try finalizer.finalize(at: outputURL)
~~~

Keep `Task.checkCancellation()` immediately before and after each finalization call and keep the existing catch cleanup. Do not modify renderer bounds, page iteration, drawing, metadata insertion, or spread composition.

Remove `normalizePDFVersionHeader(at:)` from `PDFPrintProduction`. Keep `targetPDFVersion = "1.6"` as the single version constant and use it from the finalizer.

Update capability text only:

~~~swift
static let implementedCapabilities: [String] = [
    "PDF/X-4 target XMP metadata",
    "PDF-1.6 deterministic xref finalization",
    "Info Dictionary /Trapped /False",
    "Output Intent",
    "ICC profile embedding through CGColorSpace",
    "MediaBox / TrimBox / BleedBox / CropBox",
    "Unencrypted PDF output",
    "Post-export structural and font-embedding tests",
    "Vector text, rules, crop marks, page numbers, and QR code drawing"
]

static let unsupportedCapabilities: [String] = [
    "Bundled certified PDF/X-4 product preflight",
    "Print-shop-specific ICC profile selection"
]
~~~

- [ ] **Step 5: Run focused finalizer and generated tests and verify GREEN**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4StructureFinalizerTests \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  test
~~~

Expected: PASS for all five font sizes in both normal and spread paths.

- [ ] **Step 6: Commit export integration**

Run:

~~~bash
git diff --check -- \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git add \
  Honkumi/Shared/Services/PDFExportService.swift \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift
git commit -m "Finalize normal and spread PDFs for PDF X-4"
~~~

---

### Task 4: Prove Typesetting and Rendering Are Byte-for-Byte Stable

**Files:**

- Modify: `HonkumiTests/PDFX4TestSupport.swift`
- Modify: `HonkumiTests/PrintSettingSamplePDFTests.swift`

**Interfaces:**

- Consumes: `BodyPDFExportService(finalizer:)`
- Consumes: `PDFX4StructureFinalizer.finalizedData(from:)`
- Produces: `PassthroughPDFFinalizer` for raw Quartz output in tests
- Produces: `PDFPageRegressionSnapshot` with page boxes, decoded content bytes, extracted text, and rendered RGBA bytes
- Guarantees: finalization changes only header, Info, xref, trailer, and separators outside object bodies

- [ ] **Step 1: Add finalization-before/after regression tests**

Add a test-only no-op finalizer:

~~~swift
nonisolated struct PassthroughPDFFinalizer: PDFFileFinalizing {
    func finalize(at url: URL) throws {}
}
~~~

Add test helpers:

~~~swift
struct PDFPageRegressionSnapshot: Equatable {
    let mediaBox: CGRect
    let trimBox: CGRect
    let bleedBox: CGRect
    let cropBox: CGRect
    let decodedContentData: Data
    let extractedText: String
    let rgbaPixels: Data
}

enum PDFPageRegressionInspector {
    static func snapshots(from data: Data, scale: CGFloat = 2) throws
        -> [PDFPageRegressionSnapshot]
}

extension PDFX4TestInspector {
    static func assertNonInfoObjectBodiesEqual(before: Data, after: Data) throws
}
~~~

Render each page into an explicitly white, 8-bit RGBA bitmap with fixed dimensions derived from the MediaBox and scale. Use `CGContext.drawPDFPage` with the same transform for both Data inputs. Extract text with `PDFDocument(data:)`. Decode one stream or every stream in a `/Contents` array with `CGPDFStreamCopyData`. Implement `assertNonInfoObjectBodiesEqual` by parsing both structures with repairable-zero mode enabled for `before`, removing the Info reference from each object-body map, and comparing every remaining reference and body exactly.

Add this test to `PrintSettingSamplePDFTests`:

~~~swift
func testPDFX4FinalizationPreservesAllRequiredFontSizeRendering() throws {
    let sizes: Set<CGFloat> = [7, 10, 12, 12.5, 16.5]
    let samples = PrintSettingSampleManifest.fontSizeCases().filter {
        sizes.contains($0.document.settings.fontSize)
    }

    for sample in samples {
        for kind in [PreviewPDFKind.normal, .spread] {
            let rawURL: URL
            if kind == .normal {
                rawURL = try BodyPDFExportService(finalizer: PassthroughPDFFinalizer()).export(
                    document: sample.document,
                    subscriptionStatus: .free
                )
            } else {
                rawURL = try BodyPDFExportService(finalizer: PassthroughPDFFinalizer()).exportPreviewPDF(
                    document: sample.document,
                    subscriptionStatus: .free,
                    previewKind: .spread,
                    generationID: UUID()
                )
            }

            let before = try Data(contentsOf: rawURL)
            let after = try PDFX4StructureFinalizer.finalizedData(from: before)

            XCTAssertEqual(
                try PDFPageRegressionInspector.snapshots(from: before),
                try PDFPageRegressionInspector.snapshots(from: after),
                "\(sample.fileName) \(kind)"
            )
            try PDFX4TestInspector.assertNonInfoObjectBodiesEqual(before: before, after: after)
        }
    }
}
~~~

- [ ] **Step 2: Add explicit layout-invariant assertions**

For every required sample, assert odd and even `PageLayout` values directly:

~~~swift
let settings = sample.document.settings.validated
let odd = LayoutCalculator.layout(for: settings, pageNumber: 1)
let even = LayoutCalculator.layout(for: settings, pageNumber: 2)

XCTAssertEqual(odd.fontSize, settings.fontSize)
XCTAssertEqual(odd.lineAdvance, odd.bodyFrame.width / CGFloat(settings.linesPerPage), accuracy: 0.0001)
XCTAssertEqual(odd.characterAdvance, odd.bodyFrame.height / CGFloat(settings.charactersPerLine), accuracy: 0.0001)
XCTAssertEqual(odd.marginTop, even.marginTop)
XCTAssertEqual(odd.marginBottom, even.marginBottom)
XCTAssertEqual(odd.bodyFrame.minX, LayoutCalculator.millimetersToPoints(settings.marginOuter), accuracy: 0.0001)
XCTAssertEqual(even.bodyFrame.minX, LayoutCalculator.millimetersToPoints(settings.marginInner), accuracy: 0.0001)
XCTAssertEqual(odd.settings.chapterTitleSize, settings.chapterTitleSize)
XCTAssertEqual(odd.settings.pageNumberSize, settings.pageNumberSize)
~~~

Also assert `charactersPerLine`, `linesPerPage`, and all four margin values remain the sample settings. The page snapshots then prove those unchanged values produce identical pagination, coordinates, page-number positions, and rendered pixels before and after finalization.

- [ ] **Step 3: Run the regression test**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests \
  test
~~~

Expected: PASS with exact equality for page count, boxes, content bytes, extracted text, and RGBA pixels across all five sizes and both output kinds.

If this fails, change only the finalizer or test's deterministic rendering setup. Do not change layout, font sizes, content drawing, pagination, or expected pixel data to hide a real difference.

- [ ] **Step 4: Commit regression coverage**

Run:

~~~bash
git diff --check -- \
  HonkumiTests/PDFX4TestSupport.swift \
  HonkumiTests/PrintSettingSamplePDFTests.swift
git add \
  HonkumiTests/PDFX4TestSupport.swift \
  HonkumiTests/PrintSettingSamplePDFTests.swift
git commit -m "Test PDF X-4 rendering stability"
~~~

---

### Task 5: Run Strict Structural, Build, and Visual Verification

**Files:**

- Verify only; modify production or tests only if a preceding verification exposes a real defect, then repeat the affected RED/GREEN cycle before continuing.

**Interfaces:**

- Consumes: all Task 1-4 tests
- Produces: fresh XCTest, build, pypdf strict, Poppler metadata, and Poppler rendering evidence
- Produces: an explicit statement that certified PDF/X-4 product preflight remains unavailable in this environment

- [ ] **Step 1: Run the complete focused PDF test set**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4StructureFinalizerTests \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  -only-testing:HonkumiTests/PrintSettingSamplePDFTests \
  -only-testing:HonkumiTests/LayoutCalculatorTests \
  -only-testing:HonkumiTests/ChapterHeaderPDFRenderingTests \
  -only-testing:HonkumiTests/ColophonCreatorVisibilityTests \
  test
~~~

Expected: all focused tests PASS.

- [ ] **Step 2: Run the full test suite**

Run:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  test
~~~

Expected: the entire Honkumi XCTest suite PASS with zero failures.

- [ ] **Step 3: Run build verification**

Run each command separately:

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-pdf-x4-debug \
  build
~~~

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme 'Honkumi Staging' \
  -configuration Staging \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-pdf-x4-staging \
  build
~~~

~~~bash
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/honkumi-pdf-x4-release \
  build
~~~

Expected: all three commands exit 0.

- [ ] **Step 4: Export stable verification artifacts with the committed test hook**

Use the Task 3 hook in `PDFX4GeneratedPDFTests`, which copies final normal and spread files only when `HONKUMI_PDF_X4_ARTIFACT_DIR` is set. It uses stable names containing font size and output kind.

Run:

~~~bash
HONKUMI_PDF_X4_ARTIFACT_DIR=/tmp/honkumi-pdf-x4-artifacts \
xcodebuild -quiet \
  -project Honkumi.xcodeproj \
  -scheme Honkumi \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:HonkumiTests/PDFX4GeneratedPDFTests \
  test
~~~

Expected: 10 PDFs, one normal and one spread PDF for each required size.

- [ ] **Step 5: Run pypdf strict-mode checks over all artifacts**

Use the bundled runtime:

~~~bash
/Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -c '
from pathlib import Path
from pypdf import PdfReader

paths = sorted(Path("/tmp/honkumi-pdf-x4-artifacts").glob("*.pdf"))
assert len(paths) == 10, len(paths)
for path in paths:
    reader = PdfReader(path, strict=True)
    assert not reader.is_encrypted
    assert len(reader.pages) > 0
    root = reader.trailer["/Root"]
    info = reader.trailer["/Info"]
    assert info["/Trapped"] == "/False"
    intents = root["/OutputIntents"]
    intent = intents[0]
    assert intent["/S"] == "/GTS_PDFX"
    assert intent["/OutputConditionIdentifier"]
    profile = intent["/DestOutputProfile"]
    assert profile["/N"] == 4
    icc = profile.get_data()
    assert len(icc) > 128 and icc[36:40] == b"acsp"
    assert "/Encrypt" not in reader.trailer
    assert "/AcroForm" not in root
    assert "/JavaScript" not in root
    assert "/EmbeddedFiles" not in root.get("/Names", {})
    for page in reader.pages:
        _ = page.get_contents()
print(f"strict pypdf: {len(paths)} PDFs passed")
'
~~~

Expected: `strict pypdf: 10 PDFs passed` with no repair warnings such as `Ignoring wrong pointing object`.

- [ ] **Step 6: Run Poppler structural and rendering checks**

Use the bundled tools:

~~~bash
find /tmp/honkumi-pdf-x4-artifacts -name '*.pdf' -exec \
  /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdfinfo '{}' \;
~~~

Expected for every file: PDF version 1.6, encrypted `no`, form `none`, metadata stream `yes`, and no syntax/repair warnings.

Render all pages:

~~~bash
mkdir -p /tmp/honkumi-pdf-x4-rendered
find /tmp/honkumi-pdf-x4-artifacts -name '*.pdf' -exec sh -c '
  name=$(basename "$1" .pdf)
  /Users/orca/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/pdftoppm \
    -png "$1" "/tmp/honkumi-pdf-x4-rendered/$name"
' sh '{}' \;
~~~

Expected: every PDF renders without errors. Inspect representative normal and spread PNGs with the local image viewer for body text, chapter title, page number, colophon/Powered by Honkumi where present, and page boundaries.

- [ ] **Step 7: Run any newly available external validators without overstating them**

Check:

~~~bash
command -v qpdf || true
command -v gs || true
command -v verapdf || true
find /Applications -maxdepth 2 -iname '*Acrobat*' -print
~~~

If qpdf exists, run `qpdf --check` on all 10 files. If a genuine PDF/X-4 preflight product exists, run its PDF/X-4 profile. Do not describe Ghostscript rendering or veraPDF PDF/A validation as a certified PDF/X-4 preflight.

When none is available, record: “Strict structural validation completed; certified PDF/X-4 product preflight was not available in this environment.”

- [ ] **Step 8: Verify scope and working-tree hygiene**

Run:

~~~bash
git diff --check
git status --short
git diff -- \
  Honkumi/Shared/Services/PDFX4StructureFinalizer.swift \
  Honkumi/Shared/Services/PDFPrintProduction.swift \
  Honkumi/Shared/Services/PDFExportService.swift \
  HonkumiTests/PDFX4StructureFinalizerTests.swift \
  HonkumiTests/PDFX4GeneratedPDFTests.swift \
  HonkumiTests/PDFX4TestSupport.swift \
  HonkumiTests/PrintSettingSamplePDFTests.swift
~~~

Confirm no layout, typesetter, UI, settings-model, or unrelated artifact file is in the PDF/X-4 implementation diff.

- [ ] **Step 9: Prepare the final evidence report**

Report:

- changed files;
- repaired xref/free-list/trailer/startxref behavior;
- `/Trapped /False` implementation;
- retained XMP, Output Intent, ICC, and embedded fonts;
- focused/full XCTest and build counts;
- pypdf and Poppler results;
- exact rendering comparison result;
- whether a certified PDF/X-4 preflight product was available;
- any remaining limitation without describing it as a pass.

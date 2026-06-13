import CoreGraphics
import Foundation

nonisolated enum PDFPrintProduction {
    static let cropMarkMarginMillimeters: CGFloat = 10
    static let cropMarkLengthMillimeters: CGFloat = 6
    static let cropMarkGapMillimeters: CGFloat = 2
    static let cropMarkLineWidthPoints: CGFloat = 0.25

    static let bleedSettings = PDFBleedSettings.none
    static let pdfX4Profile = PDFX4ProductionProfile.default
    static let targetPDFVersion = "1.6"

    static func pageGeometry(for layout: PageLayout) -> PDFPageGeometry {
        let cropMarkInset = layout.settings.showsCropMarks
            ? LayoutCalculator.millimetersToPoints(cropMarkMarginMillimeters)
            : 0
        let trimBox = CGRect(
            x: cropMarkInset,
            y: cropMarkInset,
            width: layout.pageWidth,
            height: layout.pageHeight
        )
        let mediaBox = CGRect(
            x: 0,
            y: 0,
            width: layout.pageWidth + cropMarkInset * 2,
            height: layout.pageHeight + cropMarkInset * 2
        )
        let bleedInset = LayoutCalculator.millimetersToPoints(bleedSettings.bleedMillimeters)
        let bleedBox = bleedInset > 0
            ? trimBox.insetBy(dx: -bleedInset, dy: -bleedInset).intersection(mediaBox)
            : trimBox

        return PDFPageGeometry(
            mediaBox: mediaBox,
            trimBox: trimBox,
            bleedBox: bleedBox,
            cropBox: mediaBox,
            trimOffset: CGSize(width: cropMarkInset, height: cropMarkInset)
        )
    }

    static func normalizePDFVersionHeader(at url: URL) throws {
        var data = try Data(contentsOf: url)
        let targetHeader = Data("%PDF-\(targetPDFVersion)".utf8)
        guard data.count >= targetHeader.count,
              data.starts(with: Data("%PDF-".utf8)),
              data.prefix(targetHeader.count) != targetHeader else {
            return
        }

        // CoreGraphics does not expose a PDF version option. Replacing only
        // the fixed-width header keeps object offsets and xref positions stable,
        // but does not by itself prove PDF/X-4 conformance.
        data.replaceSubrange(0..<targetHeader.count, with: targetHeader)
        try data.write(to: url, options: .atomic)
    }
}

nonisolated struct PDFBleedSettings: Equatable {
    let bleedMillimeters: CGFloat

    static let none = PDFBleedSettings(bleedMillimeters: 0)
}

nonisolated struct PDFPageGeometry: Equatable {
    let mediaBox: CGRect
    let trimBox: CGRect
    let bleedBox: CGRect
    let cropBox: CGRect
    let trimOffset: CGSize

    var pageInfo: [String: Any] {
        [
            kCGPDFContextMediaBox as String: Self.boxData(mediaBox),
            kCGPDFContextTrimBox as String: Self.boxData(trimBox),
            kCGPDFContextBleedBox as String: Self.boxData(bleedBox),
            kCGPDFContextCropBox as String: Self.boxData(cropBox)
        ]
    }

    private static func boxData(_ rect: CGRect) -> Data {
        var rect = rect
        return Data(bytes: &rect, count: MemoryLayout<CGRect>.size)
    }
}

nonisolated struct PDFX4ProductionProfile {
    let outputConditionIdentifier: String
    let outputCondition: String
    let registryName: String
    let info: String

    static let `default` = PDFX4ProductionProfile(
        outputConditionIdentifier: "Generic CMYK",
        outputCondition: "Generic CMYK print output condition",
        registryName: "https://www.color.org",
        info: "CoreGraphics Generic CMYK ICC profile embedded as the PDF/X output intent."
    )

    static let implementedCapabilities: [String] = [
        "PDF/X-4 target XMP metadata",
        "PDF-1.6 header normalization after CoreGraphics rendering",
        "Output Intent",
        "ICC profile embedding through CGColorSpace",
        "MediaBox / TrimBox / BleedBox / CropBox",
        "Unencrypted PDF output",
        "Vector text, rules, crop marks, page numbers, and QR code drawing"
    ]

    // CoreGraphics can write PDF/X-related metadata, boxes, and Output Intent,
    // but it does not expose a full PDF/X-4 conformance switch or validator.
    // Keep these gaps explicit so a future veraPDF/Ghostscript validation layer
    // can replace this profile boundary instead of scattering checks.
    static let unsupportedCapabilities: [String] = [
        "Automated PDF/X-4 conformance validation",
        "Print-shop-specific ICC profile selection",
        "Guaranteed PDF/X-4 low-level object constraints beyond the patched header",
        "Post-export verification that every font subset is embedded"
    ]

    var outputIntentColorSpace: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.genericCMYK)
            ?? CGColorSpace(name: CGColorSpace.sRGB)
    }

    var outputIntentICCProfileData: CFData? {
        guard let outputIntentColorSpace else { return nil }
        return outputIntentColorSpace.copyICCData()
    }

    var hasEmbeddableICCProfile: Bool {
        outputIntentICCProfileData != nil
    }

    var outputIntent: [String: Any]? {
        guard let outputIntentColorSpace, outputIntentICCProfileData != nil else { return nil }

        return [
            kCGPDFXOutputIntentSubtype as String: "GTS_PDFX",
            kCGPDFXOutputConditionIdentifier as String: outputConditionIdentifier,
            kCGPDFXOutputCondition as String: outputCondition,
            kCGPDFXRegistryName as String: registryName,
            kCGPDFXInfo as String: info,
            kCGPDFXDestinationOutputProfile as String: outputIntentColorSpace
        ]
    }

    func documentInfo(title: String) -> [String: Any] {
        var info: [String: Any] = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Honkumi",
            kCGPDFContextSubject as String: "Print production PDF for PDF/X-4 validation, unverified",
            kCGPDFContextKeywords as String: "PDF/X-4 target, unverified, print, Honkumi"
        ]

        if let outputIntent {
            info[kCGPDFContextOutputIntent as String] = outputIntent
        }

        return info
    }

    func xmpMetadataData(title: String, documentID: UUID, createdAt: Date = Date()) -> Data? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAtString = formatter.string(from: createdAt)
        let escapedTitle = Self.xmlEscaped(title)
        let escapedID = Self.xmlEscaped(documentID.uuidString)

        let xmp = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Honkumi">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:pdfxid="http://www.npes.org/pdfx/ns/id/"
              pdfxid:GTS_PDFXVersion="PDF/X-4"
              pdfxid:GTS_PDFXConformance="PDF/X-4" />
            <rdf:Description rdf:about=""
              xmlns:honkumi="https://honkumi.jp/ns/pdf/"
              honkumi:PDFXTarget="PDF/X-4"
              honkumi:PDFXVerificationStatus="unverified" />
            <rdf:Description rdf:about=""
              xmlns:pdf="http://ns.adobe.com/pdf/1.3/"
              pdf:Producer="Honkumi" />
            <rdf:Description rdf:about=""
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmp:CreatorTool="Honkumi"
              xmp:CreateDate="\(createdAtString)"
              xmp:MetadataDate="\(createdAtString)" />
            <rdf:Description rdf:about=""
              xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
              xmpMM:DocumentID="uuid:\(escapedID)"
              xmpMM:InstanceID="uuid:\(UUID().uuidString)" />
            <rdf:Description rdf:about=""
              xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:format>application/pdf</dc:format>
              <dc:title>
                <rdf:Alt>
                  <rdf:li xml:lang="x-default">\(escapedTitle)</rdf:li>
                </rdf:Alt>
              </dc:title>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

        return xmp.data(using: .utf8)
    }

    private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

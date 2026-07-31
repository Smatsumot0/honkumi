import CoreGraphics
import Foundation
import PDFKit
@testable import Honkumi
import XCTest

nonisolated struct PassthroughPDFFinalizer: PDFFileFinalizing {
    func finalize(at url: URL) throws {}
}

enum PDFTestFixtureBuilder {
    static func pdfWithCatalogReference(_ reference: String) -> Data {
        malformedQuartzStylePDF(catalogReference: reference)
    }

    static func incorrectPositiveOffsetPDF() -> Data {
        replacingFirst(
            malformedQuartzStylePDF(),
            "0000000009 00000 n ",
            with: "0000000010 00000 n "
        )
    }

    static func duplicateXRefObjectNumberPDF() -> Data {
        replacingFirst(
            malformedQuartzStylePDF(),
            "0000000000 00000 n \ntrailer",
            with: "0000000000 00000 n \n1 1\n0000000009 00000 n \ntrailer"
        )
    }

    static func incrementalUpdatePDF() -> Data {
        replacingFirst(
            malformedQuartzStylePDF(),
            " /Info 3 0 R >>",
            with: " /Info 3 0 R /Prev 0 >>"
        )
    }

    static func encryptedPDF() -> Data {
        replacingFirst(
            malformedQuartzStylePDF(),
            " /Info 3 0 R >>",
            with: " /Info 3 0 R /Encrypt 4 0 R >>"
        )
    }

    static func pdfWithStream(
        lengthEntries: String,
        payload: String,
        additionalObjects: [String] = []
    ) -> Data {
        var data = Data("%PDF-1.3\n".utf8)
        var offsets: [Int: Int] = [:]

        func appendObject(_ number: Int, _ body: String) {
            offsets[number] = data.count
            data.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
        }

        appendObject(1, "<< /Type /Catalog /Pages 2 0 R >>")
        appendObject(2, "<< /Type /Pages /Count 0 /Kids [] >>")
        appendObject(3, "<< /Title (Fixture) >>")
        appendObject(4, "<< \(lengthEntries) >>\nstream\n\(payload)\nendstream")
        for (index, object) in additionalObjects.enumerated() {
            appendObject(index + 5, object)
        }

        let xrefOffset = data.count
        let size = additionalObjects.count + 5
        data.append(Data("xref\n0 \(size)\n".utf8))
        data.append(Data("0000000000 65535 f \n".utf8))
        for number in 1..<size {
            data.append(Data(String(format: "%010d 00000 n \n", offsets[number]!).utf8))
        }
        data.append(Data("""
        trailer
        << /Size \(size) /Root 1 0 R /Info 3 0 R >>
        startxref
        \(xrefOffset)
        %%EOF
        """.utf8))
        return data
    }

    static func malformedQuartzStylePDF(
        trappedValue: String? = nil,
        additionalTrailerEntries: String = "",
        catalogReference: String? = nil,
        additionalCatalogEntries: String = "",
        catalogPostamble: String = ""
    ) -> Data {
        var data = Data("%PDF-1.3\n".utf8)
        var offsets: [Int: Int] = [:]

        func appendObject(_ number: Int, _ body: String) {
            offsets[number] = data.count
            data.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
        }

        let brokenReference = catalogReference.map { " /Broken \($0)" } ?? ""
        appendObject(
            1,
            "<< /Type /Catalog /Pages 2 0 R\(brokenReference)\(additionalCatalogEntries) >>\(catalogPostamble)"
        )
        appendObject(2, "<< /Type /Pages /Count 0 /Kids [] >>")
        let trapped = trappedValue.map { " /Trapped \($0)" } ?? ""
        appendObject(3, "<< /Title (Fixture)\(trapped) >>")

        let xrefOffset = data.count
        data.append(Data("xref\n0 5\n".utf8))
        data.append(Data("0000000000 65535 f \n".utf8))
        for number in 1...3 {
            data.append(Data(String(format: "%010d 00000 n \n", offsets[number]!).utf8))
        }
        data.append(Data("0000000000 00000 n \n".utf8))
        data.append(Data("""
        trailer
        << /Size 5 /Root 1 0 R /Info 3 0 R\(additionalTrailerEntries) >>
        startxref
        \(xrefOffset)
        %%EOF
        """.utf8))
        return data
    }

    static func replacingFirst(_ source: Data, _ old: String, with new: String) -> Data {
        let oldData = Data(old.utf8)
        guard let range = source.range(of: oldData) else {
            preconditionFailure("Fixture replacement text was not found: \(old)")
        }
        var result = Data(source[..<range.lowerBound])
        result.append(Data(new.utf8))
        result.append(source[range.upperBound..<source.count])
        return result
    }
}

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

enum PDFX4TestInspectionError: Error, Equatable {
    case unreadablePDF
    case missingCatalog
    case invalidCatalog
    case missingInfo
    case missingValue(String)
    case invalidICCProfile
    case invalidXMP
    case missingEmbeddedFont(String)
}

enum PDFX4TestInspector {
    static func inspect(_ data: Data) throws -> PDFX4SemanticSnapshot {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let document = CGPDFDocument(provider)
        else {
            throw PDFX4TestInspectionError.unreadablePDF
        }
        guard let catalog = document.catalog else {
            throw PDFX4TestInspectionError.missingCatalog
        }
        guard name(in: catalog, key: "Type") == "Catalog" else {
            throw PDFX4TestInspectionError.invalidCatalog
        }
        guard let info = document.info else {
            throw PDFX4TestInspectionError.missingInfo
        }

        var majorVersion: Int32 = 0
        var minorVersion: Int32 = 0
        document.getVersion(majorVersion: &majorVersion, minorVersion: &minorVersion)

        let trappedName = try requiredName(in: info, key: "Trapped")
        let infoTitle = try requiredString(in: info, key: "Title")
        let infoCreator = try requiredString(in: info, key: "Creator")

        var outputIntents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(catalog, "OutputIntents", &outputIntents),
              let outputIntents,
              CGPDFArrayGetCount(outputIntents) == 1 else {
            throw PDFX4TestInspectionError.missingValue("OutputIntents")
        }
        var outputIntent: CGPDFDictionaryRef?
        guard CGPDFArrayGetDictionary(outputIntents, 0, &outputIntent), let outputIntent else {
            throw PDFX4TestInspectionError.missingValue("OutputIntent")
        }
        let outputIntentSubtype = try requiredName(in: outputIntent, key: "S")
        let outputConditionIdentifier = try requiredString(
            in: outputIntent,
            key: "OutputConditionIdentifier"
        )

        var iccStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(outputIntent, "DestOutputProfile", &iccStream),
              let iccStream,
              let iccDictionary = CGPDFStreamGetDictionary(iccStream) else {
            throw PDFX4TestInspectionError.missingValue("DestOutputProfile")
        }
        var componentCount: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(iccDictionary, "N", &componentCount) else {
            throw PDFX4TestInspectionError.missingValue("DestOutputProfile.N")
        }
        let iccData = try decodedData(from: iccStream, label: "DestOutputProfile")
        guard iccData.count >= 40,
              iccData.subdata(in: 36..<40) == Data("acsp".utf8) else {
            throw PDFX4TestInspectionError.invalidICCProfile
        }
        let iccColorSpace = CGColorSpace(iccData: iccData as CFData)

        var metadataStream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &metadataStream),
              let metadataStream else {
            throw PDFX4TestInspectionError.missingValue("Metadata")
        }
        let metadata = try decodedData(from: metadataStream, label: "Metadata")
        let xmp = try xmpSnapshot(from: metadata)

        var embeddedBaseFontNames = Set<String>()
        var unresolvedColorSpaceNames = Set<String>()
        var hasExternalReferences = false
        var hasPageJavaScript = false

        for pageNumber in 1...document.numberOfPages {
            guard let page = document.page(at: pageNumber),
                  let pageDictionary = page.dictionary else {
                throw PDFX4TestInspectionError.unreadablePDF
            }
            let resourceFeatures = try inspectPageResources(
                in: pageDictionary,
                embeddedBaseFontNames: &embeddedBaseFontNames,
                unresolvedColorSpaceNames: &unresolvedColorSpaceNames
            )
            var pageFeatures = pageForbiddenFeatures(pageDictionary)
            pageFeatures.merge(resourceFeatures)
            hasExternalReferences = hasExternalReferences
                || pageFeatures.hasExternalReferences
            hasPageJavaScript = hasPageJavaScript || pageFeatures.hasJavaScript
        }

        var namesDictionary: CGPDFDictionaryRef?
        let hasNames = CGPDFDictionaryGetDictionary(catalog, "Names", &namesDictionary)
        let hasAssociatedFiles = containsObject(in: catalog, key: "AF")
        let hasEmbeddedFiles = hasAssociatedFiles || (hasNames
            && namesDictionary.map { containsObject(in: $0, key: "EmbeddedFiles") } == true
        )
        let hasNamesJavaScript = hasNames
            && namesDictionary.map { containsObject(in: $0, key: "JavaScript") } == true
        let openActionFeatures = actionFeatures(in: catalog, key: "OpenAction")
        let additionalActionFeatures = actionFeatures(in: catalog, key: "AA")
        let outlineFeatures = catalogOutlineFeatures(catalog)
        let hasCatalogJavaScript = containsObject(in: catalog, key: "JavaScript")
            || openActionFeatures.hasJavaScript
            || additionalActionFeatures.hasJavaScript
            || outlineFeatures.hasJavaScript
        let hasOptionalContent = containsObject(in: catalog, key: "OCProperties")
        hasExternalReferences = hasExternalReferences
            || hasOptionalContent
            || hasAssociatedFiles
            || containsObject(in: catalog, key: "URI")
            || containsObject(in: catalog, key: "Collection")
            || openActionFeatures.hasExternalReferences
            || additionalActionFeatures.hasExternalReferences
            || outlineFeatures.hasExternalReferences

        return PDFX4SemanticSnapshot(
            version: "\(majorVersion).\(minorVersion)",
            trappedName: trappedName,
            outputIntentSubtype: outputIntentSubtype,
            outputConditionIdentifier: outputConditionIdentifier,
            catalogVersion: name(in: catalog, key: "Version"),
            iccComponentCount: Int(componentCount),
            iccData: iccData,
            iccLoadsAsFourComponentColorSpace: iccColorSpace?.numberOfComponents == 4,
            pdfXVersionCount: xmp.pdfXVersionCount,
            pdfXConformanceCount: xmp.pdfXConformanceCount,
            infoTitle: infoTitle,
            xmpTitle: xmp.title,
            infoCreator: infoCreator,
            xmpCreatorTool: xmp.creatorTool,
            isEncrypted: document.isEncrypted,
            hasAcroForm: containsObject(in: catalog, key: "AcroForm"),
            hasJavaScript: hasCatalogJavaScript || hasNamesJavaScript || hasPageJavaScript,
            hasEmbeddedFiles: hasEmbeddedFiles,
            hasExternalReferences: hasExternalReferences,
            unresolvedColorSpaceNames: unresolvedColorSpaceNames,
            embeddedBaseFontNames: embeddedBaseFontNames
        )
    }

    static func infoObjectBody(in data: Data) throws -> Data {
        let structure = try PDFX4StructureFinalizer.structure(in: data)
        guard let body = structure.objectBodies[structure.infoReference] else {
            throw PDFX4FinalizationError.missingReference(structure.infoReference)
        }
        return body
    }

    static func occurrenceCount(of needle: Data, in haystack: Data) -> Int {
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var lowerBound = haystack.startIndex
        while lowerBound < haystack.endIndex,
              let range = haystack.range(of: needle, in: lowerBound..<haystack.endIndex) {
            count += 1
            lowerBound = range.upperBound
        }
        return count
    }

    private static func inspectPageResources(
        in page: CGPDFDictionaryRef,
        embeddedBaseFontNames: inout Set<String>,
        unresolvedColorSpaceNames: inout Set<String>
    ) throws -> ForbiddenFeatureSnapshot {
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources else {
            for stream in contentStreams(in: page, key: "Contents") {
                unresolvedColorSpaceNames.formUnion(
                    usedColorSpaceNames(in: try decodedData(from: stream, label: "Contents"))
                        .subtracting(acceptedColorSpaceNames)
                )
            }
            return .init()
        }

        return try inspectResources(
            resources,
            contentStreams: contentStreams(in: page, key: "Contents"),
            path: "Page",
            depth: 0,
            embeddedBaseFontNames: &embeddedBaseFontNames,
            unresolvedColorSpaceNames: &unresolvedColorSpaceNames
        )
    }

    private static func inspectResources(
        _ resources: CGPDFDictionaryRef,
        contentStreams: [CGPDFStreamRef],
        path: String,
        depth: Int,
        embeddedBaseFontNames: inout Set<String>,
        unresolvedColorSpaceNames: inout Set<String>
    ) throws -> ForbiddenFeatureSnapshot {
        guard depth < 32 else {
            unresolvedColorSpaceNames.insert("\(path).recursive-resources")
            return .init(hasExternalReferences: true)
        }

        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
            for (resourceName, object) in entries(in: fonts) {
                guard let font = dictionary(from: object) else {
                    throw PDFX4TestInspectionError.missingEmbeddedFont(resourceName)
                }
                try inspectFont(font, embeddedBaseFontNames: &embeddedBaseFontNames)
            }
        }

        var colorSpaces: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "ColorSpace", &colorSpaces), let colorSpaces {
            for (resourceName, object) in entries(in: colorSpaces)
                where !isResolvedColorSpace(object) {
                unresolvedColorSpaceNames.insert(resourceName)
            }
        }

        for stream in contentStreams {
            let data = try decodedData(from: stream, label: "\(path).Contents")
            for colorSpaceName in usedColorSpaceNames(in: data)
                where !acceptedColorSpaceNames.contains(colorSpaceName) {
                var definition: CGPDFObjectRef?
                guard let colorSpaces,
                      CGPDFDictionaryGetObject(
                        colorSpaces,
                        colorSpaceName,
                        &definition
                      ), let definition,
                      isResolvedColorSpace(definition) else {
                    unresolvedColorSpaceNames.insert(colorSpaceName)
                    continue
                }
            }
        }

        var result = ForbiddenFeatureSnapshot()
        var xObjects: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects {
            for (resourceName, object) in entries(in: xObjects) {
                guard let xObject = stream(from: object),
                      let dictionary = CGPDFStreamGetDictionary(xObject) else {
                    result.hasExternalReferences = true
                    continue
                }
                let subtype = name(in: dictionary, key: "Subtype")
                if subtype == "PS"
                    || containsObject(in: dictionary, key: "Ref")
                    || containsObject(in: dictionary, key: "OC") {
                    result.hasExternalReferences = true
                }
                if subtype == "Image",
                   let colorSpace = dictionaryObject(in: dictionary, key: "ColorSpace"),
                   !isResolvedColorSpace(colorSpace, definitions: colorSpaces) {
                    unresolvedColorSpaceNames.insert("\(resourceName).ColorSpace")
                }
                if subtype == "Form" {
                    var nestedResources: CGPDFDictionaryRef?
                    if CGPDFDictionaryGetDictionary(
                        dictionary,
                        "Resources",
                        &nestedResources
                    ), let nestedResources {
                        result.merge(try inspectResources(
                            nestedResources,
                            contentStreams: [xObject],
                            path: "\(path).\(resourceName)",
                            depth: depth + 1,
                            embeddedBaseFontNames: &embeddedBaseFontNames,
                            unresolvedColorSpaceNames: &unresolvedColorSpaceNames
                        ))
                    } else {
                        let usedNames = usedColorSpaceNames(
                            in: try decodedData(from: xObject, label: resourceName)
                        )
                        unresolvedColorSpaceNames.formUnion(
                            usedNames.subtracting(acceptedColorSpaceNames)
                        )
                    }
                }
            }
        }

        var patterns: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Pattern", &patterns), let patterns {
            for (resourceName, object) in entries(in: patterns) {
                if let patternStream = stream(from: object),
                   let dictionary = CGPDFStreamGetDictionary(patternStream) {
                    var nestedResources: CGPDFDictionaryRef?
                    if CGPDFDictionaryGetDictionary(
                        dictionary,
                        "Resources",
                        &nestedResources
                    ), let nestedResources {
                        result.merge(try inspectResources(
                            nestedResources,
                            contentStreams: [patternStream],
                            path: "\(path).Pattern.\(resourceName)",
                            depth: depth + 1,
                            embeddedBaseFontNames: &embeddedBaseFontNames,
                            unresolvedColorSpaceNames: &unresolvedColorSpaceNames
                        ))
                    }
                }
            }
        }

        var shadings: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Shading", &shadings), let shadings {
            for (resourceName, object) in entries(in: shadings) {
                guard let dictionary = dictionary(from: object),
                      let colorSpace = dictionaryObject(
                        in: dictionary,
                        key: "ColorSpace"
                      ),
                      isResolvedColorSpace(colorSpace, definitions: colorSpaces) else {
                    unresolvedColorSpaceNames.insert("\(resourceName).ColorSpace")
                    continue
                }
            }
        }

        var properties: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Properties", &properties),
           let properties,
           entries(in: properties).contains(where: { _, object in
               guard let dictionary = dictionary(from: object) else { return false }
               return ["OCG", "OCMD"].contains(name(in: dictionary, key: "Type"))
           }) {
            result.hasExternalReferences = true
        }
        return result
    }

    private static func inspectFont(
        _ font: CGPDFDictionaryRef,
        embeddedBaseFontNames: inout Set<String>
    ) throws {
        let baseFontName = normalizedFontName(name(in: font, key: "BaseFont") ?? "unknown")
        let subtype = name(in: font, key: "Subtype")
        var descendantFonts: CGPDFArrayRef?
        if subtype == "Type0" {
            guard CGPDFDictionaryGetArray(font, "DescendantFonts", &descendantFonts),
                  let descendantFonts,
                  CGPDFArrayGetCount(descendantFonts) > 0 else {
                throw PDFX4TestInspectionError.missingEmbeddedFont(baseFontName)
            }
            for index in 0..<CGPDFArrayGetCount(descendantFonts) {
                var descendant: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(descendantFonts, index, &descendant),
                      let descendant else {
                    throw PDFX4TestInspectionError.missingEmbeddedFont(baseFontName)
                }
                try inspectFont(descendant, embeddedBaseFontNames: &embeddedBaseFontNames)
            }
            return
        }

        if subtype == "Type3" {
            var characterProcedures: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(
                font,
                "CharProcs",
                &characterProcedures
            ), let characterProcedures else {
                throw PDFX4TestInspectionError.missingEmbeddedFont(baseFontName)
            }
            let procedures = entries(in: characterProcedures)
            guard !procedures.isEmpty,
                  procedures.allSatisfy({ _, object in
                      guard let stream = stream(from: object),
                            let data = try? decodedData(from: stream, label: "CharProcs") else {
                          return false
                      }
                      return !data.isEmpty
                  }) else {
                throw PDFX4TestInspectionError.missingEmbeddedFont(baseFontName)
            }
            embeddedBaseFontNames.insert(baseFontName)
            return
        }

        var descriptor: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(font, "FontDescriptor", &descriptor),
              let descriptor else {
            throw PDFX4TestInspectionError.missingEmbeddedFont(baseFontName)
        }
        let descriptorName = normalizedFontName(
            name(in: descriptor, key: "FontName") ?? baseFontName
        )
        let embeddedKeys = ["FontFile", "FontFile2", "FontFile3"]
        let hasNonEmptyEmbeddedStream = embeddedKeys.contains { key in
            guard let stream = stream(in: descriptor, key: key),
                  let data = try? decodedData(from: stream, label: key) else {
                return false
            }
            return !data.isEmpty
        }
        guard hasNonEmptyEmbeddedStream else {
            throw PDFX4TestInspectionError.missingEmbeddedFont(descriptorName)
        }
        embeddedBaseFontNames.insert(descriptorName)
    }

    private static func isResolvedColorSpace(_ object: CGPDFObjectRef) -> Bool {
        if let value = name(from: object) {
            return acceptedColorSpaceNames.contains(value)
        }
        guard let array = array(from: object), CGPDFArrayGetCount(array) > 0 else {
            return false
        }
        var familyPointer: UnsafePointer<CChar>?
        guard CGPDFArrayGetName(array, 0, &familyPointer), let familyPointer else {
            return false
        }
        let family = String(cString: familyPointer)
        switch family {
        case "DeviceGray", "DeviceRGB", "DeviceCMYK", "Pattern":
            if family == "Pattern", CGPDFArrayGetCount(array) > 1,
               let base = arrayObject(in: array, at: 1) {
                return isResolvedColorSpace(base)
            }
            return true
        case "ICCBased":
            guard CGPDFArrayGetCount(array) == 2,
                  let profile = stream(in: array, at: 1),
                  let profileDictionary = CGPDFStreamGetDictionary(profile) else {
                return false
            }
            var components: CGPDFInteger = 0
            return CGPDFDictionaryGetInteger(profileDictionary, "N", &components)
                && (components == 1 || components == 3 || components == 4)
                && ((try? decodedData(from: profile, label: "ICCBased"))?.isEmpty == false)
        default:
            return false
        }
    }

    private static func isResolvedColorSpace(
        _ object: CGPDFObjectRef,
        definitions: CGPDFDictionaryRef?
    ) -> Bool {
        guard let referencedName = name(from: object),
              !acceptedColorSpaceNames.contains(referencedName) else {
            return isResolvedColorSpace(object)
        }
        var definition: CGPDFObjectRef?
        return definitions.map {
            CGPDFDictionaryGetObject($0, referencedName, &definition)
        } == true && definition.map(isResolvedColorSpace) == true
    }

    private static let acceptedColorSpaceNames: Set<String> = [
        "DeviceGray", "DeviceRGB", "DeviceCMYK", "Pattern"
    ]

    private static func contentStreams(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> [CGPDFStreamRef] {
        if let direct = stream(in: dictionary, key: key) {
            return [direct]
        }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array else {
            return []
        }
        return (0..<CGPDFArrayGetCount(array)).compactMap {
            stream(in: array, at: $0)
        }
    }

    private static func usedColorSpaceNames(in data: Data) -> Set<String> {
        var cursor = PDFContentTokenCursor(data: data)
        var previousName: String?
        var inlineImageKey: String?
        var isInsideInlineImage = false
        var result = Set<String>()
        while let token = cursor.next() {
            switch token {
            case let .name(name):
                if isInsideInlineImage {
                    if inlineImageKey == "CS" || inlineImageKey == "ColorSpace" {
                        result.insert(name)
                        inlineImageKey = nil
                    } else {
                        inlineImageKey = name
                    }
                    previousName = nil
                    continue
                }
                previousName = name
            case let .word(word) where word == "CS" || word == "cs":
                if let previousName {
                    result.insert(previousName)
                }
                previousName = nil
            case .word("BI"):
                isInsideInlineImage = true
                inlineImageKey = nil
                previousName = nil
            case .word("ID"):
                isInsideInlineImage = false
                inlineImageKey = nil
                previousName = nil
                cursor.skipInlineImageData()
            case .word, .other:
                if isInsideInlineImage, inlineImageKey != nil {
                    inlineImageKey = nil
                }
                previousName = nil
            }
        }
        return result
    }

    private static func pageForbiddenFeatures(
        _ page: CGPDFDictionaryRef
    ) -> ForbiddenFeatureSnapshot {
        var result = actionFeatures(in: page, key: "AA")
        if containsObject(in: page, key: "AF") {
            result.hasExternalReferences = true
        }
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(page, "Annots", &annotations), let annotations else {
            return result
        }
        let forbiddenSubtypes: Set<String> = [
            "Widget", "FileAttachment", "Sound", "Movie", "Screen", "PrinterMark",
            "TrapNet", "Watermark", "3D", "Redact", "RichMedia", "Projection"
        ]
        for index in 0..<CGPDFArrayGetCount(annotations) {
            var annotation: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotations, index, &annotation), let annotation else {
                result.hasExternalReferences = true
                continue
            }
            if name(in: annotation, key: "Subtype").map(forbiddenSubtypes.contains) == true
                || containsObject(in: annotation, key: "FS")
                || containsObject(in: annotation, key: "AF")
                || containsObject(in: annotation, key: "OC") {
                result.hasExternalReferences = true
            }
            var annotationFlags: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(annotation, "F", &annotationFlags),
               annotationFlags & 4 != 0 {
                result.hasExternalReferences = true
            }
            result.merge(actionFeatures(in: annotation, key: "A"))
            result.merge(actionFeatures(in: annotation, key: "AA"))
        }
        return result
    }

    private static func catalogOutlineFeatures(
        _ catalog: CGPDFDictionaryRef
    ) -> ForbiddenFeatureSnapshot {
        var outlines: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Outlines", &outlines),
              let outlines else {
            return .init()
        }
        return outlineFeatures(in: outlines, childKey: "First", depth: 0)
    }

    private static func outlineFeatures(
        in parent: CGPDFDictionaryRef,
        childKey: String,
        depth: Int
    ) -> ForbiddenFeatureSnapshot {
        guard depth < 256 else {
            return .init(hasExternalReferences: true)
        }
        var child: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(parent, childKey, &child), let child else {
            return .init()
        }
        var result = actionFeatures(in: child, key: "A")
        result.merge(actionFeatures(in: child, key: "AA"))
        if containsObject(in: child, key: "FS")
            || containsObject(in: child, key: "AF") {
            result.hasExternalReferences = true
        }
        result.merge(outlineFeatures(in: child, childKey: "First", depth: depth + 1))
        result.merge(outlineFeatures(in: child, childKey: "Next", depth: depth + 1))
        return result
    }

    private static func actionFeatures(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> ForbiddenFeatureSnapshot {
        var action: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, key, &action), let action else {
            return .init()
        }
        return actionFeatures(from: action, collection: key == "AA")
    }

    private static func actionFeatures(
        from object: CGPDFObjectRef,
        collection: Bool = false
    ) -> ForbiddenFeatureSnapshot {
        if let array = array(from: object) {
            var result = ForbiddenFeatureSnapshot()
            for index in 0..<CGPDFArrayGetCount(array) {
                if let item = arrayObject(in: array, at: index) {
                    result.merge(actionFeatures(from: item))
                }
            }
            return result
        }
        guard let dictionary = dictionary(from: object) else { return .init() }
        if collection {
            var result = ForbiddenFeatureSnapshot()
            for (_, value) in entries(in: dictionary) {
                result.merge(actionFeatures(from: value))
            }
            return result
        }

        let actionName = name(in: dictionary, key: "S")
        let externalActionNames: Set<String> = [
            "GoToR", "GoToE", "Launch", "URI", "Rendition", "Movie", "Sound",
            "SubmitForm", "ImportData"
        ]
        var result = ForbiddenFeatureSnapshot(
            hasJavaScript: actionName == "JavaScript",
            hasExternalReferences: actionName.map(externalActionNames.contains) == true
                || containsObject(in: dictionary, key: "F")
                || containsObject(in: dictionary, key: "FS")
        )
        if let next = dictionaryObject(in: dictionary, key: "Next") {
            result.merge(actionFeatures(from: next))
        }
        return result
    }

    private static func xmpSnapshot(from data: Data) throws -> PDFXMPTestSnapshot {
        let delegate = PDFXMPTestParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(),
              !delegate.hasInvalidPDFXIdentifier,
              delegate.defaultTitleCount == 1 else {
            throw PDFX4TestInspectionError.invalidXMP
        }
        return PDFXMPTestSnapshot(
            pdfXVersionCount: delegate.pdfXVersionCount,
            pdfXConformanceCount: delegate.pdfXConformanceCount,
            title: delegate.title,
            creatorTool: delegate.creatorTool
        )
    }

    private static func decodedData(
        from stream: CGPDFStreamRef,
        label: String
    ) throws -> Data {
        var format = CGPDFDataFormat.raw
        guard let copied = CGPDFStreamCopyData(stream, &format) else {
            throw PDFX4TestInspectionError.missingValue(label)
        }
        return copied as Data
    }

    private static func requiredName(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) throws -> String {
        guard let value = name(in: dictionary, key: key) else {
            throw PDFX4TestInspectionError.missingValue(key)
        }
        return value
    }

    private static func requiredString(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) throws -> String {
        guard let value = string(in: dictionary, key: key) else {
            throw PDFX4TestInspectionError.missingValue(key)
        }
        return value
    }

    private static func containsObject(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> Bool {
        var object: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dictionary, key, &object)
    }

    private static func dictionaryObject(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> CGPDFObjectRef? {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, key, &object) else { return nil }
        return object
    }

    private static func name(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> String? {
        var pointer: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &pointer), let pointer else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func string(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value),
              let value,
              let text = CGPDFStringCopyTextString(value) else {
            return nil
        }
        return text as String
    }

    private static func name(from object: CGPDFObjectRef) -> String? {
        var pointer: UnsafePointer<CChar>?
        guard CGPDFObjectGetValue(object, .name, &pointer), let pointer else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func dictionary(from object: CGPDFObjectRef) -> CGPDFDictionaryRef? {
        var dictionary: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dictionary) else { return nil }
        return dictionary
    }

    private static func array(from object: CGPDFObjectRef) -> CGPDFArrayRef? {
        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(object, .array, &array) else { return nil }
        return array
    }

    private static func arrayObject(
        in array: CGPDFArrayRef,
        at index: Int
    ) -> CGPDFObjectRef? {
        var object: CGPDFObjectRef?
        guard CGPDFArrayGetObject(array, index, &object) else { return nil }
        return object
    }

    private static func stream(
        in dictionary: CGPDFDictionaryRef,
        key: String
    ) -> CGPDFStreamRef? {
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dictionary, key, &stream) else { return nil }
        return stream
    }

    private static func stream(in array: CGPDFArrayRef, at index: Int) -> CGPDFStreamRef? {
        var stream: CGPDFStreamRef?
        guard CGPDFArrayGetStream(array, index, &stream) else { return nil }
        return stream
    }

    private static func stream(from object: CGPDFObjectRef) -> CGPDFStreamRef? {
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream) else { return nil }
        return stream
    }

    private static func entries(
        in dictionary: CGPDFDictionaryRef
    ) -> [(String, CGPDFObjectRef)] {
        var entries: [(String, CGPDFObjectRef)] = []
        CGPDFDictionaryApplyBlock(dictionary, { key, value, _ in
            entries.append((String(cString: key), value))
            return true
        }, nil)
        return entries
    }

    private static func normalizedFontName(_ name: String) -> String {
        let components = name.split(separator: "+", maxSplits: 1).map(String.init)
        guard components.count == 2,
              components[0].count == 6,
              components[0].allSatisfy({ $0.isASCII && $0.isUppercase }) else {
            return name
        }
        return components[1]
    }
}

private struct ForbiddenFeatureSnapshot {
    var hasJavaScript = false
    var hasExternalReferences = false

    mutating func merge(_ other: ForbiddenFeatureSnapshot) {
        hasJavaScript = hasJavaScript || other.hasJavaScript
        hasExternalReferences = hasExternalReferences || other.hasExternalReferences
    }
}

private enum PDFContentToken {
    case name(String)
    case word(String)
    case other
}

private struct PDFContentTokenCursor {
    private let data: Data
    private var position = 0

    init(data: Data) {
        self.data = data
    }

    mutating func next() -> PDFContentToken? {
        skipWhitespaceAndComments()
        guard position < data.count else { return nil }

        switch data[position] {
        case 0x2F:
            position += 1
            let start = position
            while position < data.count,
                  !Self.isWhitespace(data[position]),
                  !Self.isDelimiter(data[position]) {
                position += 1
            }
            return .name(Self.decodedName(Data(data[start..<position])))
        case 0x28:
            skipLiteralString()
            return .other
        case 0x3C:
            skipHexStringOrDictionaryStart()
            return .other
        case 0x3E:
            position += 1
            if position < data.count, data[position] == 0x3E {
                position += 1
            }
            return .other
        case 0x5B, 0x5D, 0x7B, 0x7D:
            position += 1
            return .other
        default:
            let start = position
            while position < data.count,
                  !Self.isWhitespace(data[position]),
                  !Self.isDelimiter(data[position]) {
                position += 1
            }
            guard position > start,
                  let word = String(data: data[start..<position], encoding: .ascii) else {
                position += 1
                return .other
            }
            return .word(word)
        }
    }

    mutating func skipInlineImageData() {
        if position < data.count, Self.isWhitespace(data[position]) {
            position += 1
        }
        while position + 3 < data.count {
            if Self.isWhitespace(data[position]),
               data[position + 1] == 0x45,
               data[position + 2] == 0x49,
               Self.isWhitespace(data[position + 3]) {
                position += 3
                return
            }
            position += 1
        }
        position = data.count
    }

    private mutating func skipWhitespaceAndComments() {
        while position < data.count {
            if Self.isWhitespace(data[position]) {
                position += 1
                continue
            }
            guard data[position] == 0x25 else { return }
            while position < data.count, data[position] != 0x0A, data[position] != 0x0D {
                position += 1
            }
        }
    }

    private mutating func skipLiteralString() {
        position += 1
        var depth = 1
        while position < data.count, depth > 0 {
            switch data[position] {
            case 0x5C:
                position = min(position + 2, data.count)
            case 0x28:
                depth += 1
                position += 1
            case 0x29:
                depth -= 1
                position += 1
            default:
                position += 1
            }
        }
    }

    private mutating func skipHexStringOrDictionaryStart() {
        position += 1
        if position < data.count, data[position] == 0x3C {
            position += 1
            return
        }
        while position < data.count {
            let byte = data[position]
            position += 1
            if byte == 0x3E { return }
        }
    }

    private static func decodedName(_ raw: Data) -> String {
        var decoded = Data()
        var index = 0
        while index < raw.count {
            if raw[index] == 0x23,
               index + 2 < raw.count,
               let high = hexValue(raw[index + 1]),
               let low = hexValue(raw[index + 2]) {
                decoded.append(high << 4 | low)
                index += 3
            } else {
                decoded.append(raw[index])
                index += 1
            }
        }
        return String(data: decoded, encoding: .utf8)
            ?? String(decoding: decoded, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25:
            true
        default:
            false
        }
    }
}

private struct PDFXMPTestSnapshot {
    let pdfXVersionCount: Int
    let pdfXConformanceCount: Int
    let title: String
    let creatorTool: String
}

private final class PDFXMPTestParserDelegate: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var titleBuffer = ""
    private var isCapturingDefaultTitle = false

    private(set) var pdfXVersionCount = 0
    private(set) var pdfXConformanceCount = 0
    private(set) var title = ""
    private(set) var creatorTool = ""
    private(set) var hasInvalidPDFXIdentifier = false
    private(set) var defaultTitleCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        elementStack.append(elementName)
        if let value = attributeDict["pdfxid:GTS_PDFXVersion"] {
            pdfXVersionCount += 1
            hasInvalidPDFXIdentifier = hasInvalidPDFXIdentifier || value != "PDF/X-4"
        }
        if let value = attributeDict["pdfxid:GTS_PDFXConformance"] {
            pdfXConformanceCount += 1
            hasInvalidPDFXIdentifier = hasInvalidPDFXIdentifier || value != "PDF/X-4"
        }
        if let value = attributeDict["xmp:CreatorTool"] {
            creatorTool = value
        }
        if elementName == "rdf:li",
           elementStack.contains("dc:title"),
           attributeDict["xml:lang"] == "x-default" {
            defaultTitleCount += 1
            isCapturingDefaultTitle = true
            titleBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturingDefaultTitle {
            titleBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "rdf:li", isCapturingDefaultTitle {
            title = titleBuffer
            isCapturingDefaultTitle = false
        }
        _ = elementStack.popLast()
    }
}

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
    static func snapshots(
        from data: Data,
        scale: CGFloat = 2
    ) throws -> [PDFPageRegressionSnapshot] {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let coreGraphicsDocument = CGPDFDocument(provider),
            let pdfKitDocument = PDFDocument(data: data),
            coreGraphicsDocument.numberOfPages == pdfKitDocument.pageCount
        else {
            throw PDFX4TestInspectionError.unreadablePDF
        }

        return try (1...coreGraphicsDocument.numberOfPages).map { pageNumber in
            guard
                let coreGraphicsPage = coreGraphicsDocument.page(at: pageNumber),
                let pageDictionary = coreGraphicsPage.dictionary,
                let pdfKitPage = pdfKitDocument.page(at: pageNumber - 1)
            else {
                throw PDFX4TestInspectionError.unreadablePDF
            }

            return PDFPageRegressionSnapshot(
                mediaBox: coreGraphicsPage.getBoxRect(.mediaBox),
                trimBox: coreGraphicsPage.getBoxRect(.trimBox),
                bleedBox: coreGraphicsPage.getBoxRect(.bleedBox),
                cropBox: coreGraphicsPage.getBoxRect(.cropBox),
                decodedContentData: try PDFX4TestInspector.regressionContentData(
                    in: pageDictionary
                ),
                extractedText: pdfKitPage.string ?? "",
                rgbaPixels: try renderedRGBABytes(
                    for: coreGraphicsPage,
                    scale: scale
                )
            )
        }
    }

    private static func renderedRGBABytes(
        for page: CGPDFPage,
        scale: CGFloat
    ) throws -> Data {
        let mediaBox = page.getBoxRect(.mediaBox)
        let scaledWidth = ceil(mediaBox.width * scale)
        let scaledHeight = ceil(mediaBox.height * scale)
        guard
            scale.isFinite,
            scale > 0,
            scaledWidth.isFinite,
            scaledHeight.isFinite,
            scaledWidth > 0,
            scaledHeight > 0,
            scaledWidth <= CGFloat(Int.max / 4),
            scaledHeight <= CGFloat(Int.max)
        else {
            throw PDFX4TestInspectionError.unreadablePDF
        }

        let width = Int(scaledWidth)
        let height = Int(scaledHeight)
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, countOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !countOverflow else {
            throw PDFX4TestInspectionError.unreadablePDF
        }

        var pixels = Data(count: byteCount)
        try pixels.withUnsafeMutableBytes { buffer in
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
            guard
                let baseAddress = buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                )
            else {
                throw PDFX4TestInspectionError.unreadablePDF
            }

            context.setBlendMode(.copy)
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setBlendMode(.normal)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
            context.drawPDFPage(page)
            context.flush()
        }
        return pixels
    }
}

extension PDFX4TestInspector {
    static func assertNonInfoObjectBodiesEqual(
        before: Data,
        after: Data,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let beforeStructure = try PDFX4StructureFinalizer.structure(
            in: before,
            allowRepairableZeroOffsets: true
        )
        let afterStructure = try PDFX4StructureFinalizer.structure(in: after)
        var beforeBodies = beforeStructure.objectBodies
        var afterBodies = afterStructure.objectBodies
        beforeBodies.removeValue(forKey: beforeStructure.infoReference)
        afterBodies.removeValue(forKey: afterStructure.infoReference)

        let beforeReferences = Set(beforeBodies.keys)
        let afterReferences = Set(afterBodies.keys)
        XCTAssertEqual(beforeReferences, afterReferences, context, file: file, line: line)

        let references = beforeReferences.union(afterReferences).sorted {
            if $0.number == $1.number {
                return $0.generation < $1.generation
            }
            return $0.number < $1.number
        }
        for reference in references {
            XCTAssertEqual(
                beforeBodies[reference],
                afterBodies[reference],
                "\(context) object \(reference.number) \(reference.generation)",
                file: file,
                line: line
            )
        }
    }

    fileprivate static func regressionContentData(
        in pageDictionary: CGPDFDictionaryRef
    ) throws -> Data {
        var result = Data()
        for contentStream in contentStreams(in: pageDictionary, key: "Contents") {
            let decoded = try decodedData(from: contentStream, label: "Contents")
            var length = UInt64(decoded.count).bigEndian
            Swift.withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(decoded)
        }
        return result
    }
}

import Foundation
@testable import Honkumi

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

enum PDFX4TestInspector {
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
}

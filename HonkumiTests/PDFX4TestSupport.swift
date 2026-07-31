import Foundation

enum PDFTestFixtureBuilder {
    static func malformedQuartzStylePDF(
        trappedValue: String? = nil,
        additionalTrailerEntries: String = ""
    ) -> Data {
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

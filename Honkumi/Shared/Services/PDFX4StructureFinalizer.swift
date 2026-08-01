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

nonisolated struct PDFTrailerEntry: Equatable {
    let name: String
    let rawName: Data
    let rawValue: Data
}

nonisolated private struct PDFTrailerDictionaryEntry {
    let rawName: Data
    let rawValue: Data
}

nonisolated struct PDFX4StructureSnapshot {
    let xrefOffset: Int
    let declaredSize: Int
    let rootReference: PDFObjectReference
    let infoReference: PDFObjectReference
    let entries: [Int: PDFXRefEntry]
    let objectBodies: [PDFObjectReference: Data]

    let originalOffsets: [PDFObjectReference: Int]
    let rawIDValue: Data?
    let preservedTrailerEntries: [PDFTrailerEntry]

    func originalOffsetOrder(_ lhs: PDFObjectReference, _ rhs: PDFObjectReference) -> Bool {
        guard let lhsOffset = originalOffsets[lhs], let rhsOffset = originalOffsets[rhs] else {
            return lhs.number < rhs.number
        }
        return lhsOffset == rhsOffset
            ? lhs.generation < rhs.generation
            : lhsOffset < rhsOffset
    }
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

nonisolated protocol PDFFileFinalizing: Sendable {
    func finalize(at url: URL, metadata: PDFX4DocumentMetadata) throws
}

nonisolated struct PDFX4FileFinalizer: PDFFileFinalizing {
    func finalize(at url: URL, metadata: PDFX4DocumentMetadata) throws {
        try PDFX4StructureFinalizer.finalize(at: url, metadata: metadata)
    }
}

nonisolated enum PDFX4StructureFinalizer {
    static func structure(
        in data: Data,
        allowRepairableZeroOffsets: Bool = false
    ) throws -> PDFX4StructureSnapshot {
        try PDFClassicXRefParser(data: data).parse(
            allowRepairableZeroOffsets: allowRepairableZeroOffsets
        )
    }

    static func validateReferences(in snapshot: PDFX4StructureSnapshot) throws {
        try PDFLexicalScanner.validateReferences(in: snapshot)
    }

    static func finalizedData(from source: Data) throws -> Data {
        try rebuild(source, metadata: nil)
    }

    static func finalizedData(
        from source: Data,
        metadata: PDFX4DocumentMetadata
    ) throws -> Data {
        try rebuild(source, metadata: metadata)
    }

    private static func rebuild(
        _ source: Data,
        metadata: PDFX4DocumentMetadata?
    ) throws -> Data {
        let parsed = try structure(in: source, allowRepairableZeroOffsets: true)
        try PDFLexicalScanner.validateReferences(in: parsed)
        guard let originalInfoBody = parsed.objectBodies[parsed.infoReference] else {
            throw PDFX4FinalizationError.missingReference(parsed.infoReference)
        }
        let infoBody = try metadata.map {
            try PDFInfoDictionaryNormalizer.normalized(in: originalInfoBody, metadata: $0)
        } ?? PDFInfoDictionaryNormalizer.trappedFalse(in: originalInfoBody)

        var output = try PDFSerialization.header(
            version: PDFPrintProduction.targetPDFVersion,
            source: source,
            parsed: parsed
        )
        var newOffsets: [PDFObjectReference: Int] = [:]

        for object in parsed.objectBodies.keys.sorted(by: parsed.originalOffsetOrder) {
            newOffsets[object] = output.count
            output.append(object == parsed.infoReference ? infoBody : parsed.objectBodies[object]!)
            output.append(PDFSerialization.objectSeparator)
        }

        let xrefOffset = output.count
        guard xrefOffset <= PDFSerialization.maximumOffset else {
            throw PDFX4FinalizationError.outputTooLarge
        }
        let largestObjectNumber = max(
            parsed.entries.keys.max() ?? 0,
            parsed.objectBodies.keys.map(\.number).max() ?? 0
        )
        let (size, overflow) = largestObjectNumber.addingReportingOverflow(1)
        guard !overflow else {
            throw PDFX4FinalizationError.outputTooLarge
        }
        output.append(try PDFSerialization.xrefTable(
            size: size,
            originalEntries: parsed.entries,
            objectOffsets: newOffsets
        ))
        output.append(PDFSerialization.trailer(
            size: size,
            root: parsed.rootReference,
            info: parsed.infoReference,
            idValue: parsed.rawIDValue,
            preservedEntries: parsed.preservedTrailerEntries,
            startXRef: xrefOffset
        ))

        do {
            let rebuilt = try structure(in: output)
            try PDFLexicalScanner.validateReferences(in: rebuilt)
        } catch {
            throw PDFX4FinalizationError.unreadableFinalizedPDF
        }
        return output
    }

    static func finalize(at url: URL) throws {
        try finalize(at: url, metadata: nil)
    }

    static func finalize(
        at url: URL,
        metadata: PDFX4DocumentMetadata
    ) throws {
        try finalize(at: url, metadata: Optional(metadata))
    }

    private static func finalize(
        at url: URL,
        metadata: PDFX4DocumentMetadata?
    ) throws {
        let source = try Data(contentsOf: url)
        let output = try rebuild(source, metadata: metadata)

        guard
            let provider = CGDataProvider(data: output as CFData),
            CGPDFDocument(provider) != nil
        else {
            throw PDFX4FinalizationError.unreadableFinalizedPDF
        }

        try output.write(to: url, options: .atomic)
    }
}

nonisolated private struct PDFLexicalScanner {
    private enum Value {
        case integer(Int)
        case reference(PDFObjectReference)
        case dictionary(StreamLength?)
        case other
    }

    private enum StreamLength {
        case direct(Int)
        case indirect(PDFObjectReference)
    }

    private let data: Data
    private let integerObjects: [PDFObjectReference: Int]
    private let objectReferences: Set<PDFObjectReference>
    private var position = 0
    private var references: [PDFObjectReference] = []

    static func validateReferences(in snapshot: PDFX4StructureSnapshot) throws {
        let integerObjects = snapshot.objectBodies.reduce(into: [PDFObjectReference: Int]()) {
            values,
            element in
            if let value = directIntegerObjectValue(in: element.value) {
                values[element.key] = value
            }
        }
        let objectReferences = Set(snapshot.objectBodies.keys)

        var references: [PDFObjectReference] = []
        for objectBody in snapshot.objectBodies.values {
            references.append(
                contentsOf: try scan(
                    objectBody,
                    integerObjects: integerObjects,
                    objectReferences: objectReferences
                )
            )
        }
        for entry in snapshot.preservedTrailerEntries {
            references.append(
                contentsOf: try scan(
                    entry.rawValue,
                    integerObjects: integerObjects,
                    objectReferences: objectReferences
                )
            )
        }
        if let rawIDValue = snapshot.rawIDValue {
            references.append(
                contentsOf: try scan(
                    rawIDValue,
                    integerObjects: integerObjects,
                    objectReferences: objectReferences
                )
            )
        }

        for reference in references where snapshot.objectBodies[reference] == nil {
            throw PDFX4FinalizationError.missingReference(reference)
        }
    }

    private static func scan(
        _ data: Data,
        integerObjects: [PDFObjectReference: Int],
        objectReferences: Set<PDFObjectReference>
    ) throws -> [PDFObjectReference] {
        var scanner = PDFLexicalScanner(
            data: data,
            integerObjects: integerObjects,
            objectReferences: objectReferences
        )
        try scanner.scan()
        return scanner.references
    }

    private static func directIntegerObjectValue(in objectBody: Data) -> Int? {
        var cursor = PDFByteCursor(data: objectBody)
        guard cursor.readInteger() != nil,
              cursor.readInteger() != nil,
              cursor.readKeyword("obj"),
              let value = cursor.readInteger(),
              cursor.readKeyword("endobj") else {
            return nil
        }
        cursor.skipWhitespaceAndComments()
        return cursor.position == objectBody.count ? value : nil
    }

    private mutating func scan() throws {
        var precedingDictionary: StreamLength?

        while true {
            skipWhitespaceAndComments()
            guard position < data.count else { return }

            if readKeyword("stream") {
                guard let streamLength = precedingDictionary else {
                    throw PDFX4FinalizationError.malformedXRef
                }
                try skipStreamPayload(length: streamLength)
                precedingDictionary = nil
                continue
            }

            let value = try consumeValue()
            if case let .dictionary(length) = value {
                precedingDictionary = length
            } else {
                precedingDictionary = nil
            }
        }
    }

    private mutating func consumeValue() throws -> Value {
        skipWhitespaceAndComments()
        guard position < data.count else { throw PDFX4FinalizationError.malformedXRef }

        if consume("<<") {
            return .dictionary(try consumeDictionary())
        }
        if data[position] == 91 {
            position += 1
            try consumeArray()
            return .other
        }
        if data[position] == 40 {
            try consumeLiteralString()
            return .other
        }
        if data[position] == 60 {
            try consumeHexString()
            return .other
        }
        if data[position] == 47 {
            guard readName() != nil else { throw PDFX4FinalizationError.malformedXRef }
            return .other
        }
        if data[position] == 93 || consume(">>") {
            throw PDFX4FinalizationError.malformedXRef
        }

        guard let token = readToken() else { throw PDFX4FinalizationError.malformedXRef }
        if token == Data("obj".utf8) || token == Data("endstream".utf8) {
            return .other
        }
        guard let number = Int(String(decoding: token, as: UTF8.self)) else {
            return .other
        }

        let afterFirstNumber = position
        guard let generation = readIntegerToken(), readKeyword("R") else {
            position = afterFirstNumber
            return .integer(number)
        }
        let reference = PDFObjectReference(number: number, generation: generation)
        references.append(reference)
        return .reference(reference)
    }

    private mutating func consumeDictionary() throws -> StreamLength? {
        var streamLength: StreamLength?

        while true {
            skipWhitespaceAndComments()
            guard position < data.count else { throw PDFX4FinalizationError.malformedXRef }
            if consume(">>") { return streamLength }

            guard let name = readName() else { throw PDFX4FinalizationError.malformedXRef }
            let value = try consumeValue()
            if name == "Length" {
                guard streamLength == nil else { throw PDFX4FinalizationError.malformedXRef }
                switch value {
                case let .integer(length) where length >= 0:
                    streamLength = .direct(length)
                case let .reference(reference):
                    streamLength = .indirect(reference)
                default:
                    throw PDFX4FinalizationError.malformedXRef
                }
            }
        }
    }

    private mutating func consumeArray() throws {
        while true {
            skipWhitespaceAndComments()
            guard position < data.count else { throw PDFX4FinalizationError.malformedXRef }
            if data[position] == 93 {
                position += 1
                return
            }
            _ = try consumeValue()
        }
    }

    private mutating func skipStreamPayload(length: StreamLength) throws {
        if position < data.count, data[position] == 13 {
            position += 1
            if position < data.count, data[position] == 10 { position += 1 }
        } else if position < data.count, data[position] == 10 {
            position += 1
        } else {
            throw PDFX4FinalizationError.malformedXRef
        }

        let payloadLength: Int
        switch length {
        case let .direct(value):
            payloadLength = value
        case let .indirect(reference):
            guard objectReferences.contains(reference) else {
                throw PDFX4FinalizationError.missingReference(reference)
            }
            guard let value = integerObjects[reference], value >= 0 else {
                throw PDFX4FinalizationError.malformedXRef
            }
            payloadLength = value
        }
        guard payloadLength <= data.count - position else {
            throw PDFX4FinalizationError.malformedXRef
        }
        position += payloadLength
        guard consumeLineEnding(), consumeKeyword("endstream") else {
            throw PDFX4FinalizationError.malformedXRef
        }
    }

    private mutating func consumeLiteralString() throws {
        var depth = 0
        while position < data.count {
            let byte = data[position]
            position += 1
            if byte == 92 {
                if position < data.count { position += 1 }
            } else if byte == 40 {
                depth += 1
            } else if byte == 41 {
                depth -= 1
                if depth == 0 { return }
            }
        }
        throw PDFX4FinalizationError.malformedXRef
    }

    private mutating func consumeHexString() throws {
        position += 1
        while position < data.count {
            if data[position] == 62 {
                position += 1
                return
            }
            position += 1
        }
        throw PDFX4FinalizationError.malformedXRef
    }

    private mutating func readIntegerToken() -> Int? {
        skipWhitespaceAndComments()
        let start = position
        guard let token = readToken(), let value = Int(String(decoding: token, as: UTF8.self)) else {
            position = start
            return nil
        }
        return value
    }

    private mutating func readName() -> String? {
        skipWhitespaceAndComments()
        guard position < data.count, data[position] == 47 else { return nil }
        position += 1
        let start = position
        while position < data.count, !PDFByteCursor.isDelimiter(data[position]) {
            position += 1
        }
        guard position > start else { return nil }
        return PDFName.decoded(Data(data[start..<position]))
    }

    private mutating func readToken() -> Data? {
        skipWhitespaceAndComments()
        let start = position
        while position < data.count, !PDFByteCursor.isDelimiter(data[position]) {
            position += 1
        }
        guard position > start else { return nil }
        return Data(data[start..<position])
    }

    private mutating func readKeyword(_ keyword: String) -> Bool {
        skipWhitespaceAndComments()
        let bytes = Array(keyword.utf8)
        guard position + bytes.count <= data.count,
              data[position..<(position + bytes.count)].elementsEqual(bytes),
              position + bytes.count == data.count || PDFByteCursor.isDelimiter(data[position + bytes.count]) else {
            return false
        }
        position += bytes.count
        return true
    }

    private mutating func consume(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard position + bytes.count <= data.count,
              data[position..<(position + bytes.count)].elementsEqual(bytes) else {
            return false
        }
        position += bytes.count
        return true
    }

    private mutating func consumeKeyword(_ keyword: String) -> Bool {
        let bytes = Array(keyword.utf8)
        guard position + bytes.count <= data.count,
              data[position..<(position + bytes.count)].elementsEqual(bytes),
              position + bytes.count == data.count || PDFByteCursor.isDelimiter(data[position + bytes.count]) else {
            return false
        }
        position += bytes.count
        return true
    }

    private mutating func consumeLineEnding() -> Bool {
        guard position < data.count else { return false }
        if data[position] == 13 {
            position += 1
            if position < data.count, data[position] == 10 { position += 1 }
            return true
        }
        if data[position] == 10 {
            position += 1
            return true
        }
        return false
    }

    private mutating func skipWhitespaceAndComments() {
        while position < data.count {
            if PDFByteCursor.isWhitespace(data[position]) {
                position += 1
            } else if data[position] == 37 {
                while position < data.count, data[position] != 10, data[position] != 13 {
                    position += 1
                }
            } else {
                return
            }
        }
    }
}

nonisolated private struct PDFClassicXRefParser {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse(allowRepairableZeroOffsets: Bool) throws -> PDFX4StructureSnapshot {
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw PDFX4FinalizationError.malformedHeader
        }
        guard let startXRefPosition = data.lastRange(of: Data("startxref".utf8))?.lowerBound else {
            throw PDFX4FinalizationError.missingStartXRef
        }

        var startCursor = PDFByteCursor(data: data, position: startXRefPosition)
        guard startCursor.readKeyword("startxref"), let xrefOffset = startCursor.readInteger() else {
            throw PDFX4FinalizationError.missingStartXRef
        }
        guard xrefOffset >= 0, xrefOffset < data.count else {
            throw PDFX4FinalizationError.invalidStartXRef(xrefOffset)
        }

        var cursor = PDFByteCursor(data: data, position: xrefOffset)
        guard cursor.readKeyword("xref") else {
            var streamCursor = PDFByteCursor(data: data, position: xrefOffset)
            if streamCursor.readInteger() != nil,
               streamCursor.readInteger() != nil,
               streamCursor.readKeyword("obj") {
                throw PDFX4FinalizationError.unsupportedXRefStream
            }
            throw PDFX4FinalizationError.invalidStartXRef(xrefOffset)
        }

        var entries: [Int: PDFXRefEntry] = [:]
        while true {
            cursor.skipWhitespaceAndComments()
            if cursor.peekKeyword("trailer") {
                break
            }
            guard let firstObject = cursor.readInteger(), let count = cursor.readInteger(),
                  firstObject >= 0, count >= 0 else {
                throw PDFX4FinalizationError.malformedXRef
            }
            let (endObject, overflow) = firstObject.addingReportingOverflow(count)
            guard !overflow else {
                throw PDFX4FinalizationError.malformedXRef
            }
            for number in firstObject..<endObject {
                guard let offset = cursor.readInteger(), let generation = cursor.readInteger(),
                      let state = cursor.readToken(), state.count == 1,
                      let byte = state.first, byte == 110 || byte == 102,
                      offset >= 0, offset <= PDFSerialization.maximumOffset,
                      generation >= 0, generation <= PDFSerialization.maximumGeneration else {
                    throw PDFX4FinalizationError.malformedXRef
                }
                guard entries[number] == nil else {
                    throw PDFX4FinalizationError.duplicateObjectNumber(number)
                }
                guard number != 0 || byte == 102 else {
                    throw PDFX4FinalizationError.malformedXRef
                }
                let reference = PDFObjectReference(number: number, generation: generation)
                if byte == 110 {
                    entries[number] = PDFXRefEntry(reference: reference, kind: .inUse(offset: offset))
                } else {
                    entries[number] = PDFXRefEntry(
                        reference: reference,
                        kind: .free(nextFreeObject: offset, generation: generation)
                    )
                }
            }
        }

        guard cursor.readKeyword("trailer") else {
            throw PDFX4FinalizationError.malformedXRef
        }
        let trailerEntries = try cursor.readDictionaryEntries()
        guard let rawSize = trailerEntries["Size"]?.rawValue,
              let declaredSize = PDFTrailerValue.integer(rawSize) else {
            throw PDFX4FinalizationError.invalidTrailerSize
        }
        guard declaredSize > 0, declaredSize > (entries.keys.max() ?? -1) else {
            throw PDFX4FinalizationError.invalidTrailerSize
        }
        for entry in entries.values {
            if case let .free(nextFreeObject, _) = entry.kind,
               nextFreeObject < 0 || nextFreeObject >= declaredSize {
                throw PDFX4FinalizationError.malformedXRef
            }
        }
        guard let rootValue = trailerEntries["Root"]?.rawValue,
              let root = PDFTrailerValue.reference(rootValue) else {
            throw PDFX4FinalizationError.missingRoot
        }
        guard let infoValue = trailerEntries["Info"]?.rawValue,
              let info = PDFTrailerValue.reference(infoValue) else {
            throw PDFX4FinalizationError.missingInfo
        }
        if trailerEntries["Prev"] != nil || trailerEntries["XRefStm"] != nil {
            throw PDFX4FinalizationError.unsupportedIncrementalUpdate
        }
        if trailerEntries["Encrypt"] != nil {
            throw PDFX4FinalizationError.encryptedPDF
        }

        let inUseEntries = entries.values.compactMap { entry -> (PDFObjectReference, Int)? in
            guard case let .inUse(offset) = entry.kind else { return nil }
            return (entry.reference, offset)
        }
        for (_, offset) in inUseEntries {
            if offset == 0 {
                guard allowRepairableZeroOffsets else {
                    throw PDFX4FinalizationError.invalidObjectOffset(0)
                }
            } else if offset < 0 || offset >= xrefOffset {
                throw PDFX4FinalizationError.invalidObjectOffset(offset)
            }
        }
        for (reference, offset) in inUseEntries where offset > 0 {
            try verifyObjectHeader(reference: reference, at: offset)
        }

        let sortedObjects = inUseEntries
            .filter { $0.1 > 0 }
            .sorted { $0.1 < $1.1 }
        var objectBodies: [PDFObjectReference: Data] = [:]
        var originalOffsets: [PDFObjectReference: Int] = [:]
        for (index, item) in sortedObjects.enumerated() {
            let end = index + 1 < sortedObjects.count ? sortedObjects[index + 1].1 : xrefOffset
            guard item.1 < end else {
                throw PDFX4FinalizationError.invalidObjectOffset(item.1)
            }
            let slice = data[item.1..<end]
            objectBodies[item.0] = PDFByteCursor.trimTrailingWhitespace(Data(slice))
            originalOffsets[item.0] = item.1
        }
        guard objectBodies[root] != nil else {
            throw PDFX4FinalizationError.missingReference(root)
        }
        guard objectBodies[info] != nil else {
            throw PDFX4FinalizationError.missingReference(info)
        }

        let preserved = trailerEntries.compactMap { name, entry -> PDFTrailerEntry? in
            ["Size", "Root", "Info", "ID", "Prev", "XRefStm", "Encrypt"].contains(name)
                ? nil
                : PDFTrailerEntry(name: name, rawName: entry.rawName, rawValue: entry.rawValue)
        }.sorted { $0.name < $1.name }

        return PDFX4StructureSnapshot(
            xrefOffset: xrefOffset,
            declaredSize: declaredSize,
            rootReference: root,
            infoReference: info,
            entries: entries,
            objectBodies: objectBodies,
            originalOffsets: originalOffsets,
            rawIDValue: trailerEntries["ID"]?.rawValue,
            preservedTrailerEntries: preserved
        )
    }

    private func verifyObjectHeader(reference: PDFObjectReference, at offset: Int) throws {
        guard data[offset] >= 48, data[offset] <= 57 else {
            throw PDFX4FinalizationError.objectHeaderMismatch(reference.number)
        }
        var cursor = PDFByteCursor(data: data, position: offset)
        guard cursor.readInteger() == reference.number,
              cursor.readInteger() == reference.generation,
              cursor.readKeyword("obj") else {
            throw PDFX4FinalizationError.objectHeaderMismatch(reference.number)
        }
    }
}

nonisolated private struct PDFByteCursor {
    private let data: Data
    private(set) var position: Int

    init(data: Data, position: Int = 0) {
        self.data = data
        self.position = position
    }

    mutating func skipWhitespaceAndComments() {
        while position < data.count {
            if Self.isWhitespace(data[position]) {
                position += 1
            } else if data[position] == 37 {
                while position < data.count, data[position] != 10, data[position] != 13 {
                    position += 1
                }
            } else {
                return
            }
        }
    }

    mutating func readInteger() -> Int? {
        skipWhitespaceAndComments()
        let start = position
        if position < data.count, data[position] == 43 || data[position] == 45 {
            position += 1
        }
        while position < data.count, data[position] >= 48, data[position] <= 57 {
            position += 1
        }
        guard position > start, let value = Int(String(decoding: data[start..<position], as: UTF8.self)) else {
            position = start
            return nil
        }
        return value
    }

    mutating func readKeyword(_ keyword: String) -> Bool {
        skipWhitespaceAndComments()
        let bytes = Array(keyword.utf8)
        guard position + bytes.count <= data.count,
              data[position..<(position + bytes.count)].elementsEqual(bytes),
              position + bytes.count == data.count || Self.isDelimiter(data[position + bytes.count]) else {
            return false
        }
        position += bytes.count
        return true
    }

    func peekKeyword(_ keyword: String) -> Bool {
        var copy = self
        return copy.readKeyword(keyword)
    }

    mutating func readToken() -> Data? {
        skipWhitespaceAndComments()
        let start = position
        while position < data.count, !Self.isDelimiter(data[position]) {
            position += 1
        }
        guard position > start else { return nil }
        return Data(data[start..<position])
    }

    mutating func readDictionaryEntries() throws -> [String: PDFTrailerDictionaryEntry] {
        skipWhitespaceAndComments()
        guard consume("<<") else { throw PDFX4FinalizationError.malformedXRef }
        var entries: [String: PDFTrailerDictionaryEntry] = [:]
        while true {
            skipWhitespaceAndComments()
            if consume(">>") { return entries }
            guard let name = readNameToken(), entries[name.decoded] == nil else {
                throw PDFX4FinalizationError.malformedXRef
            }
            let valueStart = position
            try consumeValue()
            entries[name.decoded] = PDFTrailerDictionaryEntry(
                rawName: name.rawSpelling,
                rawValue: Data(data[valueStart..<position])
            )
        }
    }

    mutating func consumeValue() throws {
        skipWhitespaceAndComments()
        guard position < data.count else { throw PDFX4FinalizationError.malformedXRef }
        if consume("<<") {
            position -= 2
            _ = try readDictionaryEntries()
            return
        }
        if data[position] == 91 {
            try consumeArray()
            return
        }
        if data[position] == 40 {
            try consumeLiteralString()
            return
        }
        if data[position] == 60 {
            try consumeHexString()
            return
        }
        if data[position] == 47 {
            guard readName() != nil else { throw PDFX4FinalizationError.malformedXRef }
            return
        }
        let valueStart = position
        if readInteger() != nil {
            var potentialReference = self
            if potentialReference.readInteger() != nil,
               potentialReference.readKeyword("R") {
                position = potentialReference.position
            }
            return
        }
        position = valueStart
        guard readToken() != nil else { throw PDFX4FinalizationError.malformedXRef }
    }

    private mutating func consumeArray() throws {
        guard position < data.count, data[position] == 91 else { throw PDFX4FinalizationError.malformedXRef }
        position += 1
        while true {
            skipWhitespaceAndComments()
            guard position < data.count else { throw PDFX4FinalizationError.malformedXRef }
            if data[position] == 93 {
                position += 1
                return
            }
            try consumeValue()
        }
    }

    private mutating func consumeLiteralString() throws {
        var depth = 0
        while position < data.count {
            let byte = data[position]
            position += 1
            if byte == 92 {
                if position < data.count { position += 1 }
            } else if byte == 40 {
                depth += 1
            } else if byte == 41 {
                depth -= 1
                if depth == 0 { return }
            }
        }
        throw PDFX4FinalizationError.malformedXRef
    }

    private mutating func consumeHexString() throws {
        position += 1
        while position < data.count {
            if data[position] == 62 {
                position += 1
                return
            }
            position += 1
        }
        throw PDFX4FinalizationError.malformedXRef
    }

    private mutating func readNameToken() -> PDFName? {
        skipWhitespaceAndComments()
        guard position < data.count, data[position] == 47 else { return nil }
        position += 1
        let start = position
        while position < data.count, !Self.isDelimiter(data[position]) {
            position += 1
        }
        guard position > start else { return nil }
        let rawSpelling = Data(data[start..<position])
        guard let decoded = PDFName.decoded(rawSpelling) else { return nil }
        return PDFName(decoded: decoded, rawSpelling: rawSpelling)
    }

    private mutating func readName() -> String? {
        readNameToken()?.decoded
    }

    private mutating func consume(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard position + bytes.count <= data.count,
              data[position..<(position + bytes.count)].elementsEqual(bytes) else { return false }
        position += bytes.count
        return true
    }

    static func trimTrailingWhitespace(_ data: Data) -> Data {
        var end = data.count
        while end > 0, isWhitespace(data[end - 1]) { end -= 1 }
        return Data(data[..<end])
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    static func isDelimiter(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || [37, 40, 41, 60, 62, 91, 93, 123, 125, 47].contains(byte)
    }
}

nonisolated private enum PDFTrailerValue {
    static func integer(_ data: Data) -> Int? {
        var cursor = PDFByteCursor(data: data)
        guard let value = cursor.readInteger() else { return nil }
        cursor.skipWhitespaceAndComments()
        return cursor.position == data.count ? value : nil
    }

    static func reference(_ data: Data) -> PDFObjectReference? {
        var cursor = PDFByteCursor(data: data)
        guard let number = cursor.readInteger(), let generation = cursor.readInteger(),
              cursor.readKeyword("R") else { return nil }
        cursor.skipWhitespaceAndComments()
        guard cursor.position == data.count else { return nil }
        return PDFObjectReference(number: number, generation: generation)
    }
}

nonisolated private struct PDFName {
    let decoded: String
    let rawSpelling: Data

    static func decoded(_ raw: Data) -> String? {
        var decoded: [UInt8] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            let byte = raw[index]
            if byte == 35 {
                let firstHex = raw.index(after: index)
                guard firstHex < raw.endIndex else { return nil }
                let secondHex = raw.index(after: firstHex)
                guard secondHex < raw.endIndex,
                      let high = hexValue(raw[firstHex]), let low = hexValue(raw[secondHex]) else {
                    return nil
                }
                decoded.append(high << 4 | low)
                index = raw.index(after: secondHex)
            } else {
                decoded.append(byte)
                index = raw.index(after: index)
            }
        }
        return String(bytes: decoded, encoding: .utf8)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}

nonisolated private enum PDFSerialization {
    static let maximumOffset = 9_999_999_999
    static let maximumGeneration = 65_535
    static let objectSeparator = Data("\n".utf8)

    static func header(version: String, source: Data, parsed: PDFX4StructureSnapshot) throws -> Data {
        guard let firstOffset = parsed.originalOffsets.values.min(), firstOffset > 0 else {
            throw PDFX4FinalizationError.malformedHeader
        }
        let prefix = Data(source[..<firstOffset])
        guard prefix.starts(with: Data("%PDF-".utf8)) else {
            throw PDFX4FinalizationError.malformedHeader
        }
        var versionEnd = 5
        while versionEnd < prefix.count, !PDFByteCursor.isWhitespace(prefix[versionEnd]) {
            versionEnd += 1
        }
        guard versionEnd < prefix.count else { throw PDFX4FinalizationError.malformedHeader }
        var output = Data("%PDF-\(version)".utf8)
        output.append(prefix[versionEnd..<prefix.count])
        return output
    }

    static func xrefTable(
        size: Int,
        originalEntries: [Int: PDFXRefEntry],
        objectOffsets: [PDFObjectReference: Int]
    ) throws -> Data {
        guard size > 0,
              size <= maximumOffset,
              size <= Int.max / 20 else {
            throw PDFX4FinalizationError.outputTooLarge
        }
        var rows: [(offset: Int, generation: Int, state: Character)] = Array(
            repeating: (0, 0, "f"),
            count: size
        )
        for number in 1..<size {
            if let entry = originalEntries[number],
               case .inUse = entry.kind,
               let offset = objectOffsets[entry.reference] {
                rows[number] = (offset, entry.reference.generation, "n")
            } else if let entry = originalEntries[number], case let .free(_, generation) = entry.kind {
                rows[number].generation = generation
            } else if let entry = originalEntries[number], case .inUse = entry.kind {
                rows[number].generation = min(entry.reference.generation + 1, 65_535)
            }
        }
        let freeObjects = (0..<size).filter { rows[$0].state == "f" }
        for (index, number) in freeObjects.enumerated() {
            rows[number].offset = index + 1 < freeObjects.count ? freeObjects[index + 1] : 0
        }
        rows[0].generation = 65_535

        var output = Data("xref\n0 \(size)\n".utf8)
        for row in rows {
            guard row.offset >= 0, row.offset <= maximumOffset,
                  row.generation >= 0, row.generation <= maximumGeneration else {
                throw PDFX4FinalizationError.outputTooLarge
            }
            output.append(Data(String(format: "%010d %05d %@ \n", row.offset, row.generation, String(row.state)).utf8))
        }
        return output
    }

    static func trailer(
        size: Int,
        root: PDFObjectReference,
        info: PDFObjectReference,
        idValue: Data?,
        preservedEntries: [PDFTrailerEntry],
        startXRef: Int
    ) -> Data {
        var output = Data("trailer\n<< /Size \(size) /Root \(root.number) \(root.generation) R /Info \(info.number) \(info.generation) R".utf8)
        if let idValue {
            output.append(Data(" /ID ".utf8))
            output.append(idValue)
        }
        for entry in preservedEntries {
            output.append(Data(" /".utf8))
            output.append(entry.rawName)
            output.append(Data(" ".utf8))
            output.append(entry.rawValue)
        }
        output.append(Data(" >>\nstartxref\n\(startXRef)\n%%EOF\n".utf8))
        return output
    }
}

nonisolated enum PDFInfoDictionaryNormalizer {
    private static let synchronizedNames: Set<String> = [
        "Title", "Author", "Subject", "Keywords", "Creator", "Producer",
        "CreationDate", "ModDate", "Trapped"
    ]

    static func trappedFalse(in objectBody: Data) throws -> Data {
        let entries = try parsedEntries(in: objectBody)
        let trappedEntries = entries.0.filter { $0.name == "Trapped" }
        guard trappedEntries.count <= 1 else {
            throw PDFX4FinalizationError.invalidInfoDictionary
        }
        if let trapped = trappedEntries.first {
            var output = Data(objectBody[..<trapped.valueStart])
            output.append(Data("/False".utf8))
            output.append(objectBody[trapped.valueEnd..<objectBody.count])
            return output
        }
        var output = Data(objectBody[..<entries.endStart])
        output.append(Data(" /Trapped /False".utf8))
        output.append(objectBody[entries.endStart..<objectBody.count])
        return output
    }

    static func normalized(
        in objectBody: Data,
        metadata: PDFX4DocumentMetadata
    ) throws -> Data {
        let entries = try parsedEntries(in: objectBody)
        let synchronizedEntries = entries.0.filter { synchronizedNames.contains($0.name) }
        let entryCounts = Dictionary(grouping: synchronizedEntries, by: \.name)
        guard entryCounts.values.allSatisfy({ $0.count == 1 }) else {
            throw PDFX4FinalizationError.invalidInfoDictionary
        }

        var replacements: [(name: String, value: Data)] = [
            ("Title", pdfTextString(metadata.title)),
            ("Subject", pdfTextString(metadata.subject)),
            ("Keywords", pdfTextString(metadata.keywords)),
            ("Creator", pdfTextString(metadata.creatorTool)),
            ("Producer", pdfTextString(metadata.producer)),
            ("CreationDate", pdfTextString(PDFX4DocumentMetadata.pdfDateString(metadata.creationDate))),
            ("ModDate", pdfTextString(PDFX4DocumentMetadata.pdfDateString(metadata.modificationDate))),
            ("Trapped", Data("/False".utf8))
        ]
        if let author = metadata.author {
            replacements.insert(("Author", pdfTextString(author)), at: 1)
        }

        let entriesByName = Dictionary(uniqueKeysWithValues: synchronizedEntries.map {
            ($0.name, $0)
        })
        var output = objectBody
        let missingEntries = replacements.filter { entriesByName[$0.name] == nil }
        if !missingEntries.isEmpty {
            var insertion = Data()
            for entry in missingEntries {
                insertion.append(Data(" /\(entry.name) ".utf8))
                insertion.append(entry.value)
            }
            output.insert(contentsOf: insertion, at: entries.endStart)
        }

        for replacement in replacements.compactMap({ replacement -> (Entry, Data)? in
            entriesByName[replacement.name].map { ($0, replacement.value) }
        }).sorted(by: { $0.0.valueStart > $1.0.valueStart }) {
            output.replaceSubrange(
                replacement.0.valueStart..<replacement.0.valueEnd,
                with: replacement.1
            )
        }
        return output
    }

    private static func parsedEntries(in objectBody: Data) throws -> ([Entry], endStart: Int) {
        var cursor = PDFByteCursor(data: objectBody)
        guard cursor.readInteger() != nil,
              cursor.readInteger() != nil,
              cursor.readKeyword("obj") else {
            throw PDFX4FinalizationError.invalidInfoDictionary
        }
        cursor.skipWhitespaceAndComments()
        let dictionaryStart = cursor.position
        guard dictionaryStart + 1 < objectBody.count,
              objectBody[dictionaryStart] == 60,
              objectBody[dictionaryStart + 1] == 60 else {
            throw PDFX4FinalizationError.invalidInfoDictionary
        }
        return try dictionaryEntries(in: objectBody, startingAt: dictionaryStart)
    }

    private static func pdfTextString(_ value: String) -> Data {
        var bytes = Data([0xFE, 0xFF])
        for codeUnit in value.utf16 {
            bytes.append(UInt8(codeUnit >> 8))
            bytes.append(UInt8(codeUnit & 0xFF))
        }

        let hexadecimal = bytes.map { String(format: "%02X", $0) }.joined()
        return Data("<\(hexadecimal)>".utf8)
    }

    private static func dictionaryEntries(in data: Data, startingAt start: Int) throws -> ([Entry], endStart: Int) {
        var cursor = PDFByteCursor(data: data, position: start)
        guard cursor.consumeDictionaryStartForNormalizer() else {
            throw PDFX4FinalizationError.invalidInfoDictionary
        }
        var result: [Entry] = []
        while true {
            cursor.skipWhitespaceAndComments()
            if cursor.atDictionaryEndForNormalizer() {
                return (result, cursor.position)
            }
            guard let name = cursor.readNameForNormalizer() else {
                throw PDFX4FinalizationError.invalidInfoDictionary
            }
            cursor.skipWhitespaceAndComments()
            let valueStart = cursor.position
            do {
                try cursor.consumeValueForNormalizer()
            } catch {
                throw PDFX4FinalizationError.invalidInfoDictionary
            }
            result.append(Entry(name: name, valueStart: valueStart, valueEnd: cursor.position))
        }
    }

    private struct Entry {
        let name: String
        let valueStart: Int
        let valueEnd: Int
    }
}

nonisolated private extension PDFByteCursor {
    mutating func consumeDictionaryStartForNormalizer() -> Bool {
        skipWhitespaceAndComments()
        guard position + 1 < data.count, data[position] == 60, data[position + 1] == 60 else { return false }
        position += 2
        return true
    }

    func atDictionaryEndForNormalizer() -> Bool {
        position + 1 < data.count && data[position] == 62 && data[position + 1] == 62
    }

    mutating func readNameForNormalizer() -> String? {
        readName()
    }

    mutating func consumeValueForNormalizer() throws {
        try consumeValue()
    }
}

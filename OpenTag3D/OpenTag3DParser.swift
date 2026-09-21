//
//  OpenTag3DParser.swift
//  OpenTag3D
//

import Foundation

struct OpenTag3DSection: Identifiable, Hashable {
    let id: String
    let title: String
}

struct OpenTag3DFieldValue: Identifiable {
    let id: String
    let section: OpenTag3DSection
    let name: String
    let offset: Int
    let length: Int
    let rawHex: String
    let numericValue: String
    let humanReadableValue: String

    var offsetDescription: String {
        String(format: "0x%02X (%d byte%@)", offset, length, length == 1 ? "" : "s")
    }
}

struct OpenTag3DFieldSection: Identifiable {
    let id: String
    let title: String
    let fields: [OpenTag3DFieldValue]
}

enum OpenTag3DHexError: LocalizedError {
    case oddDigitCount
    case invalidCharacter(Character)

    var errorDescription: String? {
        switch self {
        case .oddDigitCount:
            return "The hex data has an incomplete byte. Every byte needs two hex digits."
        case .invalidCharacter(let character):
            return "“\(character)” is not a hex digit. Use only 0–9, A–F, and whitespace."
        }
    }
}

enum OpenTag3DEditSource {
    case humanReadable
    case numeric
    case rawHex
}

enum OpenTag3DEditError: LocalizedError {
    case unknownField
    case numericNotApplicable
    case unsupportedType(String)
    case invalidValue(String)
    case outOfRange(maximum: UInt64)
    case wrongByteCount(expected: Int, actual: Int)
    case textTooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .unknownField:
            return "That OpenTag3D field is not recognized."
        case .numericNotApplicable:
            return "This text field does not have a numeric representation."
        case .unsupportedType(let type):
            return "The bundled specification uses the unsupported field type “\(type)”."
        case .invalidValue(let expected):
            return "Enter \(expected)."
        case .outOfRange(let maximum):
            return "The encoded value must be between 0 and \(maximum)."
        case .wrongByteCount(let expected, let actual):
            return "Raw hex requires exactly \(expected) bytes; \(actual) were entered."
        case .textTooLong(let maximum):
            return "The text is too long for this field (maximum \(maximum) bytes)."
        }
    }
}

enum OpenTag3DSpecError: LocalizedError {
    case missingFile
    case invalidOffset(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "spec.json is missing from the app bundle."
        case .invalidOffset(let offset):
            return "The OpenTag3D specification contains an invalid offset: \(offset)."
        }
    }
}

enum OpenTag3DParser {
    static func mimeType() throws -> String {
        try specification().mimeType
    }

    static func specificationVersion() throws -> String {
        try specification().version
    }

    static func data(from hexText: String) throws -> Data {
        let compactHex = hexText.filter { !$0.isWhitespace }

        if let invalidCharacter = compactHex.first(where: { !$0.isHexDigit }) {
            throw OpenTag3DHexError.invalidCharacter(invalidCharacter)
        }

        guard compactHex.count.isMultiple(of: 2) else {
            throw OpenTag3DHexError.oddDigitCount
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(compactHex.count / 2)
        var index = compactHex.startIndex

        while index < compactHex.endIndex {
            let nextIndex = compactHex.index(index, offsetBy: 2)
            bytes.append(UInt8(compactHex[index..<nextIndex], radix: 16)!)
            index = nextIndex
        }

        return Data(bytes)
    }

    static func editableHex(for data: Data) -> String {
        stride(from: 0, to: data.count, by: 16).map { offset in
            let end = min(offset + 16, data.count)
            return data[offset..<end]
                .map { String(format: "%02X", $0) }
                .joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    static func fieldSections(from data: Data) throws -> [OpenTag3DFieldSection] {
        try specification().sections.map { sectionDefinition in
            let section = OpenTag3DSection(
                id: sectionDefinition.id,
                title: sectionDefinition.title
            )
            let fields = try sectionDefinition.fields.map { definition in
                try fieldValue(for: definition, section: section, data: data)
            }
            return OpenTag3DFieldSection(
                id: section.id,
                title: section.title,
                fields: fields
            )
        }
    }

    static func replacingField(
        id: String,
        source: OpenTag3DEditSource,
        text: String,
        in originalData: Data
    ) throws -> Data {
        guard let definition = try specification().sections
            .flatMap(\.fields)
            .first(where: { $0.id == id }) else {
            throw OpenTag3DEditError.unknownField
        }

        let replacement: [UInt8]
        switch source {
        case .rawHex:
            replacement = [UInt8](try data(from: text))
            guard replacement.count == definition.length else {
                throw OpenTag3DEditError.wrongByteCount(
                    expected: definition.length,
                    actual: replacement.count
                )
            }
        case .numeric:
            replacement = try bytesFromNumericText(text, for: definition)
        case .humanReadable:
            replacement = try bytesFromHumanText(text, for: definition)
        }

        var updatedData = originalData
        let requiredCount = definition.offset + definition.length
        if updatedData.count < requiredCount {
            updatedData.append(Data(repeating: 0, count: requiredCount - updatedData.count))
        }
        updatedData.replaceSubrange(
            definition.offset..<requiredCount,
            with: replacement
        )
        return updatedData
    }

    private static func fieldValue(
        for definition: FieldDefinition,
        section: OpenTag3DSection,
        data: Data
    ) throws -> OpenTag3DFieldValue {
        let end = definition.offset + definition.length
        let bytes = definition.offset < data.count
            ? Data(data[definition.offset..<min(end, data.count)])
            : Data()
        let rawHex = bytes.isEmpty
            ? "—"
            : bytes.map { String(format: "%02X", $0) }.joined(separator: " ")

        guard bytes.count == definition.length else {
            return OpenTag3DFieldValue(
                id: definition.id,
                section: section,
                name: definition.name,
                offset: definition.offset,
                length: definition.length,
                rawHex: rawHex,
                numericValue: "—",
                humanReadableValue: "Not present"
            )
        }

        let decoded = try decode([UInt8](bytes), using: definition)
        return OpenTag3DFieldValue(
            id: definition.id,
            section: section,
            name: definition.name,
            offset: definition.offset,
            length: definition.length,
            rawHex: rawHex,
            numericValue: decoded.numeric,
            humanReadableValue: decoded.humanReadable
        )
    }

    private static func decode(
        _ bytes: [UInt8],
        using definition: FieldDefinition
    ) throws -> DecodedValue {
        switch definition.type {
        case "int":
            let value = unsignedInteger(bytes)
            return DecodedValue(
                numeric: String(value),
                humanReadable: humanReadableInteger(value, definition: definition)
            )
        case "utf8", "ascii":
            let content = bytes.prefix { $0 != 0 }
            let value = String(decoding: content, as: UTF8.self)
            return DecodedValue(numeric: "—", humanReadable: value.isEmpty ? "(empty)" : value)
        case "rgba":
            let numeric = bytes.map(String.init).joined(separator: ", ")
            let hex = bytes.map { String(format: "%02X", $0) }.joined()
            return DecodedValue(numeric: numeric, humanReadable: "#\(hex) (RGBA)")
        case "date":
            guard bytes.count == 4 else {
                throw OpenTag3DEditError.wrongByteCount(expected: 4, actual: bytes.count)
            }
            let year = unsignedInteger(Array(bytes[0...1]))
            return DecodedValue(
                numeric: "\(year), \(bytes[2]), \(bytes[3])",
                humanReadable: String(format: "%04llu-%02d-%02d", year, bytes[2], bytes[3])
            )
        case "time":
            guard bytes.count == 3 else {
                throw OpenTag3DEditError.wrongByteCount(expected: 3, actual: bytes.count)
            }
            return DecodedValue(
                numeric: bytes.map(String.init).joined(separator: ", "),
                humanReadable: String(format: "%02d:%02d:%02d UTC", bytes[0], bytes[1], bytes[2])
            )
        default:
            throw OpenTag3DEditError.unsupportedType(definition.type)
        }
    }

    private static func humanReadableInteger(
        _ value: UInt64,
        definition: FieldDefinition
    ) -> String {
        let scaling = definition.scaling ?? 1
        let scaledValue = Double(value) * scaling
        let places = decimalPlaces(for: scaling)
        let formatted = places == 0
            ? String(format: "%.0f", scaledValue)
            : String(format: "%.*f", places, scaledValue)

        guard let unit = definition.unit, !unit.isEmpty, unit != "version" else {
            return formatted
        }
        return "\(formatted) \(unit)"
    }

    private static func decimalPlaces(for scaling: Double) -> Int {
        guard scaling > 0, scaling < 1 else { return 0 }
        var shifted = scaling
        for places in 1...6 {
            shifted *= 10
            if abs(shifted.rounded() - shifted) < 0.000_000_1 {
                return places
            }
        }
        return 6
    }

    private static func bytesFromNumericText(
        _ text: String,
        for definition: FieldDefinition
    ) throws -> [UInt8] {
        switch definition.type {
        case "utf8", "ascii":
            throw OpenTag3DEditError.numericNotApplicable
        case "rgba":
            return try byteList(from: text, count: definition.length)
        case "date":
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        case "time":
            let values = try integerList(from: text, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        case "int":
            guard let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw OpenTag3DEditError.invalidValue("an unsigned integer")
            }
            return try bigEndianBytes(value, length: definition.length)
        default:
            throw OpenTag3DEditError.unsupportedType(definition.type)
        }
    }

    private static func bytesFromHumanText(
        _ text: String,
        for definition: FieldDefinition
    ) throws -> [UInt8] {
        switch definition.type {
        case "utf8", "ascii":
            let value = text == "(empty)" ? "" : text
            let bytes = [UInt8](value.utf8)
            if definition.type == "ascii", bytes.contains(where: { $0 > 0x7F }) {
                throw OpenTag3DEditError.invalidValue("ASCII text")
            }
            guard bytes.count <= definition.length else {
                throw OpenTag3DEditError.textTooLong(maximum: definition.length)
            }
            return bytes + Array(repeating: 0, count: definition.length - bytes.count)
        case "rgba":
            let beforeDescription = text.split(separator: "(", maxSplits: 1)[0]
            let hex = beforeDescription.filter { $0.isHexDigit }
            guard hex.count == definition.length * 2 else {
                throw OpenTag3DEditError.invalidValue(
                    "a \(definition.length * 2)-digit hexadecimal color"
                )
            }
            return [UInt8](try data(from: hex))
        case "date":
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        case "time":
            let withoutUTC = text.replacingOccurrences(
                of: "UTC",
                with: "",
                options: .caseInsensitive
            )
            let values = try integerList(from: withoutUTC, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        case "int":
            let displayedValue = try firstDecimal(in: text)
            let scaling = definition.scaling ?? 1
            guard scaling > 0 else {
                throw OpenTag3DEditError.invalidValue("a field with positive scaling")
            }
            let rawValue = displayedValue / scaling
            guard rawValue.isFinite,
                  rawValue >= 0,
                  abs(rawValue.rounded() - rawValue) < 0.000_000_1 else {
                throw OpenTag3DEditError.invalidValue(
                    "a value representable using the field's scaling"
                )
            }
            return try bigEndianBytes(UInt64(rawValue.rounded()), length: definition.length)
        default:
            throw OpenTag3DEditError.unsupportedType(definition.type)
        }
    }

    private static func firstDecimal(in text: String) throws -> Double {
        let scanner = Scanner(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let value = scanner.scanDouble() else {
            throw OpenTag3DEditError.invalidValue("a number, optionally followed by its unit")
        }
        return value
    }

    private static func integerList(from text: String, count: Int) throws -> [UInt64] {
        let components = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard components.count == count,
              components.allSatisfy({ UInt64($0) != nil }) else {
            throw OpenTag3DEditError.invalidValue("\(count) integer values")
        }
        return components.map { UInt64($0)! }
    }

    private static func byteList(from text: String, count: Int) throws -> [UInt8] {
        let values = try integerList(from: text, count: count)
        guard values.allSatisfy({ $0 <= UInt8.max }) else {
            throw OpenTag3DEditError.invalidValue("\(count) values between 0 and 255")
        }
        return values.map(UInt8.init)
    }

    private static func dateBytes(year: UInt64, month: UInt64, day: UInt64) throws -> [UInt8] {
        guard year <= UInt16.max, (1...12).contains(month), (1...31).contains(day) else {
            throw OpenTag3DEditError.invalidValue("a date formatted as YYYY-MM-DD")
        }
        return try bigEndianBytes(year, length: 2) + [UInt8(month), UInt8(day)]
    }

    private static func timeBytes(hour: UInt64, minute: UInt64, second: UInt64) throws -> [UInt8] {
        guard hour <= 23, minute <= 59, second <= 59 else {
            throw OpenTag3DEditError.invalidValue("a 24-hour time formatted as HH:MM:SS")
        }
        return [UInt8(hour), UInt8(minute), UInt8(second)]
    }

    private static func bigEndianBytes(_ value: UInt64, length: Int) throws -> [UInt8] {
        let maximum = length >= MemoryLayout<UInt64>.size
            ? UInt64.max
            : (UInt64(1) << UInt64(length * 8)) - 1
        guard value <= maximum else {
            throw OpenTag3DEditError.outOfRange(maximum: maximum)
        }
        return (0..<length).map { index in
            let shift = (length - index - 1) * 8
            return shift >= 64 ? 0 : UInt8((value >> UInt64(shift)) & 0xFF)
        }
    }

    private static func unsignedInteger(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func specification() throws -> Specification {
        try specificationResult.get()
    }

    private static let specificationResult: Result<Specification, Error> = Result {
        let bundles = [Bundle.main, Bundle(for: OpenTag3DBundleLocator.self)]
        guard let fileURL = bundles.lazy.compactMap({
            $0.url(forResource: "spec", withExtension: "json")
        }).first else {
            throw OpenTag3DSpecError.missingFile
        }

        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(SpecDocument.self, from: data)
        let sections = try document.sections.map { section in
            SectionDefinition(
                id: section.id,
                title: section.id.replacingOccurrences(of: "_", with: " ").uppercased(),
                startOffset: try offset(from: section.value.addressRange.start),
                fields: try section.value.fields.map { field in
                    FieldDefinition(
                        id: field.id,
                        name: field.name,
                        type: field.type.lowercased(),
                        unit: field.unit,
                        scaling: field.scaling,
                        offset: try offset(from: field.start),
                        length: field.length
                    )
                }
            )
        }
        .sorted { $0.startOffset < $1.startOffset }

        return Specification(
            version: document.version,
            mimeType: document.mimeType,
            sections: sections
        )
    }

    private static func offset(from text: String) throws -> Int {
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard let value = Int(digits, radix: 16) else {
            throw OpenTag3DSpecError.invalidOffset(text)
        }
        return value
    }

    private struct DecodedValue {
        let numeric: String
        let humanReadable: String
    }

    private struct Specification {
        let version: String
        let mimeType: String
        let sections: [SectionDefinition]
    }

    private struct SectionDefinition {
        let id: String
        let title: String
        let startOffset: Int
        let fields: [FieldDefinition]
    }

    private struct FieldDefinition {
        let id: String
        let name: String
        let type: String
        let unit: String?
        let scaling: Double?
        let offset: Int
        let length: Int
    }

    private struct SpecDocument: Decodable {
        let version: String
        let mimeType: String
        let sections: [(id: String, value: SpecSection)]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            version = try container.decode(String.self, forKey: DynamicCodingKey("version"))
            mimeType = try container.decode(String.self, forKey: DynamicCodingKey("mime_type"))
            sections = try container.allKeys.compactMap { key in
                guard key.stringValue != "version", key.stringValue != "mime_type" else {
                    return nil
                }
                return (
                    id: key.stringValue,
                    value: try container.decode(SpecSection.self, forKey: key)
                )
            }
        }
    }

    private struct SpecSection: Decodable {
        let addressRange: SpecAddressRange
        let fields: [SpecField]

        private enum CodingKeys: String, CodingKey {
            case addressRange = "address_range"
            case fields
        }
    }

    private struct SpecAddressRange: Decodable {
        let start: String
    }

    private struct SpecField: Decodable {
        let name: String
        let id: String
        let unit: String?
        let type: String
        let scaling: Double?
        let start: String
        let length: Int
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

private final class OpenTag3DBundleLocator: NSObject {}

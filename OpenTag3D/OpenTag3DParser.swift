//
//  OpenTag3DParser.swift
//  OpenTag3D
//

import Foundation

enum OpenTag3DSection: String {
    case core = "CORE"
    case extended = "EXTENDED"
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
        case .invalidValue(let expected):
            return "Enter \(expected)."
        case .outOfRange(let maximum):
            return "The encoded value must be between 0 and \(maximum)."
        case .wrongByteCount(let expected, let actual):
            return "Raw hex requires exactly \(expected) bytes; \(actual) were entered."
        case .textTooLong(let maximum):
            return "The text is too long for this field (maximum \(maximum) UTF-8 bytes)."
        }
    }
}

enum OpenTag3DParser {
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

    static func fields(from data: Data) -> [OpenTag3DFieldValue] {
        definitions.map { definition in
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
                    section: definition.section,
                    name: definition.name,
                    offset: definition.offset,
                    length: definition.length,
                    rawHex: rawHex,
                    numericValue: "—",
                    humanReadableValue: "Not present"
                )
            }

            let decoded = definition.decode([UInt8](bytes))
            return OpenTag3DFieldValue(
                id: definition.id,
                section: definition.section,
                name: definition.name,
                offset: definition.offset,
                length: definition.length,
                rawHex: rawHex,
                numericValue: decoded.numeric,
                humanReadableValue: decoded.humanReadable
            )
        }
    }

    static func replacingField(
        id: String,
        source: OpenTag3DEditSource,
        text: String,
        in originalData: Data
    ) throws -> Data {
        guard let definition = definitions.first(where: { $0.id == id }) else {
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

    private struct DecodedValue {
        let numeric: String
        let humanReadable: String
    }

    private struct FieldDefinition {
        let id: String
        let section: OpenTag3DSection
        let name: String
        let offset: Int
        let length: Int
        let decode: ([UInt8]) -> DecodedValue
    }

    private static func unsignedInteger(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static let textFieldIDs: Set<String> = [
        "material_base", "material_mod", "manufacturer", "color_name",
        "online_data_url", "serial"
    ]

    private static let temperatureFieldIDs: Set<String> = [
        "print_temp", "bed_temp", "mfi_temp", "max_dry_temp",
        "min_print_temp", "max_print_temp", "min_bed_temp", "max_bed_temp"
    ]

    private static func bytesFromNumericText(
        _ text: String,
        for definition: FieldDefinition
    ) throws -> [UInt8] {
        if textFieldIDs.contains(definition.id) {
            throw OpenTag3DEditError.numericNotApplicable
        }
        if definition.id.hasPrefix("color_") {
            return try byteList(from: text, count: 4)
        }
        if definition.id == "mfg_date" {
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        }
        if definition.id == "mfg_time" {
            let values = try integerList(from: text, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        }

        guard let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OpenTag3DEditError.invalidValue("an unsigned integer")
        }
        return try bigEndianBytes(value, length: definition.length)
    }

    private static func bytesFromHumanText(
        _ text: String,
        for definition: FieldDefinition
    ) throws -> [UInt8] {
        if textFieldIDs.contains(definition.id) {
            let value = text == "(empty)" ? "" : text
            let bytes = [UInt8](value.utf8)
            if definition.id == "online_data_url", bytes.contains(where: { $0 > 0x7F }) {
                throw OpenTag3DEditError.invalidValue("an ASCII URL")
            }
            guard bytes.count <= definition.length else {
                throw OpenTag3DEditError.textTooLong(maximum: definition.length)
            }
            return bytes + Array(repeating: 0, count: definition.length - bytes.count)
        }
        if definition.id.hasPrefix("color_") {
            let beforeDescription = text.split(separator: "(", maxSplits: 1)[0]
            let hex = beforeDescription.filter { $0.isHexDigit }
            guard hex.count == 8 else {
                throw OpenTag3DEditError.invalidValue("an 8-digit RRGGBBAA color")
            }
            return [UInt8](try data(from: hex))
        }
        if definition.id == "mfg_date" {
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        }
        if definition.id == "mfg_time" {
            let withoutUTC = text.replacingOccurrences(of: "UTC", with: "", options: .caseInsensitive)
            let values = try integerList(from: withoutUTC, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        }

        let displayedValue = try firstDecimal(in: text)
        let rawValue: Double
        switch definition.id {
        case "tag_version", "target_diameter", "density":
            rawValue = displayedValue * 1_000
        case "td", "mfi_value":
            rawValue = displayedValue * 10
        case let id where temperatureFieldIDs.contains(id):
            rawValue = displayedValue / 5
        case "mfi_load":
            rawValue = text.lowercased().contains("kg")
                ? displayedValue * 100
                : displayedValue / 10
        default:
            rawValue = displayedValue
        }

        guard rawValue.isFinite, rawValue >= 0, rawValue.rounded() == rawValue else {
            throw OpenTag3DEditError.invalidValue("a value representable by this field’s scaling")
        }
        return try bigEndianBytes(UInt64(rawValue), length: definition.length)
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
        let maximum = (UInt64(1) << UInt64(length * 8)) - 1
        guard value <= maximum else {
            throw OpenTag3DEditError.outOfRange(maximum: maximum)
        }
        return (0..<length).map { index in
            let shift = UInt64((length - index - 1) * 8)
            return UInt8((value >> shift) & 0xFF)
        }
    }

    private static func integer(
        id: String,
        section: OpenTag3DSection,
        name: String,
        offset: Int,
        length: Int,
        humanReadable: @escaping (UInt64) -> String
    ) -> FieldDefinition {
        FieldDefinition(id: id, section: section, name: name, offset: offset, length: length) { bytes in
            let value = unsignedInteger(bytes)
            return DecodedValue(numeric: String(value), humanReadable: humanReadable(value))
        }
    }

    private static func text(
        id: String,
        section: OpenTag3DSection,
        name: String,
        offset: Int,
        length: Int
    ) -> FieldDefinition {
        FieldDefinition(id: id, section: section, name: name, offset: offset, length: length) { bytes in
            let content = bytes.prefix { $0 != 0 }
            let value = String(decoding: content, as: UTF8.self)
            return DecodedValue(numeric: "—", humanReadable: value.isEmpty ? "(empty)" : value)
        }
    }

    private static func rgba(id: String, name: String, offset: Int) -> FieldDefinition {
        FieldDefinition(id: id, section: .core, name: name, offset: offset, length: 4) { bytes in
            let numeric = bytes.map(String.init).joined(separator: ", ")
            let hex = bytes.map { String(format: "%02X", $0) }.joined()
            return DecodedValue(numeric: numeric, humanReadable: "#\(hex) (RGBA)")
        }
    }

    private static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.*f", places, value)
    }

    // OpenTag3D v1.001. Offsets are relative to the start of the NDEF payload.
    private static let definitions: [FieldDefinition] = [
        integer(id: "tag_version", section: .core, name: "Tag Version", offset: 0x00, length: 2) {
            decimal(Double($0) * 0.001, places: 3)
        },
        text(id: "material_base", section: .core, name: "Base Material Name", offset: 0x02, length: 5),
        text(id: "material_mod", section: .core, name: "Material Modifiers", offset: 0x07, length: 5),
        text(id: "manufacturer", section: .core, name: "Filament Manufacturer", offset: 0x1B, length: 16),
        text(id: "color_name", section: .core, name: "Color Name", offset: 0x2B, length: 32),
        rgba(id: "color_1", name: "Color 1 Hex", offset: 0x4B),
        rgba(id: "color_2", name: "Color 2 Hex", offset: 0x50),
        rgba(id: "color_3", name: "Color 3 Hex", offset: 0x54),
        rgba(id: "color_4", name: "Color 4 Hex", offset: 0x58),
        integer(id: "target_diameter", section: .core, name: "Target Diameter", offset: 0x5C, length: 2) {
            "\(decimal(Double($0) * 0.001, places: 3)) mm"
        },
        integer(id: "target_weight", section: .core, name: "Target Weight", offset: 0x5E, length: 2) { "\($0) g" },
        integer(id: "print_temp", section: .core, name: "Print Temperature", offset: 0x60, length: 1) { "\($0 * 5) °C" },
        integer(id: "bed_temp", section: .core, name: "Bed Temperature", offset: 0x61, length: 1) { "\($0 * 5) °C" },
        integer(id: "density", section: .core, name: "Density", offset: 0x62, length: 2) {
            "\(decimal(Double($0) * 0.001, places: 3)) g/cm³"
        },
        integer(id: "td", section: .core, name: "Transmission Distance (TD)", offset: 0x64, length: 2) {
            "\(decimal(Double($0) * 0.1, places: 1)) mm"
        },

        text(id: "online_data_url", section: .extended, name: "Online Data URL", offset: 0x70, length: 32),
        text(id: "serial", section: .extended, name: "Serial Number / Batch ID", offset: 0x90, length: 16),
        FieldDefinition(id: "mfg_date", section: .extended, name: "Manufacture Date", offset: 0xA0, length: 4) { bytes in
            let year = unsignedInteger(Array(bytes[0...1]))
            let numeric = "\(year), \(bytes[2]), \(bytes[3])"
            return DecodedValue(numeric: numeric, humanReadable: String(format: "%04llu-%02d-%02d", year, bytes[2], bytes[3]))
        },
        FieldDefinition(id: "mfg_time", section: .extended, name: "Manufacture Time", offset: 0xA4, length: 3) { bytes in
            let numeric = bytes.map(String.init).joined(separator: ", ")
            return DecodedValue(numeric: numeric, humanReadable: String(format: "%02d:%02d:%02d UTC", bytes[0], bytes[1], bytes[2]))
        },
        integer(id: "spool_core_diameter", section: .extended, name: "Spool Core Diameter", offset: 0xA7, length: 1) { "\($0) mm" },
        integer(id: "mfi_temp", section: .extended, name: "MFI Temp", offset: 0xA8, length: 1) { "\($0 * 5) °C" },
        integer(id: "mfi_load", section: .extended, name: "MFI Load", offset: 0xA9, length: 1) {
            "\($0 * 10) g (\(decimal(Double($0) * 0.01, places: 2)) kg)"
        },
        integer(id: "mfi_value", section: .extended, name: "MFI Value", offset: 0xAA, length: 1) {
            "\(decimal(Double($0) * 0.1, places: 1)) g/10 min"
        },
        integer(id: "measured_tolerance", section: .extended, name: "Measured Tolerance", offset: 0xAB, length: 1) { "\($0) µm" },
        integer(id: "empty_spool_weight", section: .extended, name: "Empty Spool Weight", offset: 0xAC, length: 2) { "\($0) g" },
        integer(id: "measured_filament_weight", section: .extended, name: "Measured Filament Weight", offset: 0xAE, length: 2) { "\($0) g" },
        integer(id: "measured_filament_length", section: .extended, name: "Measured Filament Length", offset: 0xB0, length: 2) { "\($0) m" },
        integer(id: "max_dry_temp", section: .extended, name: "Max Dry Temp", offset: 0xB2, length: 1) { "\($0 * 5) °C" },
        integer(id: "dry_time", section: .extended, name: "Dry Time", offset: 0xB3, length: 1) { "\($0) hr" },
        integer(id: "min_print_temp", section: .extended, name: "Min Print Temp", offset: 0xB4, length: 1) { "\($0 * 5) °C" },
        integer(id: "max_print_temp", section: .extended, name: "Max Print Temp", offset: 0xB5, length: 1) { "\($0 * 5) °C" },
        integer(id: "min_bed_temp", section: .extended, name: "Min Bed Temp", offset: 0xB6, length: 1) { "\($0 * 5) °C" },
        integer(id: "max_bed_temp", section: .extended, name: "Max Bed Temp", offset: 0xB7, length: 1) { "\($0 * 5) °C" },
        integer(id: "min_vso", section: .extended, name: "Min Volumetric Speed", offset: 0xB8, length: 1) { "\($0) mm³/s" },
        integer(id: "max_vso", section: .extended, name: "Max Volumetric Speed", offset: 0xB9, length: 1) { "\($0) mm³/s" },
        integer(id: "target_vso", section: .extended, name: "Target Volumetric Speed", offset: 0xBA, length: 1) { "\($0) mm³/s" }
    ]
}

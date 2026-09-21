//
//  TagPayloadEditor.swift
//  OpenTag3D
//

import Foundation
import OpenTag3DKit

/// Identifies which editable representation supplied a field's new value.
enum OpenTag3DEditSource {
    case humanReadable
    case numeric
    case rawHex
}

enum TagPayloadError: LocalizedError {
    case unknownField
    case numericNotApplicable
    case invalidValue(String)
    case outOfRange(maximum: UInt64)
    case wrongByteCount(expected: Int, actual: Int)
    case textTooLong(maximum: Int)
    case oddHexDigitCount
    case invalidHexCharacter(Character)

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
            return "The text is too long for this field (maximum \(maximum) bytes)."
        case .oddHexDigitCount:
            return "The hex data has an incomplete byte. Every byte needs two hex digits."
        case .invalidHexCharacter(let character):
            return "‘\(character)’ is not a hex digit. Use only 0–9, A–F, and whitespace."
        }
    }
}

/// App-only editing and formatting around the portable OpenTag3DKit parser.
enum TagPayloadEditor {
    static func parser(for payload: Data) throws -> OpenTag3DParser {
        let version = try OpenTag3DHeader.version(from: payload)
        return try OpenTag3DParser(bundledVersion: version)
    }

    static func data(from hexText: String) throws -> Data {
        var digits: [Character] = []
        for character in hexText {
            if character.isWhitespace {
                continue
            }
            if character.isHexDigit == false {
                throw TagPayloadError.invalidHexCharacter(character)
            }
            digits.append(character)
        }

        if digits.count % 2 != 0 {
            throw TagPayloadError.oddHexDigitCount
        }

        var bytes: [UInt8] = []
        var index = 0
        while index < digits.count {
            let byteText = String([digits[index], digits[index + 1]])
            if let byte = UInt8(byteText, radix: 16) {
                bytes.append(byte)
            }
            index += 2
        }
        return Data(bytes)
    }

    static func editableHex(for data: Data) -> String {
        let bytes = [UInt8](data)
        var lines: [String] = []
        var lineStart = 0

        while lineStart < bytes.count {
            let lineEnd = min(lineStart + 16, bytes.count)
            let line = bytes[lineStart..<lineEnd]
                .map { String(format: "%02X", $0) }
                .joined(separator: " ")
            lines.append(line)
            lineStart = lineEnd
        }

        return lines.joined(separator: "\n")
    }

    static func replacingField(
        id: String,
        source: OpenTag3DEditSource,
        text: String,
        in originalData: Data
    ) throws -> Data {
        let parser = try parser(for: originalData)
        let tag = try parser.parse(originalData)
        guard let field = tag[id] else {
            throw TagPayloadError.unknownField
        }

        let replacement: [UInt8]
        switch source {
        case .rawHex:
            replacement = [UInt8](try data(from: text))
            guard replacement.count == field.length else {
                throw TagPayloadError.wrongByteCount(
                    expected: field.length,
                    actual: replacement.count
                )
            }
        case .numeric:
            replacement = try bytesFromNumericText(text, for: field)
        case .humanReadable:
            replacement = try bytesFromHumanText(text, for: field)
        }

        var updatedData = originalData
        let requiredCount = field.offset + field.length
        if updatedData.count < requiredCount {
            updatedData.append(Data(repeating: 0, count: requiredCount - updatedData.count))
        }
        updatedData.replaceSubrange(field.offset..<requiredCount, with: replacement)
        return updatedData
    }

    private static func bytesFromNumericText(
        _ text: String,
        for field: OpenTag3DField
    ) throws -> [UInt8] {
        switch field.type {
        case .utf8, .ascii:
            throw TagPayloadError.numericNotApplicable
        case .rgba:
            return try byteList(from: text, count: field.length)
        case .date:
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        case .time:
            let values = try integerList(from: text, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        case .integer:
            guard let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TagPayloadError.invalidValue("an unsigned integer")
            }
            return try bigEndianBytes(value, length: field.length)
        }
    }

    private static func bytesFromHumanText(
        _ text: String,
        for field: OpenTag3DField
    ) throws -> [UInt8] {
        switch field.type {
        case .utf8, .ascii:
            let value = text == "(empty)" ? "" : text
            let bytes = [UInt8](value.utf8)
            if field.type == .ascii, bytes.contains(where: { $0 > 0x7F }) {
                throw TagPayloadError.invalidValue("ASCII text")
            }
            guard bytes.count <= field.length else {
                throw TagPayloadError.textTooLong(maximum: field.length)
            }
            return bytes + Array(repeating: 0, count: field.length - bytes.count)
        case .rgba:
            let hex = text.filter { $0.isHexDigit }
            guard hex.count == field.length * 2 else {
                throw TagPayloadError.invalidValue(
                    "a \(field.length * 2)-digit hexadecimal color"
                )
            }
            return [UInt8](try data(from: hex))
        case .date:
            let values = try integerList(from: text, count: 3)
            return try dateBytes(year: values[0], month: values[1], day: values[2])
        case .time:
            let withoutUTC = text.replacingOccurrences(
                of: "UTC",
                with: "",
                options: .caseInsensitive
            )
            let values = try integerList(from: withoutUTC, count: 3)
            return try timeBytes(hour: values[0], minute: values[1], second: values[2])
        case .integer:
            let displayedValue = try firstDecimal(in: text)
            let scaling = field.scaling ?? 1
            let rawValue = displayedValue / scaling
            guard rawValue.isFinite,
                  rawValue >= 0,
                  abs(rawValue.rounded() - rawValue) < 0.000_000_1 else {
                throw TagPayloadError.invalidValue(
                    "a value representable using the field's scaling"
                )
            }
            return try bigEndianBytes(UInt64(rawValue.rounded()), length: field.length)
        }
    }

    private static func firstDecimal(in text: String) throws -> Double {
        let scanner = Scanner(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let value = scanner.scanDouble() else {
            throw TagPayloadError.invalidValue("a number, optionally followed by its unit")
        }
        return value
    }

    private static func integerList(from text: String, count: Int) throws -> [UInt64] {
        let components = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard components.count == count,
              components.allSatisfy({ UInt64($0) != nil }) else {
            throw TagPayloadError.invalidValue("\(count) integer values")
        }
        return components.map { UInt64($0)! }
    }

    private static func byteList(from text: String, count: Int) throws -> [UInt8] {
        let values = try integerList(from: text, count: count)
        guard values.allSatisfy({ $0 <= UInt8.max }) else {
            throw TagPayloadError.invalidValue("\(count) values between 0 and 255")
        }
        return values.map(UInt8.init)
    }

    private static func dateBytes(year: UInt64, month: UInt64, day: UInt64) throws -> [UInt8] {
        guard year <= UInt16.max, (1...12).contains(month), (1...31).contains(day) else {
            throw TagPayloadError.invalidValue("a date formatted as YYYY-MM-DD")
        }
        return try bigEndianBytes(year, length: 2) + [UInt8(month), UInt8(day)]
    }

    private static func timeBytes(hour: UInt64, minute: UInt64, second: UInt64) throws -> [UInt8] {
        guard hour <= 23, minute <= 59, second <= 59 else {
            throw TagPayloadError.invalidValue("a 24-hour time formatted as HH:MM:SS")
        }
        return [UInt8(hour), UInt8(minute), UInt8(second)]
    }

    private static func bigEndianBytes(_ value: UInt64, length: Int) throws -> [UInt8] {
        let maximum = length >= MemoryLayout<UInt64>.size
            ? UInt64.max
            : (UInt64(1) << UInt64(length * 8)) - 1
        guard value <= maximum else {
            throw TagPayloadError.outOfRange(maximum: maximum)
        }
        return (0..<length).map { index in
            let shift = (length - index - 1) * 8
            return UInt8((value >> UInt64(shift)) & 0xFF)
        }
    }
}

extension OpenTag3DField {
    var offsetDescription: String {
        String(format: "0x%02X (%d byte%@)", offset, length, length == 1 ? "" : "s")
    }

    var rawHexText: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var numericText: String {
        switch value {
        case .integer, .number:
            return rawInteger.map(String.init) ?? "—"
        case .text:
            return "—"
        case .color(let red, let green, let blue, let alpha):
            return "\(red), \(green), \(blue), \(alpha)"
        case .date(let year, let month, let day):
            return "\(year), \(month), \(day)"
        case .time(let hour, let minute, let second):
            return "\(hour), \(minute), \(second)"
        }
    }

    var humanReadableText: String {
        description.isEmpty ? "(empty)" : description
    }
}

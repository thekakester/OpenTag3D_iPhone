import Foundation

// These are the Swift data types used to represent the fields and values
// described by an OpenTag3D spec-XXXX.json file. The parser uses these
// models to return structured OpenTag3D data instead of raw bytes.

/// The binary representation used by a field in an OpenTag3D specification.
public enum OpenTag3DFieldType: String, Equatable, Sendable {
    /// An unsigned, big-endian integer.
    case integer
    /// Null-padded UTF-8 text.
    case utf8
    /// Null-padded ASCII text.
    case ascii
    /// Four bytes in red, green, blue, alpha order.
    case rgba
    /// Two bytes for year, followed by one byte each for month and day.
    case date
    /// One byte each for hour, minute, and second.
    case time
}

/// A strongly typed value decoded from an OpenTag3D field.
///
/// Example values include:
///
/// ```swift
/// let diameterValue: OpenTag3DValue = .number(1.750)
/// let manufacturerValue: OpenTag3DValue = .text("Polar Filament")
/// ```
///
/// Read a filament diameter value:
///
/// ```swift
/// let diameter = tag["diameter"]?.value
/// // diameter is Optional(.number(1.750))
/// ```
///
/// Read the filament manufacturer value:
///
/// ```swift
/// let manufacturer = tag["manufacturer"]?.value
/// // manufacturer is Optional(.text("Polar Filament"))
/// ```
public enum OpenTag3DValue: Equatable, Sendable {
    /// An integer field without scaling.
    case integer(UInt64)
    /// An integer field after applying the specification's scaling value.
    case number(Decimal)
    case text(String)
    case color(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    case date(year: Int, month: Int, day: Int)
    case time(hour: Int, minute: Int, second: Int)
}

/// One field decoded according to its entry in the OpenTag3D specification.
///
/// `value` is the strongly typed result, `description` is suitable for display,
/// and `data`, `bytes`, and `hex` expose the original encoded field bytes.
///
/// Example fields include:
///
/// - `manufacturer`: UTF-8 text such as `"Polar Filament"` at offset `0x0C`.
/// - `diameter`: a scaled number such as `1.750 mm` at offset `0x8C`.
/// - `color_1`: an RGBA color such as `#FA34C5FF` at offset `0x3C`.
/// - `mfg_date`: a date such as `2026-08-06` at offset `0x84`.
public struct OpenTag3DField: Identifiable, CustomStringConvertible, Sendable {
    /// Stable field identifier from the specification, such as `diameter`.
    public let id: String
    /// Human-readable field name from the specification.
    public let name: String
    /// Zero-based byte offset in the OpenTag3D payload.
    public let offset: Int
    /// Encoded field length in bytes.
    public let length: Int
    public let type: OpenTag3DFieldType
    public let unit: String?
    /// Multiplier applied to the raw integer value, such as `0.001` for diameter.
    public let scaling: Double?
    public let addedVersion: String?
    public let usage: String?
    public let isRequired: Bool
    public let documentation: String?
    /// Strongly typed value after decoding and applying scaling.
    ///
    /// For example:
    ///
    /// - `manufacturer` → `.text("Polar Filament")`
    /// - `diameter` → `.number(1.750)`
    /// - `weight` → `.integer(1000)`
    /// - `color_1` → `.color(red: 250, green: 52, blue: 197, alpha: 255)`
    /// - `mfg_date` → `.date(year: 2026, month: 8, day: 6)`
    public let value: OpenTag3DValue
    /// Original unscaled integer, or `nil` for non-integer fields.
    public let rawInteger: UInt64?
    /// Exact encoded bytes for this field.
    public let data: Data
    /// Human-readable value, including its unit when applicable.
    public let description: String

    /// Exact encoded bytes represented as an array.
    public var bytes: [UInt8] {
        Array(data)
    }

    /// Uppercase hexadecimal without spaces or other formatting.
    public var hex: String {
        data.openTag3DHex
    }
}

/// A complete OpenTag3D payload decoded with a particular specification.
public struct OpenTag3DTag: Sendable {
    /// Integer version read from the first two payload bytes.
    public let reportedVersion: UInt16
    /// Integer version declared by the specification used to parse the payload.
    public let specificationVersion: UInt16
    public let mimeType: String
    /// Original payload exactly as supplied to the parser.
    public let data: Data
    /// All decoded fields in payload order.
    public let fields: [OpenTag3DField]

    public var bytes: [UInt8] {
        Array(data)
    }

    /// Uppercase hexadecimal without spaces or other formatting.
    public var hex: String {
        data.openTag3DHex
    }

    /// Finds a field by its stable specification identifier.
    public func field(id: String) -> OpenTag3DField? {
        fields.first { $0.id == id }
    }

    /// Finds a field by its stable specification identifier.
    ///
    /// ```swift
    /// let diameter = tag["diameter"]
    /// print(diameter?.description ?? "Missing")
    /// ```
    public subscript(fieldID: String) -> OpenTag3DField? {
        field(id: fieldID)
    }
}

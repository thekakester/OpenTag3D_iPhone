import Foundation

/// Parses raw OpenTag3D payloads using a data-driven JSON specification.
///
/// Field names, offsets, lengths, types, scaling, and units come from the
/// official JSON specification published by OpenTag3D rather than being
/// hardcoded in this library. Supporting a future specification version is
/// therefore mainly a matter of downloading the newest JSON file and passing
/// it to `OpenTag3DParser`.
///
/// The default initializer uses the specification bundled with this package:
///
/// ```swift
/// let parser = try OpenTag3DParser()
/// let tag = try parser.parse(ndefRecordPayload)
/// print(tag["manufacturer"]?.description ?? "Unknown")
/// ```
///
/// The parser has no dependency on CoreNFC. Callers are responsible for
/// obtaining the payload bytes from NFC, a file, a network response, or any
/// other source.
public struct OpenTag3DParser: Sendable {
    private let specification: OpenTag3DSpecification

    /// Creates a parser using the current specification bundled with OpenTag3DKit.
    public init() throws {
        guard let url = Bundle.module.url(forResource: "spec-2003", withExtension: "json") else {
            throw OpenTag3DError.missingDefaultSpecification
        }
        try self.init(specificationJSON: Data(contentsOf: url))
    }

    /// Creates a parser using a caller-supplied OpenTag3D specification.
    public init(specificationJSON: Data) throws {
        specification = try OpenTag3DSpecification.decode(specificationJSON)
    }

    /// Creates a parser using an OpenTag3D specification file.
    public init(specificationURL: URL) throws {
        try self.init(specificationJSON: Data(contentsOf: specificationURL))
    }

    /// Parses a binary OpenTag3D payload.
    ///
    /// The first two bytes must match the parser's specification version.
    /// Missing trailing bytes are interpreted as zero as required by the
    /// OpenTag3D reader guidelines. `OpenTag3DTag.data` still contains the
    /// original, unpadded payload.
    public func parse(_ data: Data) throws -> OpenTag3DTag {
        let reportedVersion = try OpenTag3DHeader.version(from: data)
        guard reportedVersion == specification.version else {
            throw OpenTag3DError.versionMismatch(
                payload: reportedVersion,
                specification: specification.version
            )
        }
        let fields = try specification.fields.map { definition in
            try decodeField(definition, payload: data)
        }

        return OpenTag3DTag(
            reportedVersion: reportedVersion,
            specificationVersion: specification.version,
            mimeType: specification.mimeType,
            data: data,
            fields: fields
        )
    }

    /// Parses hexadecimal OpenTag3D payload text.
    ///
    /// Whitespace is allowed, so compact and formatted input are equivalent:
    ///
    /// ```swift
    /// let compact = try parser.parse(hex: "07D3504C")
    /// let formatted = try parser.parse(hex: "07 D3 50 4C")
    /// ```
    public func parse(hex: String) throws -> OpenTag3DTag {
        try parse(OpenTag3DHex.decode(hex))
    }

    /// Decodes one field from the payload using its definition in spec-XXXX.json.
    ///
    /// A field is one named piece of OpenTag3D data with a byte offset, length,
    /// type, and optional scaling. For example:
    ///
    /// - `diameter` starts at offset `0x8C` and is two bytes long. Bytes
    ///   `06 D6` decode to the raw integer `1750`, which becomes `1.750 mm`
    ///   after applying the specification's `0.001` scaling.
    /// - `manufacturer` starts at offset `0x0C` and is 16 bytes of UTF-8 text.
    ///   Bytes beginning with `50 6F 6C 61 72` decode to `"Polar..."`, with
    ///   trailing zero bytes ignored.
    ///
    /// If part or all of the field is beyond the end of the supplied payload,
    /// its missing bytes are decoded as `0x00`.
    private func decodeField(
        _ definition: OpenTag3DSpecification.Field,
        payload: Data
    ) throws -> OpenTag3DField {
        // Read whatever bytes exist for this field. If the payload ends before
        // the field does, OpenTag3D requires the missing bytes to be treated as
        // 0x00.
        var fieldBytes = [UInt8](repeating: 0, count: definition.length)
        var fieldByteIndex = 0

        // Copy each available payload byte into the field, leaving 0x00 in any
        // position that extends past the end of the payload.
        while fieldByteIndex < definition.length {
            let payloadOffset = definition.offset + fieldByteIndex

            if payloadOffset < payload.count {
                let payloadIndex = payload.index(
                    payload.startIndex,
                    offsetBy: payloadOffset
                )
                fieldBytes[fieldByteIndex] = payload[payloadIndex]
            }

            fieldByteIndex += 1
        }

        let fieldData = Data(fieldBytes)
        let decoded = try decodeValue(fieldData, definition: definition)

        return OpenTag3DField(
            id: definition.id,
            name: definition.name,
            offset: definition.offset,
            length: definition.length,
            type: definition.type,
            unit: definition.unit,
            addedVersion: definition.addedVersion,
            usage: definition.usage,
            isRequired: definition.isRequired,
            documentation: definition.documentation,
            value: decoded.value,
            rawInteger: decoded.rawInteger,
            data: fieldData,
            description: decoded.description
        )
    }

    /// Converts one field's bytes into a `DecodedValue`.
    ///
    /// `DecodedValue` contains the typed value, the original unscaled integer
    /// when applicable, and a human-readable string formatted with its unit.
    /// For example, decoding `diameter` returns the equivalent of:
    ///
    /// ```swift
    /// DecodedValue(
    ///     value: .number(1.750),
    ///     rawInteger: 1750,
    ///     description: "1.750 mm"
    /// )
    /// ```
    private func decodeValue(
        _ data: Data,
        definition: OpenTag3DSpecification.Field
    ) throws -> DecodedValue {
        let bytes = [UInt8](data)

        switch definition.type {
        case .integer:
            let rawValue = unsignedInteger(bytes)
            let scaling = definition.scaling ?? 1
            let scaledValue = Double(rawValue) * scaling
            let decimalPlaces = decimalPlaces(for: scaling)
            let locale = Locale(identifier: "en_US_POSIX")
            let formatted = decimalPlaces == 0
                ? String(format: "%.0f", locale: locale, scaledValue)
                : String(format: "%.*f", locale: locale, decimalPlaces, scaledValue)
            let value: OpenTag3DValue
            if definition.scaling == nil || scaling == 1 {
                value = .integer(rawValue)
            } else {
                value = .number(
                    Decimal(
                        string: formatted,
                        locale: Locale(identifier: "en_US_POSIX")
                    ) ?? Decimal(scaledValue)
                )
            }
            let description = formatWithUnit(formatted, unit: definition.unit)
            return DecodedValue(
                value: value,
                rawInteger: rawValue,
                description: description
            )

        case .utf8:
            // `$0` is the current byte. Keep bytes until the first 0x00 padding byte.
            let content = Data(bytes.prefix { $0 != 0 })
            guard let text = String(data: content, encoding: .utf8) else {
                throw OpenTag3DError.invalidText(fieldID: definition.id, encoding: "UTF-8")
            }
            return DecodedValue(value: .text(text), rawInteger: nil, description: text)

        case .ascii:
            // Keep bytes until 0x00, then verify every byte is valid ASCII (0–127).
            let content = bytes.prefix { $0 != 0 }
            guard content.allSatisfy({ $0 <= 0x7F }) else {
                throw OpenTag3DError.invalidText(fieldID: definition.id, encoding: "ASCII")
            }
            let text = String(decoding: content, as: UTF8.self)
            return DecodedValue(value: .text(text), rawInteger: nil, description: text)

        case .rgba:
            guard bytes.count == 4 else {
                throw OpenTag3DError.invalidSpecification(
                    "RGBA field ‘\(definition.id)’ must contain exactly four bytes."
                )
            }
            return DecodedValue(
                value: .color(
                    red: bytes[0],
                    green: bytes[1],
                    blue: bytes[2],
                    alpha: bytes[3]
                ),
                rawInteger: nil,
                description: "#\(data.openTag3DHex)"
            )

        case .date:
            guard bytes.count == 4 else {
                throw OpenTag3DError.invalidSpecification(
                    "Date field ‘\(definition.id)’ must contain exactly four bytes."
                )
            }
            let year = Int(unsignedInteger(Array(bytes[0...1])))
            let month = Int(bytes[2])
            let day = Int(bytes[3])
            return DecodedValue(
                value: .date(year: year, month: month, day: day),
                rawInteger: nil,
                description: String(format: "%04d-%02d-%02d", year, month, day)
            )

        case .time:
            guard bytes.count == 3 else {
                throw OpenTag3DError.invalidSpecification(
                    "Time field ‘\(definition.id)’ must contain exactly three bytes."
                )
            }
            return DecodedValue(
                value: .time(
                    hour: Int(bytes[0]),
                    minute: Int(bytes[1]),
                    second: Int(bytes[2])
                ),
                rawInteger: nil,
                description: String(format: "%02d:%02d:%02d UTC", bytes[0], bytes[1], bytes[2])
            )
        }
    }

    /// Formats a decoded value for display by adding its unit when applicable.
    /// For example, `formatWithUnit("1.750", unit: "mm")` returns `"1.750 mm"`.
    /// Values without a unit, and version values, are returned unchanged.
    private func formatWithUnit(_ value: String, unit: String?) -> String {
        guard let unit, !unit.isEmpty, unit != "version" else {
            return value
        }
        return "\(value) \(unit)"
    }

    /// Returns how many digits should be displayed after the decimal point for
    /// a scaling value. This is not a significant-figures calculation.
    ///
    /// Examples:
    ///
    /// - Scaling `1` returns `0` decimal places.
    /// - Scaling `0.1` returns `1` decimal place.
    /// - Scaling `0.25` returns `2` decimal places because `0.25 × 100 = 25`.
    /// - Scaling `0.01` returns `2` decimal places.
    /// - Scaling `0.001` returns `3` decimal places.
    ///
    /// For example, diameter uses scaling `0.001`, so raw value `1750` is
    /// formatted with three decimal places as `1.750`.
    private func decimalPlaces(for scaling: Double) -> Int {
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

    private func unsignedInteger(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private struct DecodedValue {
    let value: OpenTag3DValue
    let rawInteger: UInt64?
    let description: String
}

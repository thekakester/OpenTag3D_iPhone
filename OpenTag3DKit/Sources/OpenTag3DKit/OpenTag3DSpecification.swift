import Foundation

/// A Swift representation of the rules defined by an OpenTag3D
/// `spec-XXXX.json` file.
///
/// This describes how a tag should be parsed, including its version, MIME type,
/// field names, offsets, lengths, types, scaling, and units. It is the
/// specification itself—not the values read from an individual NFC tag.
struct OpenTag3DSpecification: Sendable {
    let version: UInt16
    let mimeType: String
    let fields: [Field]

    struct Field: Sendable {
        let id: String
        let name: String
        let type: OpenTag3DFieldType
        let unit: String?
        let scaling: Double?
        let offset: Int
        let length: Int
        let addedVersion: String?
        let usage: String?
        let isRequired: Bool
        let documentation: String?
    }

    /// Decodes the JSON specification itself into an `OpenTag3DSpecification`.
    ///
    /// The supplied `Data` contains the contents of a `spec-XXXX.json` file,
    /// not an OpenTag3D NFC payload. Actual tag payloads are decoded later by
    /// `OpenTag3DParser` using the rules returned by this function.
    static func decode(_ data: Data) throws -> OpenTag3DSpecification {
        let document: SpecDocument
        do {
            document = try JSONDecoder().decode(SpecDocument.self, from: data)
        } catch {
            throw OpenTag3DError.invalidSpecification(error.localizedDescription)
        }

        let version = try encodedVersion(document.version)
        guard !document.mimeType.isEmpty else {
            throw OpenTag3DError.invalidSpecification("mime_type cannot be empty.")
        }

        var seenFieldIDs: Set<String> = []
        let fields = try document.fields.map { fieldDocument in
            guard !fieldDocument.id.isEmpty else {
                throw OpenTag3DError.invalidSpecification("A field id cannot be empty.")
            }
            guard seenFieldIDs.insert(fieldDocument.id).inserted else {
                throw OpenTag3DError.invalidSpecification(
                    "Field id ‘\(fieldDocument.id)’ appears more than once."
                )
            }
            guard fieldDocument.length > 0 else {
                throw OpenTag3DError.invalidSpecification(
                    "Field ‘\(fieldDocument.id)’ must have a positive length."
                )
            }

            let type = try parseFieldType(fieldDocument.type)
            try validateLength(
                fieldDocument.length,
                for: type,
                fieldID: fieldDocument.id
            )
            if let scaling = fieldDocument.scaling,
               (!scaling.isFinite || scaling <= 0) {
                throw OpenTag3DError.invalidSpecification(
                    "Field ‘\(fieldDocument.id)’ must have positive, finite scaling."
                )
            }

            return Field(
                id: fieldDocument.id,
                name: fieldDocument.name,
                type: type,
                unit: fieldDocument.unit,
                scaling: fieldDocument.scaling,
                offset: try parseHexByteOffset(fieldDocument.start),
                length: fieldDocument.length,
                addedVersion: fieldDocument.added,
                usage: fieldDocument.usage,
                isRequired: fieldDocument.required ?? false,
                documentation: fieldDocument.description
            )
        }
        // Sort fields by their byte position in the payload. `$0` and `$1` are
        // the two fields being compared; the field with the lower offset comes first.
        .sorted { $0.offset < $1.offset }

        guard !fields.isEmpty else {
            throw OpenTag3DError.invalidSpecification("At least one payload field is required.")
        }

        return OpenTag3DSpecification(
            version: version,
            mimeType: document.mimeType,
            fields: fields
        )
    }

    /// Converts the specification's readable version string into the integer
    /// format stored in the first two payload bytes.
    ///
    /// For example, `"2.003"` becomes `2003`. This lets the parser compare the
    /// version declared by spec-2003.json with the version read from the tag.
    private static func encodedVersion(_ text: String) throws -> UInt16 {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[1].count == 3,
              let major = UInt32(parts[0]),
              let minor = UInt32(parts[1]),
              minor <= 999,
              major * 1_000 + minor <= UInt16.max else {
            throw OpenTag3DError.invalidSpecification(
                "Version ‘\(text)’ must use the form major.minor with three minor digits."
            )
        }
        return UInt16(major * 1_000 + minor)
    }

    /// Converts a hexadecimal byte offset from the JSON specification into an
    /// integer. For example, `"0x8C"` becomes `140`.
    private static func parseHexByteOffset(_ text: String) throws -> Int {
        let digits = text.lowercased().hasPrefix("0x")
            ? String(text.dropFirst(2))
            : text
        guard let value = Int(digits, radix: 16) else {
            throw OpenTag3DError.invalidSpecification("‘\(text)’ is not a valid offset.")
        }
        return value
    }

    /// Converts a field type name from the JSON specification into the matching
    /// Swift `OpenTag3DFieldType`. For example, `"int"` becomes `.integer`.
    private static func parseFieldType(_ text: String) throws -> OpenTag3DFieldType {
        switch text.lowercased() {
        case "int": return .integer
        case "utf8": return .utf8
        case "ascii": return .ascii
        case "rgba": return .rgba
        case "date": return .date
        case "time": return .time
        default: throw OpenTag3DError.unsupportedFieldType(text)
        }
    }

    /// Checks that a field's byte length is valid for its type.
    ///
    /// For example, an RGBA color and date must be four bytes, a time must be
    /// three bytes, and an integer cannot exceed the eight bytes held by UInt64.
    /// Text fields may have any positive length.
    private static func validateLength(
        _ length: Int,
        for type: OpenTag3DFieldType,
        fieldID: String
    ) throws {
        let isValid: Bool
        switch type {
        case .integer:
            isValid = length <= MemoryLayout<UInt64>.size
        case .rgba:
            isValid = length == 4
        case .date:
            isValid = length == 4
        case .time:
            isValid = length == 3
        case .utf8, .ascii:
            isValid = true
        }

        guard isValid else {
            throw OpenTag3DError.invalidSpecification(
                "Field ‘\(fieldID)’ has an invalid length for type ‘\(type.rawValue)’."
            )
        }
    }
}

/// The initial Swift representation produced when JSONDecoder reads the entire
/// spec-XXXX.json document.
///
/// It reads the specification version, MIME type, and payload field definitions.
/// Other top-level data, such as `web_api`, is ignored. The result is then
/// validated and converted into `OpenTag3DSpecification`.
private struct SpecDocument: Decodable {
    let version: String
    let mimeType: String
    let payload: SpecPayload

    var fields: [SpecField] {
        payload.fields
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case mimeType = "mime_type"
        // The official JSON currently stores its payload definition under "core".
        case payload = "core"
    }
}

/// The part of spec-XXXX.json that describes bytes in the NFC payload.
private struct SpecPayload: Decodable {
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
    let added: String?
    let unit: String?
    let type: String
    let scaling: Double?
    let start: String
    let length: Int
    let usage: String?
    let required: Bool?
    let description: String?
}

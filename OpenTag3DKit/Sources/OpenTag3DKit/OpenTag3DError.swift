import Foundation

/// Errors produced while loading a specification or parsing an OpenTag3D payload.
public enum OpenTag3DError: Error, Equatable, LocalizedError, Sendable {
    case payloadTooShort(minimum: Int, actual: Int)
    case oddHexDigitCount
    case invalidHexCharacter(Character)
    case missingDefaultSpecification
    case invalidSpecification(String)
    case unsupportedFieldType(String)
    case versionMismatch(payload: UInt16, specification: UInt16)
    case invalidText(fieldID: String, encoding: String)

    public var errorDescription: String? {
        switch self {
        case .payloadTooShort(let minimum, let actual):
            return "The payload requires at least \(minimum) bytes but contains \(actual)."
        case .oddHexDigitCount:
            return "The hexadecimal input contains an incomplete byte."
        case .invalidHexCharacter(let character):
            return "The hexadecimal input contains the invalid character '\(character)'."
        case .missingDefaultSpecification:
            return "The default OpenTag3D specification is missing from the package."
        case .invalidSpecification(let reason):
            return "The OpenTag3D specification is invalid: \(reason)"
        case .unsupportedFieldType(let type):
            return "The OpenTag3D field type ‘\(type)’ is not supported."
        case .versionMismatch(let payload, let specification):
            return "Payload version \(payload) does not match specification version \(specification)."
        case .invalidText(let fieldID, let encoding):
            return "Field ‘\(fieldID)’ does not contain valid \(encoding) text."
        }
    }
}

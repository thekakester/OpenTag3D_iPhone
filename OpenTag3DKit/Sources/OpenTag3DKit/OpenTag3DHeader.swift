import Foundation

/// The first two bytes of every OpenTag3D payload contain the OpenTag3D version.
/// We read these bytes first so we know which version of the specification to
/// use when parsing the rest of the payload.
///
/// For example, a version value of `2003` tells the caller to load
/// `spec-2003.json` before parsing the complete payload:
///
/// ```swift
/// let payload = Data([0x07, 0xD3, 0x50, 0x4C])
/// let version = try OpenTag3DHeader.version(from: payload)
/// print(version) // 2003
///
/// let specificationName = "spec-\(version).json"
/// ```
///
/// Reading the version does not load or parse a specification file.
public enum OpenTag3DHeader {
    /// Returns the integer version encoded in the first two bytes.
    /// For example, bytes `07 D3` return `2003`.
    public static func version(from data: Data) throws -> UInt16 {
        guard data.count >= 2 else {
            throw OpenTag3DError.payloadTooShort(minimum: 2, actual: data.count)
        }

        return UInt16(data[data.startIndex]) << 8
            | UInt16(data[data.index(after: data.startIndex)])
    }

    /// Returns the integer version encoded by the first two hexadecimal bytes.
    public static func version(fromHex hex: String) throws -> UInt16 {
        try version(from: OpenTag3DHex.decode(hex))
    }
}

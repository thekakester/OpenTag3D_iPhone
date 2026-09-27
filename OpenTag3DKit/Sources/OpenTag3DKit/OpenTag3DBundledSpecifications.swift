import Foundation

/// Discovers the versions supported by the package's `spec-XXXX.json` files.
public enum OpenTag3DBundledSpecifications {
    /// All bundled specification versions in ascending numeric order.
    public static let supportedVersions = discoverSpecificationVersions().sorted()

    /// Reads version numbers from bundled files named `spec-XXXX.json`.
    private static func discoverSpecificationVersions() -> [UInt16] {
        guard let resourceURLs = Bundle.module.urls(
            forResourcesWithExtension: "json",
            subdirectory: "Specifications"
        ) else {
            return []
        }

        var versions: [UInt16] = []

        for resourceURL in resourceURLs {
            let fileName = resourceURL.deletingPathExtension().lastPathComponent
            guard fileName.hasPrefix("spec-") else {
                continue
            }

            let versionText = fileName.dropFirst("spec-".count)
            guard let version = UInt16(versionText) else {
                continue
            }

            versions.append(version)
        }

        return versions
    }

    /// Selects the exact bundled specification, or the newest earlier minor
    /// version in the same major-version family.
    public static func specificationVersion(for tagVersion: UInt16) throws -> UInt16 {
        let tagMajorVersion = OpenTag3DHeader.majorVersion(of: tagVersion)
        let sameMajorVersions = supportedVersions.filter { version in
            OpenTag3DHeader.majorVersion(of: version) == tagMajorVersion
        }

        guard sameMajorVersions.isEmpty == false else {
            throw OpenTag3DError.unsupportedMajorVersion(tagMajorVersion)
        }

        guard let selectedVersion = sameMajorVersions.last(where: { version in
            version <= tagVersion
        }) else {
            throw OpenTag3DError.unsupportedVersion(tagVersion)
        }
        return selectedVersion
    }
}

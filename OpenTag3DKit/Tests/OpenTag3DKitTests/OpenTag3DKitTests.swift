import Foundation
import Testing
@testable import OpenTag3DKit

struct OpenTag3DKitTests {
    @Test func readsVersionWithoutLoadingSpecification() throws {
        #expect(try OpenTag3DHeader.version(from: Data([0x07, 0xD3])) == 2003)
        #expect(try OpenTag3DHeader.version(fromHex: "07 D3 FF FF") == 2003)
    }

    @Test func parsesDefaultSpecification() throws {
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD3
        payload.replaceSubrange(0x0C..<(0x0C + 14), with: Data("Polar Filament".utf8))
        payload[0x8C] = 0x06
        payload[0x8D] = 0xD6

        let tag = try OpenTag3DParser().parse(payload)

        #expect(tag.reportedVersion == 2003)
        #expect(tag.specificationVersion == 2003)
        #expect(tag.mimeType == "application/opentag3d")
        #expect(tag["manufacturer"]?.description == "Polar Filament")
        #expect(tag["diameter"]?.rawInteger == 1750)
        #expect(tag["diameter"]?.description == "1.750 mm")
        #expect(tag["diameter"]?.hex == "06D6")
        #expect(tag["diameter"]?.bytes == [0x06, 0xD6])
    }

    @Test func parsesCallerSuppliedSpecification() throws {
        let specification = Data(
            #"{"version":"2.003","mime_type":"application/opentag3d","core":{"address_range":{"start":"0x00","end":"0x03"},"fields":[{"name":"Tag Version","id":"tag_version","type":"int","scaling":0.001,"start":"0x00","length":2},{"name":"Example","id":"example","type":"int","scaling":0.1,"unit":"mm","start":"0x02","length":2}]}}"#.utf8
        )
        let parser = try OpenTag3DParser(specificationJSON: specification)
        let tag = try parser.parse(Data([0x07, 0xD3, 0x03, 0xE9]))

        #expect(tag.reportedVersion == 2003)
        #expect(tag["example"]?.rawInteger == 1001)
        #expect(tag["example"]?.description == "100.1 mm")
        #expect(tag["example"]?.hex == "03E9")
    }

    @Test func rejectsSpecificationVersionMismatch() throws {
        let parser = try OpenTag3DParser()
        var payload = Data(repeating: 0, count: 0xD8)
        payload[0] = 0x07
        payload[1] = 0xD4

        #expect(throws: OpenTag3DError.versionMismatch(payload: 2004, specification: 2003)) {
            try parser.parse(payload)
        }
    }

    @Test func treatsMissingTrailingBytesAsZero() throws {
        let tag = try OpenTag3DParser().parse(Data([0x07, 0xD3]))

        #expect(tag.data == Data([0x07, 0xD3]))
        #expect(tag["diameter"]?.rawInteger == 0)
        #expect(tag["diameter"]?.hex == "0000")
    }

    @Test func parsesHexPayload() throws {
        let specification = Data(
            #"{"version":"2.003","mime_type":"application/opentag3d","core":{"address_range":{"start":"0x00","end":"0x01"},"fields":[{"name":"Tag Version","id":"tag_version","type":"int","scaling":0.001,"start":"0x00","length":2}]}}"#.utf8
        )
        let tag = try OpenTag3DParser(specificationJSON: specification).parse(hex: "07 D3")

        #expect(tag.reportedVersion == 2003)
        #expect(tag.hex == "07D3")
        #expect(tag.bytes == [0x07, 0xD3])
    }
}

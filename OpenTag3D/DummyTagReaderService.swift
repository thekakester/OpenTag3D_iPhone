//
//  DummyTagReaderService.swift
//  OpenTag3D
//

import Foundation

/// Reads a bundled JSON file that stands in for an NFC NDEF message.
final class DummyTagReaderService: ObservableObject {
    static let openTag3DMIMEType = "application/OpenTag3D"

    @Published private(set) var isReading = false
    @Published private(set) var statusMessage = "Enter a hex payload or read the bundled dummy tag."
    @Published private(set) var rawHexText = "00 00 00 00"
    @Published private(set) var coreFields: [OpenTag3DFieldValue] = []
    @Published private(set) var extendedFields: [OpenTag3DFieldValue] = []

    func beginReading() {
        isReading = true
        statusMessage = "Reading DummyOpenTag3DMessage.json…"

        defer { isReading = false }

        do {
            guard let fileURL = Bundle.main.url(
                forResource: "DummyOpenTag3DMessage",
                withExtension: "json"
            ) else {
                throw DummyTagError.missingFile
            }

            let fileData = try Data(contentsOf: fileURL)
            let message = try JSONDecoder().decode(DummyNDEFMessage.self, from: fileData)

            let matchingRecords = message.records.filter { record in
                record.typeNameFormat.caseInsensitiveCompare("media") == .orderedSame
                    && record.type.caseInsensitiveCompare(Self.openTag3DMIMEType) == .orderedSame
            }

            guard !matchingRecords.isEmpty else {
                statusMessage = "No application/OpenTag3D record was found in the dummy file."
                return
            }

            let payload = try OpenTag3DParser.data(from: matchingRecords[0].payloadHex)
            rawHexText = OpenTag3DParser.editableHex(for: payload)
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Read an OpenTag3D record from the dummy file (\(payload.count) bytes)."
        } catch {
            statusMessage = "Could not read the dummy tag: \(error.localizedDescription)"
        }
    }

    /// Called by the TextEditor every time the user changes the hex dump.
    func updateRawHexText(_ newValue: String) {
        rawHexText = newValue

        do {
            let payload = try refreshDecodedFieldsFromRawHex()
            statusMessage = "Decoded \(payload.count) edited payload bytes."
        } catch {
            coreFields = []
            extendedFields = []
            statusMessage = "Hex edit error: \(error.localizedDescription)"
        }
    }

    /// Encodes one bubble edit into the payload, then derives every display value again.
    func updateField(id: String, source: OpenTag3DEditSource, text: String) {
        do {
            let currentPayload = try OpenTag3DParser.data(from: rawHexText)
            let updatedPayload = try OpenTag3DParser.replacingField(
                id: id,
                source: source,
                text: text,
                in: currentPayload
            )

            rawHexText = OpenTag3DParser.editableHex(for: updatedPayload)
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Updated the payload from the edited field."
        } catch {
            statusMessage = "Field edit error: \(error.localizedDescription)"
        }
    }

    /// Rebuilds every displayed field from the current editable hex text.
    @discardableResult
    private func refreshDecodedFieldsFromRawHex() throws -> Data {
        let payload = try OpenTag3DParser.data(from: rawHexText)
        let fields = OpenTag3DParser.fields(from: payload)
        coreFields = fields.filter { $0.section == .core }
        extendedFields = fields.filter { $0.section == .extended }
        return payload
    }
}

private struct DummyNDEFMessage: Decodable {
    let records: [DummyNDEFRecord]
}

private struct DummyNDEFRecord: Decodable {
    let typeNameFormat: String
    let type: String
    let payloadHex: String
}

private enum DummyTagError: LocalizedError {
    case missingFile

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "DummyOpenTag3DMessage.json is missing from the app bundle."
        }
    }
}

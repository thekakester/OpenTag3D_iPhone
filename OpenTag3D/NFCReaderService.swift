//
//  NFCReaderService.swift
//  OpenTag3D
//

import CoreNFC
import Foundation
import OpenTag3DKit

/// Reads an OpenTag3D MIME record from an NDEF-compatible NFC tag.
final class NFCReaderService: NSObject, ObservableObject {
    private static let openTag3DMIMEType = "application/opentag3d"

    @Published private(set) var isReading = false
    @Published private(set) var statusMessage = "Enter a hex payload or scan an OpenTag3D tag."
    @Published private(set) var rawHexText = "00 00 00 00"
    @Published private(set) var fields: [OpenTag3DField] = []

    private var readerSession: NFCNDEFReaderSession?
    private var didFinishCurrentScan = false

    func beginReading() {
        guard NFCNDEFReaderSession.readingAvailable else {
            statusMessage = "NFC reading is not available on this device."
            return
        }

        didFinishCurrentScan = false
        isReading = true
        statusMessage = "Starting the NFC reader…"

        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        session.alertMessage = "Hold your iPhone near an OpenTag3D filament tag."
        readerSession = session
        session.begin()
    }

    /// Called by the TextEditor every time the user changes the hex dump.
    func updateRawHexText(_ newValue: String) {
        rawHexText = newValue

        do {
            let payload = try refreshDecodedFieldsFromRawHex()
            statusMessage = "Decoded \(payload.count) edited payload bytes."
        } catch {
            fields = []
            statusMessage = "Hex edit error: \(error.localizedDescription)"
        }
    }

    /// Encodes one bubble edit into the payload, then derives every display value again.
    func updateField(id: String, source: OpenTag3DEditSource, text: String) {
        do {
            let currentPayload = try TagPayloadEditor.data(from: rawHexText)
            let updatedPayload = try TagPayloadEditor.replacingField(
                id: id,
                source: source,
                text: text,
                in: currentPayload
            )

            rawHexText = TagPayloadEditor.editableHex(for: updatedPayload)
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Updated the payload from the edited field."
        } catch {
            statusMessage = "Field edit error: \(error.localizedDescription)"
        }
    }

    /// Rebuilds every displayed field from the current editable hex text.
    @discardableResult
    private func refreshDecodedFieldsFromRawHex() throws -> Data {
        let payload = try TagPayloadEditor.data(from: rawHexText)
        let parser = try TagPayloadEditor.parser(for: payload)
        fields = try parser.parse(payload).fields
        return payload
    }

    private func finishReading(payload: Data) {
        rawHexText = TagPayloadEditor.editableHex(for: payload)

        do {
            try refreshDecodedFieldsFromRawHex()
            statusMessage = "Read an OpenTag3D payload from the NFC tag (\(payload.count) bytes)."
        } catch {
            fields = []
            statusMessage = "The tag was read, but its payload could not be decoded: \(error.localizedDescription)"
        }

        isReading = false
    }
}

extension NFCReaderService: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "NFC reader active. Hold the top of your iPhone near the tag."
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        let matchingRecord = messages
            .flatMap(\.records)
            .first { record in
                guard record.typeNameFormat == .media,
                      let recordType = String(data: record.type, encoding: .utf8) else {
                    return false
                }
                return recordType.caseInsensitiveCompare(Self.openTag3DMIMEType) == .orderedSame
            }

        guard let matchingRecord else {
            didFinishCurrentScan = true
            session.invalidate(
                errorMessage: "This tag does not contain an application/opentag3d record."
            )
            DispatchQueue.main.async { [weak self] in
                self?.isReading = false
                self?.statusMessage = "The tag does not contain an OpenTag3D NDEF record."
            }
            return
        }

        didFinishCurrentScan = true
        session.alertMessage = "OpenTag3D tag read successfully."
        session.invalidate()

        let payload = matchingRecord.payload
        DispatchQueue.main.async { [weak self] in
            self?.finishReading(payload: payload)
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        let scanWasFinished = didFinishCurrentScan

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readerSession = nil
            self.isReading = false

            guard !scanWasFinished else { return }

            if let readerError = error as? NFCReaderError,
               readerError.code == .readerSessionInvalidationErrorUserCanceled {
                self.statusMessage = "NFC scan canceled."
            } else {
                self.statusMessage = "NFC scan ended: \(error.localizedDescription)"
            }
        }
    }
}

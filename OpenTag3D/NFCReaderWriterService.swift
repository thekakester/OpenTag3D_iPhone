//
//  NFCReaderWriterService.swift
//  OpenTag3D
//

import CoreNFC
import Foundation
import OpenTag3DKit

enum TagImportError: LocalizedError, Equatable {
    case emptySerialNumber
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case invalidResponseText
    case invalidQRCodeURL
    case unsupportedQRCodeHost
    case missingQRCodeSerialNumber

    var errorDescription: String? {
        switch self {
        case .emptySerialNumber:
            return "Enter a Polar Filament serial number."
        case .invalidURL:
            return "The Polar Filament import URL could not be created."
        case .invalidResponse:
            return "The Polar Filament API returned an invalid response."
        case .httpStatus(let statusCode):
            return "The Polar Filament API returned HTTP status \(statusCode)."
        case .invalidResponseText:
            return "The Polar Filament API response is not valid text."
        case .invalidQRCodeURL:
            return "The QR code does not contain a valid URL."
        case .unsupportedQRCodeHost:
            return "The QR code must use 3dqr.co or pfil.us."
        case .missingQRCodeSerialNumber:
            return "The QR code does not contain an i parameter with a serial number."
        }
    }
}

/// Reads and writes an OpenTag3D MIME record on an NDEF-compatible NFC tag.
final class NFCReaderWriterService: NSObject, ObservableObject {
    private static let openTag3DMIMEType = "application/opentag3d"

    private enum Operation {
        case read
        case write(Data)
    }

    @Published private(set) var isReading = false
    @Published private(set) var isWriting = false
    @Published private(set) var isImporting = false
    @Published private(set) var statusMessage = "Enter a hex payload or scan an OpenTag3D tag."
    @Published private(set) var rawHexText = "00 00 00 00"
    @Published private(set) var fields: [OpenTag3DField] = []

    private var readerSession: NFCNDEFReaderSession?
    private var didFinishCurrentScan = false
    private var operation: Operation = .read

    var isScanning: Bool {
        isReading || isWriting
    }

    var isBusy: Bool {
        isScanning || isImporting
    }

    static func normalizedSerialNumber(_ serialNumber: String) -> String {
        serialNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    static func polarFilamentImportURL(for serialNumber: String) -> URL? {
        var components = URLComponents(string: "https://pfil.us/opentag3d.php")
        components?.queryItems = [
            URLQueryItem(name: "id", value: normalizedSerialNumber(serialNumber)),
            URLQueryItem(name: "mode", value: "core"),
            URLQueryItem(name: "format", value: "hex")
        ]
        return components?.url
    }

    /// Extracts and normalizes a serial number from a supported OpenTag3D QR URL.
    static func serialNumber(fromQRCode qrCode: String) throws -> String {
        let trimmedQRCode = qrCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQRCode.isEmpty == false else {
            throw TagImportError.invalidQRCodeURL
        }

        let urlText: String
        if trimmedQRCode.contains("://") {
            urlText = trimmedQRCode
        } else {
            urlText = "https://\(trimmedQRCode)"
        }

        guard let components = URLComponents(string: urlText),
              let host = components.host?.lowercased() else {
            throw TagImportError.invalidQRCodeURL
        }
        guard host == "3dqr.co" || host == "pfil.us" else {
            throw TagImportError.unsupportedQRCodeHost
        }

        let serialNumber = components.queryItems?.first { queryItem in
            queryItem.name.lowercased() == "i"
        }?.value
        let normalizedSerialNumber = normalizedSerialNumber(serialNumber ?? "")

        guard normalizedSerialNumber.isEmpty == false else {
            throw TagImportError.missingQRCodeSerialNumber
        }
        return normalizedSerialNumber
    }

    /// Validates a QR code and sends its serial number through the same import
    /// path used by manually entered serial numbers.
    func importPolarFilamentTag(qrCode: String) {
        do {
            let serialNumber = try Self.serialNumber(fromQRCode: qrCode)
            importPolarFilamentTag(serialNumber: serialNumber)
        } catch {
            statusMessage = "Could not import QR code: \(error.localizedDescription)"
        }
    }

    /// Imports and decodes a Polar Filament tag without changing the current
    /// payload unless the request and the complete decode both succeed.
    func importPolarFilamentTag(serialNumber: String) {
        let normalizedSerialNumber = Self.normalizedSerialNumber(serialNumber)
        guard normalizedSerialNumber.isEmpty == false else {
            statusMessage = TagImportError.emptySerialNumber.localizedDescription
            return
        }
        guard let url = Self.polarFilamentImportURL(for: normalizedSerialNumber) else {
            statusMessage = TagImportError.invalidURL.localizedDescription
            return
        }

        isImporting = true
        statusMessage = "Importing Polar Filament tag \(normalizedSerialNumber)…"

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error {
                self?.finishImport(
                    result: .failure(error),
                    serialNumber: normalizedSerialNumber
                )
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                self?.finishImport(
                    result: .failure(TagImportError.invalidResponse),
                    serialNumber: normalizedSerialNumber
                )
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                self?.finishImport(
                    result: .failure(TagImportError.httpStatus(httpResponse.statusCode)),
                    serialNumber: normalizedSerialNumber
                )
                return
            }
            guard let data, let hexText = String(data: data, encoding: .utf8) else {
                self?.finishImport(
                    result: .failure(TagImportError.invalidResponseText),
                    serialNumber: normalizedSerialNumber
                )
                return
            }

            do {
                let payload = try TagPayloadEditor.data(from: hexText)
                let plan = try TagPayloadEditor.decodingPlan(for: payload)
                let decodedFields = try plan.parser.parse(payload).fields
                let importedTag = ImportedTag(
                    payload: payload,
                    fields: decodedFields,
                    warning: plan.warning
                )
                self?.finishImport(
                    result: .success(importedTag),
                    serialNumber: normalizedSerialNumber
                )
            } catch {
                self?.finishImport(
                    result: .failure(error),
                    serialNumber: normalizedSerialNumber
                )
            }
        }.resume()
    }

    private struct ImportedTag {
        let payload: Data
        let fields: [OpenTag3DField]
        let warning: String?
    }

    private func finishImport(
        result: Result<ImportedTag, Error>,
        serialNumber: String
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isImporting = false

            switch result {
            case .success(let importedTag):
                self.rawHexText = TagPayloadEditor.editableHex(for: importedTag.payload)
                self.fields = importedTag.fields
                self.statusMessage = importedTag.warning
                    ?? "Imported Polar Filament tag \(serialNumber) (\(importedTag.payload.count) bytes)."
            case .failure(let error):
                self.statusMessage = "Could not import tag \(serialNumber): \(error.localizedDescription)"
            }
        }
    }

    func beginReading() {
        guard NFCNDEFReaderSession.readingAvailable else {
            statusMessage = "NFC reading is not available on this device."
            return
        }

        didFinishCurrentScan = false
        operation = .read
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

    /// Writes the current editable payload as one application/opentag3d NDEF record.
    func beginWriting() {
        guard NFCNDEFReaderSession.readingAvailable else {
            statusMessage = "NFC writing is not available on this device."
            return
        }

        let payload: Data
        do {
            payload = try TagPayloadEditor.data(from: rawHexText)
        } catch {
            statusMessage = "Cannot write the payload: \(error.localizedDescription)"
            return
        }

        didFinishCurrentScan = false
        operation = .write(payload)
        isWriting = true
        statusMessage = "Starting the NFC writer…"

        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        session.alertMessage = "Hold your iPhone near the NFC tag you want to overwrite."
        readerSession = session
        session.begin()
    }

    /// Called by the TextEditor every time the user changes the hex dump.
    func updateRawHexText(_ newValue: String) {
        rawHexText = newValue

        do {
            let result = try refreshDecodedFieldsFromRawHex()
            statusMessage = result.warning
                ?? "Decoded \(result.payload.count) edited payload bytes."
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
    private func refreshDecodedFieldsFromRawHex() throws -> (payload: Data, warning: String?) {
        let payload = try TagPayloadEditor.data(from: rawHexText)
        let plan = try TagPayloadEditor.decodingPlan(for: payload)
        fields = try plan.parser.parse(payload).fields
        return (payload, plan.warning)
    }

    private func finishReading(payload: Data) {
        rawHexText = TagPayloadEditor.editableHex(for: payload)

        do {
            let result = try refreshDecodedFieldsFromRawHex()
            statusMessage = result.warning
                ?? "Read an OpenTag3D payload from the NFC tag (\(payload.count) bytes)."
        } catch {
            fields = []
            statusMessage = "The tag was read, but its payload could not be decoded: \(error.localizedDescription)"
        }

        isReading = false
    }

    private func openTag3DPayload(in message: NFCNDEFMessage) -> Data? {
        message.records.first { record in
            guard record.typeNameFormat == .media,
                  let recordType = String(data: record.type, encoding: .utf8) else {
                return false
            }
            return recordType.caseInsensitiveCompare(Self.openTag3DMIMEType) == .orderedSame
        }?.payload
    }

    private func fail(_ session: NFCNDEFReaderSession, message: String) {
        didFinishCurrentScan = true
        session.invalidate(errorMessage: message)
        DispatchQueue.main.async { [weak self] in
            self?.isReading = false
            self?.isWriting = false
            self?.statusMessage = message
        }
    }
}

extension NFCReaderWriterService: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.operation {
            case .read:
                self.statusMessage = "NFC reader active. Hold the top of your iPhone near the tag."
            case .write:
                self.statusMessage = "NFC writer active. Hold the top of your iPhone near the tag."
            }
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        guard case .read = operation else { return }
        guard let payload = messages.compactMap({ openTag3DPayload(in: $0) }).first else {
            fail(session, message: "The tag does not contain an OpenTag3D NDEF record.")
            return
        }

        didFinishCurrentScan = true
        session.alertMessage = "OpenTag3D tag read successfully."
        session.invalidate()

        DispatchQueue.main.async { [weak self] in
            self?.finishReading(payload: payload)
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetect tags: [NFCNDEFTag]
    ) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "More than one tag was detected. Present only one tag."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, message: "Could not connect to the NFC tag: \(error.localizedDescription)")
                return
            }

            switch self.operation {
            case .read:
                self.read(tag, in: session)
            case .write(let payload):
                self.write(payload, to: tag, in: session)
            }
        }
    }

    private func read(_ tag: NFCNDEFTag, in session: NFCNDEFReaderSession) {
        tag.readNDEF { [weak self] message, error in
            guard let self else { return }
            if let error {
                self.fail(session, message: "Could not read the NFC tag: \(error.localizedDescription)")
                return
            }
            guard let message, let payload = self.openTag3DPayload(in: message) else {
                self.fail(session, message: "The tag does not contain an OpenTag3D NDEF record.")
                return
            }

            self.didFinishCurrentScan = true
            session.alertMessage = "OpenTag3D tag read successfully."
            session.invalidate()
            DispatchQueue.main.async { [weak self] in
                self?.finishReading(payload: payload)
            }
        }
    }

    private func write(_ payload: Data, to tag: NFCNDEFTag, in session: NFCNDEFReaderSession) {
        let record = NFCNDEFPayload(
            format: .media,
            type: Data(Self.openTag3DMIMEType.utf8),
            identifier: Data(),
            payload: payload
        )
        let message = NFCNDEFMessage(records: [record])

        tag.queryNDEFStatus { [weak self] status, capacity, error in
            guard let self else { return }
            if let error {
                self.fail(session, message: "Could not inspect the NFC tag: \(error.localizedDescription)")
                return
            }

            switch status {
            case .notSupported:
                self.fail(session, message: "This NFC tag does not support NDEF data.")
            case .readOnly:
                self.fail(session, message: "This NFC tag is read-only and cannot be changed.")
            case .readWrite:
                guard message.length <= capacity else {
                    self.fail(
                        session,
                        message: "The NDEF message needs \(message.length) bytes, but this tag holds only \(capacity)."
                    )
                    return
                }

                guard tag.isAvailable else {
                    self.fail(
                        session,
                        message: "The NFC tag moved out of range. Keep the top of the iPhone against the tag until writing finishes."
                    )
                    return
                }

                session.alertMessage = "Writing \(payload.count) payload bytes. Keep the iPhone against the tag."
                tag.writeNDEF(message) { [weak self] error in
                    guard let self else { return }
                    if let error {
                        self.fail(session, message: self.writeFailureMessage(for: error))
                        return
                    }

                    self.didFinishCurrentScan = true
                    session.alertMessage = "OpenTag3D payload written successfully."
                    session.invalidate()
                    DispatchQueue.main.async { [weak self] in
                        self?.isWriting = false
                        self?.statusMessage = "Wrote \(payload.count) OpenTag3D payload bytes to the NFC tag."
                    }
                }
            @unknown default:
                self.fail(session, message: "The NFC tag reported an unknown write status.")
            }
        }
    }

    /// Converts Core NFC's terse errors (including "Stack Error") into useful guidance.
    private func writeFailureMessage(for error: Error) -> String {
        guard let readerError = error as? NFCReaderError else {
            let nsError = error as NSError
            return "The NFC tag could not be written: \(error.localizedDescription) (error \(nsError.code))."
        }

        switch readerError.code {
        case .readerTransceiveErrorTagConnectionLost,
             .readerTransceiveErrorTagNotConnected,
             .readerTransceiveErrorRetryExceeded:
            return "The NFC connection was lost while writing. Keep the top of the iPhone against the tag until the success checkmark appears."
        case .ndefReaderSessionErrorTagNotWritable:
            return "This NFC tag reports that it is not writable. It may be permanently locked or password protected."
        case .ndefReaderSessionErrorTagSizeTooSmall,
             .readerTransceiveErrorPacketTooLong:
            return "This NFC tag does not have enough writable space for the NDEF message."
        case .ndefReaderSessionErrorTagUpdateFailure,
             .readerTransceiveErrorTagResponseError:
            return "The tag rejected the NDEF update. Keep it firmly in place and try again; if it repeats, the tag may be locked or damaged. (Core NFC error \(readerError.code.rawValue))"
        default:
            return "The NFC tag could not be written: \(error.localizedDescription) (Core NFC error \(readerError.code.rawValue))."
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
            self.isWriting = false

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

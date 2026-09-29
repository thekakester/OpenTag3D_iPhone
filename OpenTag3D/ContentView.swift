//
//  ContentView.swift
//  OpenTag3D
//
//  Created by Mitch Davis (With AI Assistance) on 8/27/26.
//

import SwiftUI
import OpenTag3DKit

private enum FieldInput: Hashable {
    case human
    case numeric
    case rawHex
}

private enum EditorFocus: Hashable {
    case payload
    case field(id: String, input: FieldInput)
}

struct ContentView: View {
    @State private var isShowingDevTools = false

    var body: some View {
        Group {
            if isShowingDevTools {
                DevToolsView()
            } else {
                LandingView {
                    isShowingDevTools = true
                }
            }
        }
        .animation(.easeInOut, value: isShowingDevTools)
    }
}

private struct DevToolsView: View {
    @StateObject private var tagReader = NFCReaderWriterService()
    @State private var isShowingSerialImport = false
    @State private var isShowingQRCodeScanner = false
    @State private var serialNumber = ""
    @FocusState private var focusedEditor: EditorFocus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        readTagButton

                        Menu {
                            Button {
                                serialNumber = ""
                                isShowingSerialImport = true
                            } label: {
                                Label("by Polar Filament Serial Number", systemImage: "number")
                            }

                            Button {
                                isShowingQRCodeScanner = true
                            } label: {
                                Label("by QR Code", systemImage: "qrcode.viewfinder")
                            }
                        } label: {
                            Label(
                                tagReader.isImporting ? "Importing…" : "Import Tag",
                                systemImage: "square.and.arrow.down"
                            )
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(.blue)
                                .background(
                                    Color.white,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(tagReader.isBusy)
                    }

                    Text(tagReader.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    EditableHexSection(
                        value: Binding(
                            get: { tagReader.rawHexText },
                            set: { tagReader.updateRawHexText($0) }
                        ),
                        focusedEditor: $focusedEditor,
                        isWriting: tagReader.isWriting,
                        isScanning: tagReader.isBusy,
                        hasPayload: tagReader.hasParsedPayload
                    ) {
                        focusedEditor = nil
                        tagReader.beginWriting()
                    }

                    if tagReader.productPhotoURLs.isEmpty == false {
                        ProductPhotoStrip(urls: tagReader.productPhotoURLs)
                    }

                    ForEach(tagReader.fields) { field in
                        FieldBubble(
                            field: field,
                            focusedEditor: $focusedEditor
                        ) { id, source, text in
                            tagReader.updateField(id: id, source: source, text: text)
                        }
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedEditor != nil {
                HStack {
                    Spacer()

                    Button("Done") {
                        focusedEditor = nil
                    }
                    .font(.body.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(.bar)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
        }
        .sheet(isPresented: $isShowingSerialImport) {
            NavigationStack {
                Form {
                    Section {
                        TextField("1234-ABCD", text: $serialNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Polar Filament Serial Number")
                    } footer: {
                        Text("The imported tag will replace the current hexadecimal payload.")
                    }
                }
                .navigationTitle("Import Tag")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isShowingSerialImport = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            tagReader.importPolarFilamentTag(serialNumber: serialNumber)
                            isShowingSerialImport = false
                        }
                        .disabled(serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $isShowingQRCodeScanner) {
            QRCodeScannerView { qrCode in
                isShowingQRCodeScanner = false
                tagReader.importPolarFilamentTag(qrCode: qrCode)
            } onCancel: {
                isShowingQRCodeScanner = false
            }
        }
    }

    @ViewBuilder
    private var readTagButton: some View {
        if tagReader.hasParsedPayload {
            Button {
                tagReader.beginReading()
            } label: {
                readTagLabel
                    .padding(.vertical, 10)
                    .foregroundStyle(.blue)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(tagReader.isBusy)
        } else {
            Button {
                tagReader.beginReading()
            } label: {
                readTagLabel
            }
            .buttonStyle(.borderedProminent)
            .disabled(tagReader.isBusy)
        }
    }

    private var readTagLabel: some View {
        Label(
            tagReader.isReading ? "Reading…" : "Read Tag",
            systemImage: "wave.3.right"
        )
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }
}

private struct ProductPhotoStrip: View {
    let urls: [URL]

    private let imageSize: CGFloat = 88

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(urls, id: \.absoluteString) { url in
                    ProductPhotoThumbnail(url: url, imageSize: imageSize)
                }
            }
        }
        .frame(height: imageSize)
        .accessibilityLabel("Product photos")
    }
}

private struct ProductPhotoThumbnail: View {
    let url: URL
    let imageSize: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
                    .onAppear {
                        print("[ProductPhotos] Thumbnail request started: \(url.absoluteString)")
                    }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .onAppear {
                        print("[ProductPhotos] Thumbnail loaded: \(url.absoluteString)")
                    }
            case .failure(let error):
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
                    .onAppear {
                        print(
                            "[ProductPhotos] Thumbnail failed: \(url.absoluteString) — "
                                + error.localizedDescription
                        )
                    }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: imageSize, height: imageSize)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct EditableHexSection: View {
    @Binding var value: String
    let focusedEditor: FocusState<EditorFocus?>.Binding
    let isWriting: Bool
    let isScanning: Bool
    let hasPayload: Bool
    let onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("application/opentag3d payload")
                    .font(.subheadline.weight(.semibold))

                Button("clear") {
                    value = ""
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
                .buttonStyle(.plain)

                Spacer()
            }

            TextEditor(text: $value)
                .font(.system(size: 10, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused(focusedEditor, equals: .payload)
                .frame(height: 82)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if hasPayload {
                Button {
                    onWrite()
                } label: {
                    writeTagLabel
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            } else {
                Button {
                    onWrite()
                } label: {
                    writeTagLabel
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
            }

            Text("Editable hexadecimal payload bytes. Offsets below start at the first byte shown here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var writeTagLabel: some View {
        Label(isWriting ? "Writing…" : "Write Tag", systemImage: "wave.3.right")
            .font(.subheadline)
            .frame(maxWidth: .infinity)
    }
}

private struct FieldBubble: View {
    let field: OpenTag3DField
    let focusedEditor: FocusState<EditorFocus?>.Binding
    let onCommit: (String, OpenTag3DEditSource, String) -> Void

    @State private var humanText: String
    @State private var numericText: String
    @State private var rawHexText: String
    init(
        field: OpenTag3DField,
        focusedEditor: FocusState<EditorFocus?>.Binding,
        onCommit: @escaping (String, OpenTag3DEditSource, String) -> Void
    ) {
        self.field = field
        self.focusedEditor = focusedEditor
        self.onCommit = onCommit
        _humanText = State(initialValue: field.humanReadableText)
        _numericText = State(initialValue: field.numericText)
        _rawHexText = State(initialValue: field.rawHexText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(field.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(field.offsetDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextField("Human readable value", text: $humanText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black)
                .focused(focusedEditor, equals: focus(for: .human))
                .onSubmit { commit(.human) }
                .accessibilityLabel("\(field.name) human readable value")
                .humanFieldStyle()

            HStack(spacing: 8) {
                if field.numericText != "—" {
                    TextField("Numeric", text: $numericText)
                        .frame(width: 105)
                        .focused(focusedEditor, equals: focus(for: .numeric))
                        .onSubmit { commit(.numeric) }
                        .accessibilityLabel("\(field.name) numeric value")
                        .rawFieldStyle(isFocused: isFocused(.numeric))
                }

                TextField("Raw hex", text: $rawHexText)
                    .fontDesign(.monospaced)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused(focusedEditor, equals: focus(for: .rawHex))
                    .onSubmit { commit(.rawHex) }
                    .accessibilityLabel("\(field.name) raw hexadecimal value")
                    .rawFieldStyle(isFocused: isFocused(.rawHex))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: focusedEditor.wrappedValue) { oldValue, newValue in
            if case .field(let id, let input) = oldValue,
               id == field.id,
               oldValue != newValue {
                commit(input)
            }
        }
        .onChange(of: field.humanReadableText) { _, newValue in
            humanText = newValue
        }
        .onChange(of: field.numericText) { _, newValue in
            numericText = newValue
        }
        .onChange(of: field.rawHexText) { _, newValue in
            rawHexText = newValue
        }
    }

    private func focus(for input: FieldInput) -> EditorFocus {
        .field(id: field.id, input: input)
    }

    private func isFocused(_ input: FieldInput) -> Bool {
        focusedEditor.wrappedValue == focus(for: input)
    }

    private func commit(_ input: FieldInput) {
        switch input {
        case .human:
            onCommit(field.id, .humanReadable, humanText)
        case .numeric:
            onCommit(field.id, .numeric, numericText)
        case .rawHex:
            onCommit(field.id, .rawHex, rawHexText)
        }
    }
}

private extension View {
    func humanFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 5))
    }

    func rawFieldStyle(isFocused: Bool) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        Color.secondary.opacity(isFocused ? 0.20 : 0.50),
                        lineWidth: 1
                    )
            }
    }
}

#Preview {
    ContentView()
}

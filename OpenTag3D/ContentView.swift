//
//  ContentView.swift
//  OpenTag3D
//
//  Created by Mitch Davis on 8/27/26.
//

import SwiftUI

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
    @StateObject private var tagReader = DummyTagReaderService()
    @FocusState private var focusedEditor: EditorFocus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 8) {
                        Button {
                            tagReader.beginReading()
                        } label: {
                            Label(
                                tagReader.isReading ? "Reading…" : "Read Tag",
                                systemImage: "wave.3.right"
                            )
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tagReader.isReading)

                        Link(destination: URL(string: "https://pfil.us/rfid")!) {
                            Text("or Look Up RFID data for any Polar Filament spool")
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
                    }

                    Text(tagReader.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    EditableHexSection(
                        value: Binding(
                            get: { tagReader.rawHexText },
                            set: { tagReader.updateRawHexText($0) }
                        ),
                        focusedEditor: $focusedEditor
                    )

                    if !tagReader.coreFields.isEmpty {
                        FieldSection(
                            title: "CORE",
                            fields: tagReader.coreFields,
                            focusedEditor: $focusedEditor
                        ) { id, source, text in
                            tagReader.updateField(id: id, source: source, text: text)
                        }
                    }

                    if !tagReader.extendedFields.isEmpty {
                        FieldSection(
                            title: "EXTENDED",
                            fields: tagReader.extendedFields,
                            focusedEditor: $focusedEditor
                        ) { id, source, text in
                            tagReader.updateField(id: id, source: source, text: text)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("OpenTag3D")
            .navigationBarTitleDisplayMode(.inline)
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
    }
}

private struct EditableHexSection: View {
    @Binding var value: String
    let focusedEditor: FocusState<EditorFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("application/opentag3d payload")
                .font(.subheadline.weight(.semibold))

            TextEditor(text: $value)
                .font(.system(size: 10, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused(focusedEditor, equals: .payload)
                .frame(height: 82)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Button {
                // Placeholder until NFC writing is enabled for the developer account.
            } label: {
                Label("Write Tag", systemImage: "wave.3.right")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)

            Text("Editable hexadecimal payload bytes. Offsets below start at the first byte shown here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldSection: View {
    let title: String
    let fields: [OpenTag3DFieldValue]
    let focusedEditor: FocusState<EditorFocus?>.Binding
    let onCommit: (String, OpenTag3DEditSource, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.bold())

            ForEach(fields) { field in
                FieldBubble(
                    field: field,
                    focusedEditor: focusedEditor,
                    onCommit: onCommit
                )
            }
        }
    }
}

private struct FieldBubble: View {
    let field: OpenTag3DFieldValue
    let focusedEditor: FocusState<EditorFocus?>.Binding
    let onCommit: (String, OpenTag3DEditSource, String) -> Void

    @State private var humanText: String
    @State private var numericText: String
    @State private var rawHexText: String
    init(
        field: OpenTag3DFieldValue,
        focusedEditor: FocusState<EditorFocus?>.Binding,
        onCommit: @escaping (String, OpenTag3DEditSource, String) -> Void
    ) {
        self.field = field
        self.focusedEditor = focusedEditor
        self.onCommit = onCommit
        _humanText = State(initialValue: field.humanReadableValue)
        _numericText = State(initialValue: field.numericValue)
        _rawHexText = State(initialValue: field.rawHex)
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
                if field.numericValue != "—" {
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
        .onChange(of: field.humanReadableValue) { _, newValue in
            humanText = newValue
        }
        .onChange(of: field.numericValue) { _, newValue in
            numericText = newValue
        }
        .onChange(of: field.rawHex) { _, newValue in
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

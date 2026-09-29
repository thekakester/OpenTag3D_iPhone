//
//  ContentView.swift
//  OpenTag3D
//
//  Created by Mitch Davis (With AI Assistance) on 8/27/26.
//

import Foundation
import SwiftUI
import UIKit
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

private enum PayloadDisplayMode: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case developer = "Developer"

    var id: Self { self }
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
    @State private var payloadDisplayMode: PayloadDisplayMode = .summary
    @FocusState private var focusedEditor: EditorFocus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeometryReader { geometry in
                        let spacing: CGFloat = 8
                        let availableWidth = geometry.size.width - spacing

                        HStack(spacing: spacing) {
                            readTagButton
                                .frame(width: availableWidth * 2 / 3)

                            importTagMenu
                                .frame(width: availableWidth / 3)
                        }
                    }
                    .frame(height: topButtonHeight)

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

                    ProductSummaryView(fields: tagReader.fields)

                    if tagReader.productPhotoURLs.isEmpty == false {
                        ProductPhotoStrip(urls: tagReader.productPhotoURLs)
                    }

                    if tagReader.fields.isEmpty == false {
                        Picker("Payload display", selection: $payloadDisplayMode) {
                            ForEach(PayloadDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: payloadDisplayMode) { _, _ in
                            focusedEditor = nil
                            DispatchQueue.main.async {
                                tagReader.rebuildFieldsFromPayload()
                            }
                        }
                    }

                    if payloadDisplayMode == .summary {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(tagReader.fields) { field in
                                SummaryFieldRow(
                                    field: field,
                                    focusedEditor: $focusedEditor
                                ) { id, text in
                                    tagReader.updateField(
                                        id: id,
                                        source: .humanReadable,
                                        text: text
                                    )
                                }
                            }
                        }
                    } else {
                        ForEach(tagReader.fields) { field in
                            FieldBubble(
                                field: field,
                                focusedEditor: $focusedEditor
                            ) { id, source, text in
                                tagReader.updateField(id: id, source: source, text: text)
                            }
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
        Button {
            tagReader.beginReading()
        } label: {
            readTagLabel
                .foregroundStyle(tagReader.hasParsedPayload ? Color.blue : Color.white)
                .frame(maxHeight: .infinity)
                .background(
                    tagReader.hasParsedPayload ? Color.white : Color.blue,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    if tagReader.hasParsedPayload {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(tagReader.isBusy)
        .opacity(tagReader.isBusy ? 0.5 : 1)
    }

    private var readTagLabel: some View {
        Label(
            tagReader.isReading ? "Reading…" : "Read Tag",
            systemImage: "wave.3.right"
        )
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private var importTagMenu: some View {
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .opacity(tagReader.isBusy ? 0.5 : 1)
    }

    private var topButtonHeight: CGFloat {
        tagReader.hasParsedPayload ? 36 : 90
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

private struct ProductSummaryView: View {
    let fields: [OpenTag3DField]

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                if let manufacturer {
                    Text(manufacturer)
                        .font(.title3.weight(.semibold))
                }

                if colorName != nil || materialDescription != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let colorName {
                            if let primaryColor {
                                Text(colorName)
                                    .font(.headline)
                                    .foregroundStyle(primaryColor.foregroundColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        primaryColor.backgroundColor,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            } else {
                                Text(colorName)
                                    .font(.headline)
                            }
                        }

                        if let materialDescription {
                            Text(materialDescription)
                                .font(.headline)
                        }
                    }
                }

                if diameterDescription != nil || weightDescription != nil {
                    Text([diameterDescription, weightDescription].compactMap { $0 }.joined(separator: " "))
                        .font(.subheadline)
                }

                if let serialNumber {
                    Text("#\(serialNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasContent: Bool {
        manufacturer != nil
            || colorName != nil
            || materialDescription != nil
            || diameterDescription != nil
            || weightDescription != nil
            || serialNumber != nil
    }

    private var manufacturer: String? {
        textValue(for: "manufacturer")
    }

    private var colorName: String? {
        textValue(for: "color_name")
    }

    private var materialDescription: String? {
        [textValue(for: "material"), textValue(for: "material_mod")]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private var diameterDescription: String? {
        guard let field = field(withID: "diameter") else {
            return nil
        }

        switch field.value {
        case .number(let diameter):
            return "\(decimalString(diameter))mm"
        case .integer(let diameter):
            return "\(diameter)mm"
        default:
            return nil
        }
    }

    private var weightDescription: String? {
        guard let field = field(withID: "weight"),
              case .integer(let grams) = field.value else {
            return nil
        }

        if grams >= 1_000 {
            let kilograms = NSDecimalNumber(value: grams)
                .dividing(by: NSDecimalNumber(value: 1_000))
            return "\(kilograms.stringValue)kg"
        }

        return "\(grams)g"
    }

    private var serialNumber: String? {
        textValue(for: "serial")
    }

    private var primaryColor: ProductSummaryColor? {
        guard let field = field(withID: "color_1"),
              case .color(let red, let green, let blue, let alpha) = field.value else {
            return nil
        }

        let backgroundColor = Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: alpha == 0 ? 0 : 1
        )
        let foregroundColor: Color = alpha == 0
            ? .primary
            : (isDarkColor(hex: field.hex) ? .white : .black)

        return ProductSummaryColor(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor
        )
    }

    private func field(withID id: String) -> OpenTag3DField? {
        fields.first { $0.id == id }
    }

    private func textValue(for id: String) -> String? {
        guard let field = field(withID: id),
              case .text(let value) = field.value else {
            return nil
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

private struct ProductSummaryColor {
    let backgroundColor: Color
    let foregroundColor: Color
}

private func isDarkColor(hex: String) -> Bool {
    let normalizedHex = hex
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

    guard normalizedHex.count >= 6 else {
        return false
    }

    let redHex = String(normalizedHex.prefix(2))
    let greenHex = String(normalizedHex.dropFirst(2).prefix(2))
    let blueHex = String(normalizedHex.dropFirst(4).prefix(2))
    guard let red = UInt8(redHex, radix: 16),
          let green = UInt8(greenHex, radix: 16),
          let blue = UInt8(blueHex, radix: 16) else {
        return false
    }

    func linearized(_ component: UInt8) -> Double {
        let value = Double(component) / 255
        return value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    let luminance = 0.2126 * linearized(red)
        + 0.7152 * linearized(green)
        + 0.0722 * linearized(blue)
    let whiteContrast = 1.05 / (luminance + 0.05)
    let blackContrast = (luminance + 0.05) / 0.05
    return whiteContrast > blackContrast
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

private struct SummaryFieldRow: View {
    let field: OpenTag3DField
    let focusedEditor: FocusState<EditorFocus?>.Binding
    let onCommit: (String, String) -> Void

    @State private var humanText: String

    init(
        field: OpenTag3DField,
        focusedEditor: FocusState<EditorFocus?>.Binding,
        onCommit: @escaping (String, String) -> Void
    ) {
        self.field = field
        self.focusedEditor = focusedEditor
        self.onCommit = onCommit
        _humanText = State(initialValue: field.humanReadableText)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(field.name)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if field.type == .rgba {
                    ColorFieldPicker(field: field) { hex in
                        onCommit(field.id, hex)
                    }
                } else {
                    FieldColorSwatch(field: field)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextField("Human readable value", text: $humanText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                    .focused(focusedEditor, equals: .field(id: field.id, input: .human))
                    .onSubmit { commit() }
                    .accessibilityLabel("\(field.name) human readable value")
                    .humanFieldStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: focusedEditor.wrappedValue) { oldValue, newValue in
            if oldValue == .field(id: field.id, input: .human), oldValue != newValue {
                commit()
            }
        }
        .onChange(of: field.humanReadableText) { _, newValue in
            humanText = newValue
        }
    }

    private func commit() {
        onCommit(field.id, humanText)
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

            HStack(spacing: 6) {
                if field.type == .rgba {
                    ColorFieldPicker(field: field) { hex in
                        onCommit(field.id, .humanReadable, hex)
                    }
                }

                TextField("Human readable value", text: $humanText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                    .focused(focusedEditor, equals: focus(for: .human))
                    .onSubmit { commit(.human) }
                    .accessibilityLabel("\(field.name) human readable value")
                    .humanFieldStyle()
            }

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

private struct FieldColorSwatch: View {
    let field: OpenTag3DField

    private let size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(displayColor)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            }
    }

    private var displayColor: Color {
        guard case .color(let red, let green, let blue, let alpha) = field.value else {
            return .clear
        }

        return Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

private struct ColorFieldPicker: View {
    let field: OpenTag3DField
    let onSelection: (String) -> Void

    @State private var selectedColor: UIColor
    @State private var isPresentingPicker = false

    init(field: OpenTag3DField, onSelection: @escaping (String) -> Void) {
        self.field = field
        self.onSelection = onSelection
        _selectedColor = State(initialValue: Self.uiColor(for: field))
    }

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            FieldColorSwatch(field: field)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(field.name)")
        .sheet(isPresented: $isPresentingPicker) {
            SystemColorPicker(
                selectedColor: $selectedColor,
                isPresented: $isPresentingPicker
            ) { color in
                guard let hex = Self.rgbaHex(for: color) else { return }
                onSelection(hex)
            }
        }
        .onChange(of: field.hex) { _, _ in
            selectedColor = Self.uiColor(for: field)
        }
    }

    private static func uiColor(for field: OpenTag3DField) -> UIColor {
        guard case .color(let red, let green, let blue, let alpha) = field.value else {
            return .clear
        }

        return UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    private static func rgbaHex(for color: UIColor) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        func byte(_ component: CGFloat) -> UInt8 {
            UInt8((min(max(component, 0), 1) * 255).rounded())
        }

        return String(
            format: "%02X%02X%02X%02X",
            byte(red),
            byte(green),
            byte(blue),
            byte(alpha)
        )
    }
}

private struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var selectedColor: UIColor
    @Binding var isPresented: Bool
    let onSelection: (UIColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedColor: $selectedColor,
            isPresented: $isPresented,
            onSelection: onSelection
        )
    }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.selectedColor = selectedColor
        picker.supportsAlpha = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ picker: UIColorPickerViewController,
        context: Context
    ) {
        if picker.selectedColor != selectedColor {
            picker.selectedColor = selectedColor
        }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        private var selectedColor: Binding<UIColor>
        private var isPresented: Binding<Bool>
        private let onSelection: (UIColor) -> Void

        init(
            selectedColor: Binding<UIColor>,
            isPresented: Binding<Bool>,
            onSelection: @escaping (UIColor) -> Void
        ) {
            self.selectedColor = selectedColor
            self.isPresented = isPresented
            self.onSelection = onSelection
        }

        func colorPickerViewControllerDidSelectColor(
            _ viewController: UIColorPickerViewController
        ) {
            selectedColor.wrappedValue = viewController.selectedColor
            onSelection(viewController.selectedColor)
        }

        func colorPickerViewControllerDidFinish(
            _ viewController: UIColorPickerViewController
        ) {
            isPresented.wrappedValue = false
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

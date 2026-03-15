import SwiftUI

private struct FontOption: Identifiable {
    let id: String  // fontName
    let label: String
    var name: String { id }
}

private struct ColorOption: Identifiable {
    let id: String  // label
    let value: CaptionColor
    var label: String { id }
}

struct CaptionStylePickerView: View {
    @Binding var style: CaptionStyle
    @Environment(\.dismiss) private var dismiss

    private let fonts: [FontOption] = [
        FontOption(id: "Helvetica-Bold", label: "SF Pro"),
        FontOption(id: "Georgia-Bold", label: "Serif"),
        FontOption(id: "Courier-Bold", label: "Mono"),
        FontOption(id: "Impact", label: "Heavy"),
    ]

    private let colors: [ColorOption] = [
        ColorOption(id: "White", value: .white),
        ColorOption(id: "Black", value: .black),
        ColorOption(id: "Yellow", value: .yellow),
        ColorOption(id: "Cyan", value: .cyan),
    ]

    var body: some View {
        NavigationStack {
            Form {
                fontSection
                sizeSection
                colorSection
                contrastSection
                previewSection
            }
            .navigationTitle("Caption Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Font Family

    @ViewBuilder
    private var fontSection: some View {
        Section("Font") {
            ForEach(Array(fonts), id: \.id) { font in
                fontRow(font)
            }
        }
    }

    // MARK: - Font Size

    @ViewBuilder
    private var sizeSection: some View {
        Section("Size") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(style.fontSize))pt")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(value: $style.fontSize, in: 28...72, step: 2)
            }
        }
    }

    // MARK: - Text Color

    @ViewBuilder
    private var colorSection: some View {
        Section("Color") {
            HStack(spacing: 16) {
                ForEach(Array(colors), id: \.id) { color in
                    Button {
                        style.textColor = color.value
                    } label: {
                        Circle()
                            .fill(Color(
                                red: color.value.red,
                                green: color.value.green,
                                blue: color.value.blue
                            ))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color(UIColor.systemGray3), lineWidth: 1)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 3)
                                    .opacity(style.textColor == color.value ? 1 : 0)
                            )
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Contrast Mode

    @ViewBuilder
    private var contrastSection: some View {
        Section("Contrast") {
            ForEach(Array(ContrastMode.allCases), id: \.self) { mode in
                contrastRow(mode)
            }
        }
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func fontRow(_ font: FontOption) -> some View {
        Button {
            style.fontName = font.name
        } label: {
            HStack {
                Text(font.label)
                    .font(.custom(font.name, size: 17))
                    .foregroundStyle(.primary)
                Spacer()
                if style.fontName == font.name {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func contrastRow(_ mode: ContrastMode) -> some View {
        Button {
            style.contrastMode = mode
        } label: {
            HStack {
                Text(mode.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if style.contrastMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            ZStack {
                LinearGradient(
                    colors: [.blue, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                captionPreviewText
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    @ViewBuilder
    private var captionPreviewText: some View {
        let font = Font.custom(style.fontName, size: style.fontSize * 0.5)
        let color = Color(
            red: style.textColor.red,
            green: style.textColor.green,
            blue: style.textColor.blue
        )

        switch style.contrastMode {
        case .none:
            Text("Sample Caption")
                .font(font)
                .foregroundStyle(color)

        case .shadow:
            Text("Sample Caption")
                .font(font)
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.8), radius: 4, x: 2, y: 2)

        case .stroke:
            ZStack {
                Text("Sample Caption")
                    .font(font)
                    .foregroundStyle(.black)
                    .blur(radius: 0.8)
                Text("Sample Caption")
                    .font(font)
                    .foregroundStyle(color)
            }

        case .highlight:
            Text("Sample Caption")
                .font(font)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color.black.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
    }
}

// MARK: - ContrastMode Display Name

extension ContrastMode {
    var displayName: String {
        switch self {
        case .none: "None"
        case .stroke: "Stroke (outline)"
        case .highlight: "Highlight (background)"
        case .shadow: "Shadow"
        }
    }
}

import AVKit
import SwiftUI

/// Full-screen editor for a single TimelineSegment with live composite preview
/// and per-layer controls.
struct SegmentEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let segmentIndex: Int

    @State private var vm: SegmentEditViewModel
    @State private var showLayerPanel = true

    init(project: Project, segmentIndex: Int) {
        self.project = project
        self.segmentIndex = segmentIndex
        let timeline = project.timeline ?? ProjectTimeline()
        let segment = segmentIndex < timeline.segments.count
            ? timeline.segments[segmentIndex]
            : TimelineSegment(scriptText: "")
        _vm = State(initialValue: SegmentEditViewModel(segment: segment, segmentIndex: segmentIndex))
    }

    var body: some View {
        VStack(spacing: 0) {
            compositePreview
            transportControls
            Divider()
            if showLayerPanel {
                layerPanel
            }
        }
        .navigationTitle("Edit Segment \(segmentIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLayerPanel.toggle()
                } label: {
                    Image(systemName: showLayerPanel ? "sidebar.trailing" : "sidebar.leading")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .sheet(item: trimSheetBinding) { layerID in
            layerTrimSheet(layerID: layerID)
        }
        .onDisappear { vm.teardown() }
    }

    // MARK: - Composite Preview

    @ViewBuilder
    private var compositePreview: some View {
        GeometryReader { geo in
            ZStack {
                // Live composited video
                VideoPlayer(player: vm.player)
                    .allowsHitTesting(false)

                // Thirds grid overlay
                if vm.showGrid {
                    thirdsGrid
                        .allowsHitTesting(false)
                }

                // Selection handles for the selected layer
                if let layerID = vm.selectedLayerID,
                   let layer = vm.segment.layers.first(where: { $0.id == layerID }) {
                    SelectionOverlay(
                        position: layer.position,
                        canvasSize: geo.size,
                        onPositionChange: { vm.updateLayerPosition(layerID: layerID, position: $0) }
                    )
                }

                if let textLayerID = vm.selectedTextLayerID,
                   let textLayer = vm.segment.textLayers.first(where: { $0.id == textLayerID }) {
                    SelectionOverlay(
                        position: textLayer.layer.position,
                        canvasSize: geo.size,
                        onPositionChange: { vm.updateTextLayerPosition(textLayerID: textLayerID, position: $0) }
                    )
                }
            }
        }
        .frame(maxHeight: showLayerPanel ? 280 : .infinity)
        .background(Color.black)
        .onTapGesture { vm.clearSelection() }
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private var transportControls: some View {
        HStack(spacing: 12) {
            Button { vm.togglePlayback() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Text(formatTime(vm.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            scrubBar
                .frame(maxWidth: .infinity)

            Text(formatTime(vm.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                vm.showGrid.toggle()
            } label: {
                Image(systemName: vm.showGrid ? "grid" : "grid.circle")
                    .foregroundStyle(vm.showGrid ? .blue : .secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var scrubBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.systemGray4))
                    .frame(height: 4)

                if vm.duration > 0 {
                    let frac = vm.currentTime / vm.duration
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: max(0, geo.size.width * frac), height: 4)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard vm.duration > 0 else { return }
                        let frac = max(0, min(1, value.location.x / geo.size.width))
                        vm.seek(to: frac * vm.duration)
                    }
            )
        }
        .frame(height: 28)
    }

    // MARK: - Layer Panel

    @ViewBuilder
    private var layerPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Media layers
                Section {
                    ForEach(vm.segment.layers, id: \.id) { layer in
                        LayerRowView(
                            layer: layer,
                            isSelected: vm.selectedLayerID == layer.id,
                            onSelect: { vm.selectLayer(layer.id) },
                            onToggleBgRemoval: { vm.toggleBackgroundRemoval(layerID: layer.id) },
                            onFilterChange: { vm.setFilter(layerID: layer.id, filter: $0) },
                            onVolumeChange: { vm.setVolume(layerID: layer.id, volume: $0) },
                            onTrimTap: { vm.trimLayerID = layer.id },
                            onBorderChange: { vm.setBorderWidth(layerID: layer.id, width: $0) },
                            onCornerRadiusChange: { vm.setCornerRadius(layerID: layer.id, radius: $0) }
                        )
                    }
                    .onMove { vm.moveLayer(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Layers")
                            .font(.headline)
                        Spacer()
                        EditButton()
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }

                // Text layers
                Section {
                    ForEach(vm.segment.textLayers, id: \.id) { textLayer in
                        TextLayerRowView(
                            textLayer: textLayer,
                            isSelected: vm.selectedTextLayerID == textLayer.id,
                            onSelect: { vm.selectTextLayer(textLayer.id) },
                            onTextChange: { vm.setTextLayerText(id: textLayer.id, text: $0) },
                            onFontSizeChange: { vm.setTextLayerFontSize(id: textLayer.id, size: $0) },
                            onColorChange: { vm.setTextLayerColor(id: textLayer.id, color: $0) },
                            onContrastChange: { vm.setTextLayerContrastMode(id: textLayer.id, mode: $0) },
                            onFontChange: { vm.setTextLayerFontName(id: textLayer.id, fontName: $0) },
                            onDelete: { vm.deleteTextLayer(id: textLayer.id) }
                        )
                    }
                    .onMove { vm.moveTextLayer(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Text Layers")
                            .font(.headline)
                        Spacer()
                        Button { vm.addTextLayer() } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Trim Sheet

    private var trimSheetBinding: Binding<UUID?> {
        Binding(
            get: { vm.trimLayerID },
            set: { vm.trimLayerID = $0 }
        )
    }

    @ViewBuilder
    private func layerTrimSheet(layerID: UUID) -> some View {
        if let layer = vm.segment.layers.first(where: { $0.id == layerID }) {
            NavigationStack {
                LayerTrimView(
                    layer: layer,
                    segmentDuration: vm.duration,
                    onSave: { start, end in
                        vm.setLayerTrim(layerID: layerID, start: start, end: end)
                        vm.trimLayerID = nil
                    }
                )
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Thirds Grid

    @ViewBuilder
    private var thirdsGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { context, _ in
                let color = Color.white.opacity(0.3)
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) },
                        with: .color(color), lineWidth: 0.5
                    )
                    let y = h * CGFloat(i) / 3
                    context.stroke(
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) },
                        with: .color(color), lineWidth: 0.5
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func save() {
        var updated = project
        guard var timeline = updated.timeline else { dismiss(); return }
        guard segmentIndex < timeline.segments.count else { dismiss(); return }
        timeline.segments[segmentIndex] = vm.segment
        updated.timeline = timeline
        appState.updateProject(updated)
        dismiss()
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Selection Overlay

/// Draws selection handles around a layer and supports drag to reposition.
private struct SelectionOverlay: View {
    let position: NormalizedRect
    let canvasSize: CGSize
    let onPositionChange: (NormalizedRect) -> Void

    @GestureState private var dragOffset: CGSize = .zero

    private var frame: CGRect {
        CGRect(
            x: position.x * canvasSize.width + dragOffset.width,
            y: position.y * canvasSize.height + dragOffset.height,
            width: position.width * canvasSize.width,
            height: position.height * canvasSize.height
        )
    }

    var body: some View {
        Rectangle()
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .topLeading) { handle }
            .overlay(alignment: .topTrailing) { handle }
            .overlay(alignment: .bottomLeading) { handle }
            .overlay(alignment: .bottomTrailing) { handle }
            .position(x: frame.midX, y: frame.midY)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                        let dx = value.translation.width / canvasSize.width
                        let dy = value.translation.height / canvasSize.height
                        onPositionChange(NormalizedRect(
                            x: max(0, min(1 - position.width, position.x + dx)),
                            y: max(0, min(1 - position.height, position.y + dy)),
                            width: position.width,
                            height: position.height
                        ))
                    }
            )
    }

    private var handle: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Layer Row

private struct LayerRowView: View {
    let layer: Layer
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleBgRemoval: () -> Void
    let onFilterChange: (FilterPreset) -> Void
    let onVolumeChange: (Double) -> Void
    let onTrimTap: () -> Void
    let onBorderChange: (Double) -> Void
    let onCornerRadiusChange: (Double) -> Void

    @State private var expanded = false

    private var iconName: String {
        switch layer.type {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .text: return "textformat"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(layerColor)
                Text(layer.type.rawValue.capitalized)
                    .font(.subheadline.bold())

                if layer.hasBackgroundRemoval {
                    Image(systemName: "person.crop.rectangle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if layer.filter != .none {
                    Text(layer.filter.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(3)
                }

                Spacer()

                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            // Expanded controls
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Background removal (video only)
                    if layer.type == .video {
                        Toggle("Background Removal", isOn: Binding(
                            get: { layer.hasBackgroundRemoval },
                            set: { _ in onToggleBgRemoval() }
                        ))
                        .font(.caption)
                    }

                    // Filter picker
                    HStack {
                        Text("Filter")
                            .font(.caption)
                        Spacer()
                        Picker("Filter", selection: Binding(
                            get: { layer.filter },
                            set: { onFilterChange($0) }
                        )) {
                            ForEach([FilterPreset.none, .vivid, .matte, .noir, .fade], id: \.self) { preset in
                                Text(preset.rawValue.capitalized).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }

                    // Volume (video/audio)
                    if layer.type == .video {
                        HStack {
                            Image(systemName: layer.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                                .font(.caption)
                            Slider(value: Binding(
                                get: { layer.volume },
                                set: { onVolumeChange($0) }
                            ), in: 0...1)
                            Text("\(Int(layer.volume * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 36)
                        }

                        // Trim button
                        Button { onTrimTap() } label: {
                            Label("Trim", systemImage: "scissors")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Border & corner radius
                    HStack {
                        Text("Border")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { layer.borderWidth },
                            set: { onBorderChange($0) }
                        ), in: 0...10)
                        Text("\(Int(layer.borderWidth))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 24)
                    }

                    HStack {
                        Text("Radius")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { layer.cornerRadius },
                            set: { onCornerRadiusChange($0) }
                        ), in: 0...50)
                        Text("\(Int(layer.cornerRadius))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 24)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : .clear, lineWidth: 1.5)
        )
        .padding(.horizontal)
    }

    private var layerColor: Color {
        switch layer.type {
        case .video: return .blue
        case .photo: return .green
        case .text: return .yellow
        }
    }
}

// MARK: - Text Layer Row

private struct TextLayerRowView: View {
    let textLayer: TextLayer
    let isSelected: Bool
    let onSelect: () -> Void
    let onTextChange: (String) -> Void
    let onFontSizeChange: (Double) -> Void
    let onColorChange: (CaptionColor) -> Void
    let onContrastChange: (ContrastMode) -> Void
    let onFontChange: (String) -> Void
    let onDelete: () -> Void

    @State private var expanded = false
    @State private var editText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "textformat")
                    .foregroundStyle(.yellow)
                Text(textLayer.text)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                Spacer()

                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Text editing
                    TextField("Text", text: Binding(
                        get: { textLayer.text },
                        set: { onTextChange($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                    // Font size
                    HStack {
                        Text("Size")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { textLayer.style.fontSize },
                            set: { onFontSizeChange($0) }
                        ), in: 12...120)
                        Text("\(Int(textLayer.style.fontSize))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 30)
                    }

                    // Font picker (common fonts)
                    HStack {
                        Text("Font")
                            .font(.caption)
                        Spacer()
                        Picker("Font", selection: Binding(
                            get: { textLayer.style.fontName },
                            set: { onFontChange($0) }
                        )) {
                            Text("Helvetica Bold").tag("Helvetica-Bold")
                            Text("Arial").tag("Arial")
                            Text("Courier").tag("Courier")
                            Text("Georgia").tag("Georgia")
                            Text("Avenir Next Bold").tag("AvenirNext-Bold")
                        }
                        .pickerStyle(.menu)
                    }

                    // Color presets
                    HStack {
                        Text("Color")
                            .font(.caption)
                        Spacer()
                        ForEach(colorPresets, id: \.name) { preset in
                            Circle()
                                .fill(Color(
                                    red: preset.color.red,
                                    green: preset.color.green,
                                    blue: preset.color.blue
                                ))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(textLayer.style.textColor == preset.color ? Color.blue : .clear, lineWidth: 2)
                                )
                                .onTapGesture { onColorChange(preset.color) }
                        }
                    }

                    // Contrast mode
                    HStack {
                        Text("Style")
                            .font(.caption)
                        Spacer()
                        Picker("Contrast", selection: Binding(
                            get: { textLayer.style.contrastMode },
                            set: { onContrastChange($0) }
                        )) {
                            Text("None").tag(ContrastMode.none)
                            Text("Stroke").tag(ContrastMode.stroke)
                            Text("Shadow").tag(ContrastMode.shadow)
                            Text("Highlight").tag(ContrastMode.highlight)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                    }

                    // Delete
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Text Layer", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.yellow.opacity(0.08) : Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.yellow : .clear, lineWidth: 1.5)
        )
        .padding(.horizontal)
    }

    private var colorPresets: [(name: String, color: CaptionColor)] {
        [
            ("White", .white),
            ("Black", .black),
            ("Yellow", .yellow),
            ("Red", CaptionColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)),
            ("Blue", CaptionColor(red: 0.2, green: 0.4, blue: 1, alpha: 1)),
        ]
    }
}

// MARK: - Layer Trim View

/// Inline trim editor reusing TrimTimelineView for a layer's enter/exit marks.
private struct LayerTrimView: View {
    let layer: Layer
    let segmentDuration: Double
    let onSave: (Double?, Double?) -> Void

    @State private var trimStart: Double?
    @State private var trimEnd: Double?
    @Environment(\.dismiss) private var dismiss

    init(layer: Layer, segmentDuration: Double, onSave: @escaping (Double?, Double?) -> Void) {
        self.layer = layer
        self.segmentDuration = segmentDuration
        self.onSave = onSave
        _trimStart = State(initialValue: layer.trimStartSeconds)
        _trimEnd = State(initialValue: layer.trimEndSeconds)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Trim Layer")
                .font(.headline)

            TrimTimelineView(
                duration: segmentDuration,
                currentTime: 0,
                trimStart: trimStart,
                trimEnd: trimEnd,
                onSeek: { _ in },
                onTrimStartChange: { trimStart = $0 },
                onTrimEndChange: { trimEnd = $0 }
            )
            .frame(height: 56)
            .padding(.horizontal)

            HStack {
                Text("In: \(formatTime(trimStart ?? 0))")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("Out: \(formatTime(trimEnd ?? segmentDuration))")
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal)

            HStack {
                Button("Clear") {
                    trimStart = nil
                    trimEnd = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply") {
                    onSave(trimStart, trimEnd)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ds)
    }
}

// MARK: - UUID Identifiable for sheet

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

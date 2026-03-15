import Photos
import SwiftUI

struct SectionManagerView: View {
    @Environment(AppState.self) private var appState
    var project: Project

    @State private var showMediaPicker = false
    @State private var navigateToTimeline = false

    var currentProject: Project {
        appState.projects.first(where: { $0.id == project.id }) ?? project
    }

    var body: some View {
        List {
            if currentProject.timeline != nil {
                Section {
                    Button {
                        navigateToTimeline = true
                    } label: {
                        Label("Open Timeline", systemImage: "timeline.selection")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("openTimelineButton")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            scriptSection
            mediaSection
        }
        .navigationTitle(currentProject.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToTimeline) {
            ProjectTimelineView(project: currentProject)
        }
        .sheet(isPresented: $showMediaPicker) {
            ProjectMediaPickerView { identifiers in
                addMedia(identifiers)
            }
        }
    }

    @ViewBuilder
    private var scriptSection: some View {
        if let script = currentProject.script, !script.sections.isEmpty {
            Section("Script") {
                ForEach(script.sections) { section in
                    SectionRowView(section: section, project: currentProject)
                }
            }
        } else {
            Section("Script") {
                NavigationLink {
                    ScriptWorkshopView(project: currentProject)
                } label: {
                    Label("Refine Script", systemImage: "doc.text")
                }
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        Section {
            Text("Shared assets available across all sections")
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)

            if currentProject.linkedMediaIDs.isEmpty {
                Button {
                    showMediaPicker = true
                } label: {
                    Label("Add Project Media", systemImage: "photo.on.rectangle.angled")
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 80), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(currentProject.linkedMediaIDs, id: \.self) { assetID in
                        MediaThumbnailView(assetID: assetID)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeMedia(assetID)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Project Media")
                Spacer()
                Button {
                    showMediaPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .font(.body)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .textCase(nil)
        }
    }

    private func addMedia(_ identifiers: [String]) {
        var updated = currentProject
        let newIDs = identifiers.filter { !updated.linkedMediaIDs.contains($0) }
        updated.linkedMediaIDs.append(contentsOf: newIDs)
        appState.updateProject(updated)
    }

    private func removeMedia(_ assetID: String) {
        var updated = currentProject
        updated.linkedMediaIDs.removeAll { $0 == assetID }
        appState.updateProject(updated)
    }
}

// MARK: - Thumbnail

private struct MediaThumbnailView: View {
    let assetID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.3)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .clipped()
        .onAppear { fetchThumbnail() }
    }

    private func fetchThumbnail() {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            DispatchQueue.main.async { image = img }
        }
    }
}

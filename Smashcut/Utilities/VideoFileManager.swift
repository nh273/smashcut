import Foundation

struct VideoFileManager {
    static func rawVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("raw.mp4")
    }

    static func maskedVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("masked.mp4")
    }

    static func compositeVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("composite.mp4")
    }

    static func exportedVideoURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("exported.mp4")
    }

    static func backgroundMediaURL(projectID: UUID, sectionID: UUID, ext: String) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("background.\(ext)")
    }

    /// URL for a media bin file (video or photo) within a section.
    static func mediaURL(projectID: UUID, sectionID: UUID, mediaID: UUID) -> URL {
        let dir = sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(mediaID).mp4")
    }

    static func srtURL(projectID: UUID, sectionID: UUID) -> URL {
        return sectionDirectory(projectID: projectID, sectionID: sectionID)
            .appendingPathComponent("captions.srt")
    }

    static func sectionDirectory(projectID: UUID, sectionID: UUID) -> URL {
        let dir = baseDirectory
            .appendingPathComponent("projects/\(projectID)/sections/\(sectionID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Layer Cache

    /// Directory for pre-rendered layer cache files.
    static var layerCacheDirectory: URL {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("smashcut/layers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// URL for a layer's pre-rendered cached asset.
    static func layerCacheURL(layerID: UUID) -> URL {
        return layerCacheDirectory
            .appendingPathComponent("\(layerID)-processed.mp4")
    }

    /// Total size of the layer cache directory in bytes.
    static func layerCacheSize() -> UInt64 {
        let fm = FileManager.default
        let dir = layerCacheDirectory
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    /// Remove all files in the layer cache directory.
    static func clearLayerCache() {
        let fm = FileManager.default
        let dir = layerCacheDirectory
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? fm.removeItem(at: file)
        }
    }

    /// Remove a specific layer's cached file.
    static func removeLayerCache(layerID: UUID) {
        try? FileManager.default.removeItem(at: layerCacheURL(layerID: layerID))
    }

    private static var baseDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("smashcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

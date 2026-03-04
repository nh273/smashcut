import Foundation

/// Pre-renders expensive layer operations (background removal) as cached MP4 files.
/// The compositor reads from the cache instead of re-processing every frame in real time.
actor LayerAssetCache {
    static let shared = LayerAssetCache()

    /// Maximum cache size in bytes (2 GB).
    private let maxCacheBytes: UInt64 = 2 * 1024 * 1024 * 1024

    /// Active processing tasks keyed by layer ID, for cancellation.
    private var activeTasks: [UUID: Task<URL, Error>] = [:]

    // MARK: - Public API

    /// Kick off background pre-rendering for a layer that needs caching.
    /// Returns the output URL on success.
    /// - Parameters:
    ///   - layer: The layer to process (must have sourceURL and hasBackgroundRemoval).
    ///   - onProgress: Called on MainActor with progress 0…1.
    ///   - onComplete: Called on MainActor with the cached URL on success, or nil on failure.
    func prerender(
        layer: Layer,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (URL?) -> Void
    ) {
        guard layer.needsCaching,
              let sourceURL = layer.sourceURL else {
            onComplete(nil)
            return
        }

        // Cancel any existing task for this layer
        activeTasks[layer.id]?.cancel()

        let layerID = layer.id
        let outputURL = VideoFileManager.layerCacheURL(layerID: layerID)

        let task = Task<URL, Error> {
            try Task.checkCancellation()

            try await SegmentationService.shared.processVideo(
                inputURL: sourceURL,
                backgroundURL: nil,
                backgroundIsVideo: false,
                outputURL: outputURL,
                progressHandler: { progress in
                    Task { @MainActor in
                        onProgress(progress)
                    }
                }
            )

            try Task.checkCancellation()
            return outputURL
        }

        activeTasks[layerID] = task

        // Monitor the task result
        Task {
            do {
                let url = try await task.value
                self.activeTasks[layerID] = nil
                Task { @MainActor in
                    onComplete(url)
                }
            } catch is CancellationError {
                self.activeTasks[layerID] = nil
            } catch {
                self.activeTasks[layerID] = nil
                Task { @MainActor in
                    onComplete(nil)
                }
            }
        }
    }

    /// Cancel any in-progress pre-render for a layer.
    func cancelPrerender(layerID: UUID) {
        activeTasks[layerID]?.cancel()
        activeTasks[layerID] = nil
    }

    /// Check if a cached asset exists and is usable for the given layer.
    func cachedURL(for layer: Layer) -> URL? {
        guard layer.cacheState == .ready,
              let url = layer.cachedProcessedURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    // MARK: - Cache Management

    /// Evict cached files if total cache exceeds the size budget.
    /// Removes oldest files first (by modification date).
    func evictIfNeeded() {
        let currentSize = VideoFileManager.layerCacheSize()
        guard currentSize > maxCacheBytes else { return }

        let fm = FileManager.default
        let dir = VideoFileManager.layerCacheDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        // Sort oldest first
        let sorted = contents.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dateA < dateB
        }

        var freed: UInt64 = 0
        let target = currentSize - maxCacheBytes
        for file in sorted {
            guard freed < target else { break }
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                freed += UInt64(size)
            }
            try? fm.removeItem(at: file)
        }
    }

    /// Remove all cached assets. Call on app backgrounding or explicit user action.
    func clearAll() {
        // Cancel all active tasks
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        VideoFileManager.clearLayerCache()
    }

    /// Remove cached asset for a specific layer.
    func removeCache(layerID: UUID) {
        activeTasks[layerID]?.cancel()
        activeTasks[layerID] = nil
        VideoFileManager.removeLayerCache(layerID: layerID)
    }
}

// MARK: - Layer Cache Helpers

extension Array where Element == Layer {
    /// Returns layers that need background removal caching.
    var layersNeedingCache: [Layer] {
        filter { $0.needsCaching && $0.cacheState != .ready }
    }
}

// MARK: - TimelineSegment Cache Invalidation

extension TimelineSegment {
    /// Invalidate caches for layers whose source or trim has changed.
    /// Call after editing a segment's layers.
    mutating func invalidateStaleCaches() {
        for i in layers.indices {
            if layers[i].cacheState == .ready || layers[i].cacheState == .stale {
                // Cache is stale if bg removal was turned off
                if !layers[i].hasBackgroundRemoval {
                    layers[i].cacheState = .none
                    layers[i].cachedProcessedURL = nil
                    VideoFileManager.removeLayerCache(layerID: layers[i].id)
                }
            }
        }
    }

    /// Mark a specific layer's cache as stale (e.g. after source or trim change).
    mutating func markCacheStale(layerID: UUID) {
        guard let idx = layers.firstIndex(where: { $0.id == layerID }) else { return }
        layers[idx].invalidateCache()
        VideoFileManager.removeLayerCache(layerID: layerID)
    }
}

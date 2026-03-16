import AVFoundation
import UIKit

struct ThumbnailService {
    /// Extracts a single JPEG frame (~200x200) from the given video URL.
    static func generateThumbnail(from videoURL: URL) async -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
                if let cgImage {
                    let uiImage = UIImage(cgImage: cgImage)
                    continuation.resume(returning: uiImage.jpegData(compressionQuality: 0.7))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Generates filmstrip thumbnails sampled at regular intervals across a video.
    /// Returns an array of UIImages suitable for display in a horizontal strip.
    /// - Parameters:
    ///   - videoURL: Source video file URL
    ///   - duration: Segment duration in seconds (used to determine sample count)
    ///   - thumbHeight: Desired thumbnail height in points (width derived from aspect ratio)
    static func generateFilmstripThumbnails(
        from videoURL: URL,
        duration: Double,
        thumbHeight: CGFloat = 40
    ) async -> [UIImage] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbHeight * 2, height: thumbHeight * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let assetDuration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            assetDuration = CMTimeGetSeconds(cmDuration)
        } catch {
            return []
        }
        guard assetDuration > 0 else { return [] }

        // Sample roughly one frame per 0.5 seconds of segment duration, min 2 max 20
        let sampleCount = max(2, min(20, Int(ceil(duration / 0.5))))
        let effectiveDuration = min(duration, assetDuration)
        let interval = effectiveDuration / Double(sampleCount)

        var times: [NSValue] = []
        for i in 0..<sampleCount {
            let seconds = interval * Double(i) + interval * 0.5
            let clamped = min(seconds, assetDuration - 0.01)
            times.append(NSValue(time: CMTime(seconds: max(0, clamped), preferredTimescale: 600)))
        }

        return await withCheckedContinuation { continuation in
            var images: [UIImage] = []
            var remaining = times.count

            generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
                if let cgImage {
                    images.append(UIImage(cgImage: cgImage))
                }
                remaining -= 1
                if remaining == 0 {
                    continuation.resume(returning: images)
                }
            }
        }
    }
}

/// In-memory cache for filmstrip thumbnails keyed by video URL + segment duration.
actor FilmstripCache {
    static let shared = FilmstripCache()

    private var cache: [String: [UIImage]] = [:]
    private let maxEntries = 50

    func thumbnails(for url: URL, duration: Double) -> [UIImage]? {
        cache[cacheKey(url: url, duration: duration)]
    }

    func store(_ images: [UIImage], for url: URL, duration: Double) {
        if cache.count >= maxEntries {
            // Evict oldest entry
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[cacheKey(url: url, duration: duration)] = images
    }

    func invalidate(for url: URL) {
        let prefix = url.absoluteString
        for key in cache.keys where key.hasPrefix(prefix) {
            cache.removeValue(forKey: key)
        }
    }

    private func cacheKey(url: URL, duration: Double) -> String {
        "\(url.absoluteString)|\(String(format: "%.1f", duration))"
    }
}

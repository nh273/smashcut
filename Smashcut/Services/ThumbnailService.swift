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

    /// Generates filmstrip thumbnails sampled at regular intervals across a time range of a video.
    /// Works for any video URL + time range — whole clips, sub-segments, or trimmed rolls.
    /// - Parameters:
    ///   - videoURL: Source video file URL
    ///   - startTime: Start of the range in seconds (default 0)
    ///   - endTime: End of the range in seconds (nil = asset duration)
    ///   - thumbHeight: Desired thumbnail height in points (width derived from aspect ratio)
    static func generateFilmstripThumbnails(
        from videoURL: URL,
        startTime: Double = 0,
        endTime: Double? = nil,
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

        let rangeStart = max(0, min(startTime, assetDuration))
        let rangeEnd = min(endTime ?? assetDuration, assetDuration)
        let rangeDuration = rangeEnd - rangeStart
        guard rangeDuration > 0 else { return [] }

        // Sample roughly one frame per 0.5 seconds of range duration, min 2 max 20
        let sampleCount = max(2, min(20, Int(ceil(rangeDuration / 0.5))))
        let interval = rangeDuration / Double(sampleCount)

        var times: [NSValue] = []
        for i in 0..<sampleCount {
            let seconds = rangeStart + interval * Double(i) + interval * 0.5
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

/// In-memory cache for filmstrip thumbnails keyed by video URL + time range.
actor FilmstripCache {
    static let shared = FilmstripCache()

    private var cache: [String: [UIImage]] = [:]
    private let maxEntries = 50

    func thumbnails(for url: URL, startTime: Double, endTime: Double) -> [UIImage]? {
        cache[cacheKey(url: url, startTime: startTime, endTime: endTime)]
    }

    func store(_ images: [UIImage], for url: URL, startTime: Double, endTime: Double) {
        if cache.count >= maxEntries {
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[cacheKey(url: url, startTime: startTime, endTime: endTime)] = images
    }

    func invalidate(for url: URL) {
        let prefix = url.absoluteString
        for key in cache.keys where key.hasPrefix(prefix) {
            cache.removeValue(forKey: key)
        }
    }

    private func cacheKey(url: URL, startTime: Double, endTime: Double) -> String {
        "\(url.absoluteString)|\(String(format: "%.1f", startTime))|\(String(format: "%.1f", endTime))"
    }
}

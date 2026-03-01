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
}

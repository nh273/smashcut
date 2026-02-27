import Foundation

struct TimingUtilities {
    /// Groups caption timestamps into ~6-word chunks and formats as SRT.
    static func exportSRT(_ timestamps: [CaptionTimestamp]) -> String {
        guard !timestamps.isEmpty else { return "" }

        var lines: [String] = []
        let chunks = groupIntoChunks(timestamps, wordsPerChunk: 6)

        for (index, chunk) in chunks.enumerated() {
            let startStr = formatSRTTime(chunk.startSeconds)
            let endStr = formatSRTTime(chunk.endSeconds)
            let text = chunk.text

            lines.append("\(index + 1)")
            lines.append("\(startStr) --> \(endStr)")
            lines.append(text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private struct TimedChunk {
        let text: String
        let startSeconds: Double
        let endSeconds: Double
    }

    private static func groupIntoChunks(
        _ timestamps: [CaptionTimestamp],
        wordsPerChunk: Int
    ) -> [TimedChunk] {
        var chunks: [TimedChunk] = []
        var buffer: [CaptionTimestamp] = []
        var wordCount = 0

        for ts in timestamps {
            let words = ts.text.split(separator: " ").count
            buffer.append(ts)
            wordCount += words

            if wordCount >= wordsPerChunk {
                if let first = buffer.first, let last = buffer.last {
                    let text = buffer.map(\.text).joined(separator: " ")
                    chunks.append(TimedChunk(
                        text: text,
                        startSeconds: first.startSeconds,
                        endSeconds: last.endSeconds
                    ))
                }
                buffer = []
                wordCount = 0
            }
        }

        // Flush remaining
        if !buffer.isEmpty, let first = buffer.first, let last = buffer.last {
            let text = buffer.map(\.text).joined(separator: " ")
            chunks.append(TimedChunk(
                text: text,
                startSeconds: first.startSeconds,
                endSeconds: last.endSeconds
            ))
        }

        return chunks
    }

    static func formatSRTTime(_ seconds: Double) -> String {
        let totalMs = Int((seconds * 1000).rounded())
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let sec = totalSec % 60
        let min = (totalSec / 60) % 60
        let hr = totalSec / 3600
        return String(format: "%02d:%02d:%02d,%03d", hr, min, sec, ms)
    }
}

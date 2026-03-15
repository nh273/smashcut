import Foundation
import Observation

/// An editable caption chunk at the SRT level (~6 words).
struct EditableCaptionChunk: Identifiable {
    var id = UUID()
    var text: String
    var startSeconds: Double
    var endSeconds: Double
    /// Normalized vertical position (0 = top, 1 = bottom).
    var verticalPosition: Double = 0.82
}

@Observable
class CaptionEditorViewModel {
    var chunks: [EditableCaptionChunk]
    var totalDuration: Double

    init(recording: Recording) {
        self.totalDuration = max(recording.durationSeconds, 1)
        self.chunks = CaptionEditorViewModel.buildChunks(from: recording.captionTimestamps)
    }

    // MARK: - Chunk conversion

    static func buildChunks(from timestamps: [CaptionTimestamp]) -> [EditableCaptionChunk] {
        guard !timestamps.isEmpty else { return [] }

        var chunks: [EditableCaptionChunk] = []
        var buffer: [CaptionTimestamp] = []
        var wordCount = 0
        let wordsPerChunk = 6

        for ts in timestamps {
            buffer.append(ts)
            wordCount += ts.text.split(separator: " ").count

            if wordCount >= wordsPerChunk {
                if let first = buffer.first, let last = buffer.last {
                    chunks.append(EditableCaptionChunk(
                        text: buffer.map(\.text).joined(separator: " "),
                        startSeconds: first.startSeconds,
                        endSeconds: last.endSeconds,
                        verticalPosition: first.verticalPosition
                    ))
                }
                buffer = []
                wordCount = 0
            }
        }

        if !buffer.isEmpty, let first = buffer.first, let last = buffer.last {
            chunks.append(EditableCaptionChunk(
                text: buffer.map(\.text).joined(separator: " "),
                startSeconds: first.startSeconds,
                endSeconds: last.endSeconds,
                verticalPosition: first.verticalPosition
            ))
        }

        return chunks
    }

    func toCaptionTimestamps() -> [CaptionTimestamp] {
        chunks.map { chunk in
            CaptionTimestamp(
                text: chunk.text,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                verticalPosition: chunk.verticalPosition
            )
        }
    }

    // MARK: - Editing

    /// Adjust start of chunk at index, clamping against previous chunk's end.
    func adjustStart(at index: Int, to newStart: Double) {
        var start = max(0, newStart)
        if index > 0 {
            start = max(start, chunks[index - 1].endSeconds + 0.05)
        }
        start = min(start, chunks[index].endSeconds - 0.1)
        chunks[index].startSeconds = start
    }

    /// Adjust end of chunk at index, clamping against next chunk's start.
    func adjustEnd(at index: Int, to newEnd: Double) {
        var end = min(totalDuration, newEnd)
        if index < chunks.count - 1 {
            end = min(end, chunks[index + 1].startSeconds - 0.05)
        }
        end = max(end, chunks[index].startSeconds + 0.1)
        chunks[index].endSeconds = end
    }

    /// Set vertical position for a single chunk.
    func setVerticalPosition(at index: Int, to position: Double) {
        chunks[index].verticalPosition = min(max(position, 0), 1)
    }

    /// Apply the vertical position of the given chunk to all chunks.
    func applyVerticalPositionToAll(from index: Int) {
        let pos = chunks[index].verticalPosition
        for i in chunks.indices {
            chunks[i].verticalPosition = pos
        }
    }

    /// Delete the chunk at index.
    func deleteChunk(at index: Int) {
        chunks.remove(at: index)
    }

    /// Split the chunk at index at its temporal midpoint.
    func addChunkAfter(index: Int) {
        let chunk = chunks[index]
        let mid = (chunk.startSeconds + chunk.endSeconds) / 2

        let words = chunk.text.split(separator: " ").map(String.init)
        let halfIdx = max(1, words.count / 2)
        let firstHalf = words.prefix(halfIdx).joined(separator: " ")
        let secondHalf = words.dropFirst(halfIdx).joined(separator: " ")

        chunks[index] = EditableCaptionChunk(
            text: firstHalf.isEmpty ? chunk.text : firstHalf,
            startSeconds: chunk.startSeconds,
            endSeconds: mid,
            verticalPosition: chunk.verticalPosition
        )
        chunks.insert(EditableCaptionChunk(
            text: secondHalf.isEmpty ? chunk.text : secondHalf,
            startSeconds: mid,
            endSeconds: chunk.endSeconds,
            verticalPosition: chunk.verticalPosition
        ), at: index + 1)
    }
}

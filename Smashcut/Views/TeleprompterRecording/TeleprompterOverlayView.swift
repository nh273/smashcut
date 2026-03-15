import SwiftUI

struct TeleprompterOverlayView: View {
    let words: [String]
    let currentWordIndex: Int
    let isRecording: Bool

    /// Number of words per scroll-targeted chunk. Large enough for natural
    /// paragraph flow while still giving smooth auto-scroll granularity.
    private let wordsPerChunk = 20

    private var chunks: [[Int]] {
        stride(from: 0, to: words.count, by: wordsPerChunk).map { start in
            Array(start..<min(start + wordsPerChunk, words.count))
        }
    }

    private func chunkIndex(for wordIndex: Int) -> Int {
        wordIndex / wordsPerChunk
    }

    /// Build a flowing Text for a chunk, highlighting the current word.
    private func styledText(for chunk: [Int]) -> Text {
        chunk.enumerated().reduce(Text("")) { result, pair in
            let (position, wordIdx) = pair
            let separator = position == 0 ? Text("") : Text(" ")
            let highlight = wordIdx == currentWordIndex && isRecording
            let word = Text(words[wordIdx])
                .foregroundColor(highlight ? Color.yellow : Color.white)
            return result + separator + word
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 180)

                    ForEach(chunks.indices, id: \.self) { chunkIdx in
                        styledText(for: chunks[chunkIdx])
                            .font(.system(size: 30, weight: .semibold))
                            .shadow(color: .black.opacity(0.8), radius: 3, x: 1, y: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(chunkIdx)
                    }

                    Color.clear.frame(height: 180)
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: currentWordIndex) { _, newIndex in
                guard newIndex < words.count else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(chunkIndex(for: newIndex), anchor: .center)
                }
            }
        }
    }
}

import SwiftUI

struct TeleprompterOverlayView: View {
    let words: [String]
    let currentWordIndex: Int
    let isRecording: Bool

    private let wordsPerRow = 5

    // Group word indices into rows of `wordsPerRow`
    private var rows: [[Int]] {
        stride(from: 0, to: words.count, by: wordsPerRow).map { start in
            Array(start..<min(start + wordsPerRow, words.count))
        }
    }

    private func rowIndex(for wordIndex: Int) -> Int {
        wordIndex / wordsPerRow
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 180)

                    ForEach(rows.indices, id: \.self) { rowIdx in
                        HStack(alignment: .center, spacing: 8) {
                            ForEach(rows[rowIdx], id: \.self) { wordIdx in
                                Text(words[wordIdx])
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(
                                        wordIdx == currentWordIndex && isRecording
                                            ? Color.yellow
                                            : Color.white
                                    )
                                    .shadow(color: .black.opacity(0.8), radius: 3, x: 1, y: 1)
                            }
                        }
                        // Each row is a direct LazyVStack child — scrollTo can target it
                        .id(rowIdx)
                    }

                    Color.clear.frame(height: 180)
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: currentWordIndex) { _, newIndex in
                guard newIndex < words.count else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(rowIndex(for: newIndex), anchor: .center)
                }
            }
        }
    }
}

import SwiftUI

struct TeleprompterOverlayView: View {
    let words: [String]
    let currentWordIndex: Int
    let isRecording: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 200)
                    flowLayout
                    Spacer().frame(height: 200)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: currentWordIndex) { _, newIndex in
                guard newIndex < words.count else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var flowLayout: some View {
        // Simple flow layout using wrapped HStack approach
        let lineBreakWords = buildLines(words: words, maxCharsPerLine: 30)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(lineBreakWords.indices, id: \.self) { lineIdx in
                HStack(spacing: 6) {
                    ForEach(lineBreakWords[lineIdx], id: \.offset) { item in
                        Text(item.word)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(item.globalIndex == currentWordIndex && isRecording
                                             ? Color.yellow
                                             : Color.white)
                            .shadow(color: .black, radius: 2, x: 1, y: 1)
                            .id(item.globalIndex)
                    }
                }
            }
        }
    }

    private struct WordItem {
        let word: String
        let offset: Int
        let globalIndex: Int
    }

    private func buildLines(words: [String], maxCharsPerLine: Int) -> [[WordItem]] {
        var lines: [[WordItem]] = []
        var currentLine: [WordItem] = []
        var currentLength = 0

        for (idx, word) in words.enumerated() {
            let item = WordItem(word: word, offset: idx, globalIndex: idx)
            if currentLength + word.count > maxCharsPerLine && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = [item]
                currentLength = word.count + 1
            } else {
                currentLine.append(item)
                currentLength += word.count + 1
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
    }
}

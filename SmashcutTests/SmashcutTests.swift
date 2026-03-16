import Foundation
import Testing
@testable import Smashcut

struct SmashcutTests {
    @Test func srtExportFormatsCorrectly() {
        let timestamps = [
            CaptionTimestamp(text: "Hello", startSeconds: 0.0, endSeconds: 0.5),
            CaptionTimestamp(text: "world", startSeconds: 0.5, endSeconds: 1.0),
            CaptionTimestamp(text: "this", startSeconds: 1.0, endSeconds: 1.5),
            CaptionTimestamp(text: "is", startSeconds: 1.5, endSeconds: 2.0),
            CaptionTimestamp(text: "a", startSeconds: 2.0, endSeconds: 2.5),
            CaptionTimestamp(text: "test", startSeconds: 2.5, endSeconds: 3.0)
        ]
        let srt = TimingUtilities.exportSRT(timestamps)
        #expect(srt.contains("00:00:00,000 --> "))
        #expect(srt.contains("Hello world this is a test"))
    }

    @Test func srtTimeFormat() {
        let result = TimingUtilities.formatSRTTime(3661.5)
        #expect(result == "01:01:01,500")
    }

    // MARK: - TimingUtilities.defaultDuration (sm-zxvl)

    @Test func defaultDurationEmptyStringReturnsMinimum() {
        let duration = TimingUtilities.defaultDuration(for: "")
        #expect(duration == 1.5)
    }

    @Test func defaultDurationShortWordReturnsMinimum() {
        let duration = TimingUtilities.defaultDuration(for: "Hello")
        // 5 chars / 15.0 = 0.33, below 1.5 minimum
        #expect(duration == 1.5)
    }

    @Test func defaultDurationSixtyCharsReturnsAboutFourSeconds() {
        let text = String(repeating: "a", count: 60)
        let duration = TimingUtilities.defaultDuration(for: text)
        // 60 / 15.0 = 4.0
        #expect(duration == 4.0)
    }

    @Test func defaultDuration120CharsReturnsAboutEightSeconds() {
        let text = String(repeating: "a", count: 120)
        let duration = TimingUtilities.defaultDuration(for: text)
        // 120 / 15.0 = 8.0
        #expect(duration == 8.0)
    }

    @Test func defaultDurationFollowsFormula() {
        for count in [0, 5, 22, 30, 45, 60, 90, 120, 200] {
            let text = String(repeating: "x", count: count)
            let expected = max(1.5, Double(count) / 15.0)
            let result = TimingUtilities.defaultDuration(for: text)
            #expect(result == expected, "Failed for count=\(count)")
        }
    }

    // MARK: - CaptionStyle rendering params (sm-txk6)

    @Test func captionStyleDefaultValues() {
        let style = CaptionStyle()
        #expect(style.fontName == "Helvetica-Bold")
        #expect(style.fontSize == 44)
        #expect(style.textColor == .white)
        #expect(style.contrastMode == .shadow)
    }

    @Test func captionStyleStrokeModeValues() {
        var style = CaptionStyle()
        style.contrastMode = .stroke
        #expect(style.contrastMode == .stroke)
    }

    @Test func captionStyleHighlightModeValues() {
        var style = CaptionStyle()
        style.contrastMode = .highlight
        #expect(style.contrastMode == .highlight)
    }

    @Test func captionStyleNoneModeValues() {
        var style = CaptionStyle()
        style.contrastMode = .none
        #expect(style.contrastMode == .none)
    }

    @Test func captionTimestampDefaultPosition() {
        let ts = CaptionTimestamp(text: "test", startSeconds: 0, endSeconds: 1)
        #expect(ts.verticalPosition == 0.82)
    }

    @Test func captionTimestampPositionToYCoordinate() {
        let ts = CaptionTimestamp(text: "test", startSeconds: 0, endSeconds: 1, verticalPosition: 0.82)
        let frameHeight = 1920.0
        // CALayer y from bottom = (1.0 - 0.82) * 1920 = 0.18 * 1920 = 345.6
        let yPosition = (1.0 - ts.verticalPosition) * frameHeight
        #expect(abs(yPosition - 345.6) < 0.1)
    }

    @Test func captionTimestampTopPositionYCoordinate() {
        let ts = CaptionTimestamp(text: "test", startSeconds: 0, endSeconds: 1, verticalPosition: 0.1)
        let frameHeight = 1920.0
        let yPosition = (1.0 - ts.verticalPosition) * frameHeight
        // (1.0 - 0.1) * 1920 = 1728
        #expect(abs(yPosition - 1728.0) < 0.1)
    }

    @Test func captionColorEquality() {
        #expect(CaptionColor.white == CaptionColor(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(CaptionColor.black == CaptionColor(red: 0, green: 0, blue: 0, alpha: 1))
        #expect(CaptionColor.white != CaptionColor.black)
    }

    @Test func captionStyleCodable() throws {
        let style = CaptionStyle(fontName: "Courier", fontSize: 32, textColor: CaptionColor.yellow, contrastMode: ContrastMode.highlight)
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(CaptionStyle.self, from: data)
        #expect(decoded.fontName == "Courier")
        #expect(decoded.fontSize == 32)
        #expect(decoded.textColor == CaptionColor.yellow)
        #expect(decoded.contrastMode == ContrastMode.highlight)
    }
}

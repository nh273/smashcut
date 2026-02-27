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
}

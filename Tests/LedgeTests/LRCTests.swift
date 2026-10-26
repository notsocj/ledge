import Testing
@testable import Ledge

@Test func parsesTimestampsSortsAndSkipsMetadata() {
    let lrc = """
    [ar:Someone]
    [00:12.50]Hello
    [01:02.00][00:05.00] Twice
    [00:20.00]
    not a lyric
    """
    #expect(LRC.parse(lrc) == [
        LyricLine(time: 5, text: "Twice"),
        LyricLine(time: 12.5, text: "Hello"),
        LyricLine(time: 20, text: ""),
        LyricLine(time: 62, text: "Twice"),
    ])
}

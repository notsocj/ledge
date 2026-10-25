import AppKit
import Testing
@testable import Kestrel

private func solid(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
        color.setFill()
        rect.fill()
        return true
    }
}

@MainActor @Test func accentStaysLegibleOnBlack() throws {
    let fromBlack = try #require(NowPlaying.accent(of: solid(.black)))
    #expect(fromBlack.brightnessComponent >= 0.85)

    let fromRed = try #require(NowPlaying.accent(of: solid(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))))
    #expect(fromRed.saturationComponent <= 0.65)
    #expect(fromRed.redComponent > fromRed.blueComponent) // still reads as the artwork's hue
}

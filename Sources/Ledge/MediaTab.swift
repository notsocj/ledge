import SwiftUI

struct MediaTab: View {
    let nowPlaying: NowPlaying
    let lyrics: [LyricLine]?

    var body: some View {
        if nowPlaying.hasTrack {
            VStack(alignment: .leading, spacing: 10) {
                header
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let time = nowPlaying.position(at: context.date)
                    VStack(alignment: .leading, spacing: 8) {
                        LyricsView(lines: lyrics, time: time)
                        ProgressRow(time: time, duration: nowPlaying.duration, accent: Color(nsColor: nowPlaying.accent))
                    }
                }
            }
        } else {
            EmptyTab(symbol: "music-note-linear", title: "Nothing playing", hint: "Play music in any app and it shows up here.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Artwork(image: nowPlaying.artwork, size: 48, radius: Radius.control + 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlaying.title)
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
                Text(nowPlaying.artist)
                    .font(Typeface.body)
                    .foregroundStyle(Palette.graphite)
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(Motion.easeOut(0.25), value: nowPlaying.trackKey)
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                IconButton(symbol: "skip-previous-bold", label: "Previous track", size: 12, box: 28) { nowPlaying.send(.previous) }
                IconButton(symbol: nowPlaying.isPlaying ? "pause-bold" : "play-bold", label: nowPlaying.isPlaying ? "Pause" : "Play", size: 16, box: 32) {
                    nowPlaying.send(.togglePlayPause)
                }
                IconButton(symbol: "skip-next-bold", label: "Next track", size: 12, box: 28) { nowPlaying.send(.next) }
            }
        }
    }
}

/// A tab with nothing to show yet: the tool's symbol, what it is, and how to fill it. Every empty tab
/// uses this, so an empty island always reads the same way.
struct EmptyTab: View {
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 10) {
            Icon(name: symbol, size: 18)
                .foregroundStyle(Palette.graphite)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.well))
            VStack(spacing: 4) {
                Text(title)
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
                Text(hint)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.ash)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// Synced lyrics as a two-line window onto the whole song: the current line in full white, the next
/// one dimmed below it. Each change scrolls the stack up, so the next line visibly becomes the current one.
private struct LyricsView: View {
    let lines: [LyricLine]?
    let time: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let lineHeight: CGFloat = 24

    var body: some View {
        Group {
            if let lines, !lines.isEmpty {
                let current = lines.lastIndex { $0.time <= time } ?? -1
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(Self.text(lines[index]))
                            .opacity(index == current ? 1 : index == current + 1 ? 0.38 : 0)
                            .frame(height: lineHeight, alignment: .leading)
                    }
                }
                .offset(y: -CGFloat(current) * lineHeight)
                .frame(height: lineHeight * 2, alignment: .top)
                .clipped()
                .animation(reduceMotion ? nil : Motion.lyric, value: current)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lines.indices.contains(current) ? Self.text(lines[current]) : "")
            } else {
                Text(lines == nil ? "Looking for lyrics" : "No synced lyrics for this track")
                    .fontWeight(.regular)
                    .foregroundStyle(Palette.ash)
                    .frame(height: lineHeight * 2, alignment: .topLeading)
            }
        }
        .font(Typeface.lyric)
        .tracking(-0.2)
        .foregroundStyle(Palette.paper)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func text(_ line: LyricLine) -> String { line.text.isEmpty ? "♪" : line.text }
}

struct ProgressRow: View {
    let time: TimeInterval
    let duration: TimeInterval
    let accent: Color

    var body: some View {
        let progress = duration > 0 ? min(1, max(0, time / duration)) : 0
        HStack(spacing: 10) {
            Text(Self.format(time))
            GeometryReader { geometry in
                Capsule()
                    .fill(Palette.rail)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: geometry.size.width * progress)
                    }
            }
            .frame(height: 4)
            Text("-" + Self.format(duration - time))
        }
        .font(Typeface.caption.monospacedDigit())
        .foregroundStyle(Palette.ash)
        .animation(.linear(duration: 0.25), value: progress) // glide between the 0.25s ticks
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.format(time)) of \(Self.format(duration))")
    }

    private static func format(_ time: TimeInterval) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

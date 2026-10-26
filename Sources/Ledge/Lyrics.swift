import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

enum LRC {
    /// Parses "[mm:ss.xx]text" lines, sorted by time. A line may carry several timestamps;
    /// metadata tags like "[ar:Artist]" are skipped.
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let parts = rest[rest.index(after: rest.startIndex)..<close].split(separator: ":")
                rest = rest[rest.index(after: close)...]
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(minutes * 60 + seconds)
                }
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

/// Synced lyrics from lrclib.net (free, no API key). Any failure just means no lyrics.
enum LRCLIB {
    private struct Record: Decodable {
        let syncedLyrics: String?
    }

    static func syncedLyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> [LyricLine] {
        // Exact match first (LRCLIB matches duration within a couple of seconds), then a looser search.
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        if let record: Record = await fetch(get.url!), let lrc = record.syncedLyrics {
            return LRC.parse(lrc)
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        let records: [Record] = await fetch(search.url!) ?? []
        return records.lazy.compactMap(\.syncedLyrics).first.map(LRC.parse) ?? []
    }

    private static func fetch<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("Ledge/0.1 (macOS notch app)", forHTTPHeaderField: "User-Agent") // LRCLIB asks clients to identify themselves
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

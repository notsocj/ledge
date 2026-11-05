import SwiftUI

/// A quiet companion inside the existing island. Data changes never replay the island's spring.
/// Weight sets the reading order: the race and the countdown, then the session that's next (highlighted),
/// then the rest of the weekend and the last podium.
struct F1View: View {
    let companion: F1Companion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 0) {
                schedule.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Palette.rail).frame(width: 1).padding(.horizontal, 14).padding(.vertical, 2)
                podium.frame(width: 164, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Local times · \(companion.statusText)")
                    .foregroundStyle(Palette.ash)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Session times in \(TimeZone.current.identifier)")
                Link("Jolpica ↗", destination: URL(string: "https://jolpi.ca/")!)
                    .foregroundStyle(Palette.ash)
                    .help("Schedule and published results by Jolpica · CC BY-NC-SA 4.0")
            }
            .font(Typeface.caption)
        }
        .animation(nil, value: companion.now)
    }

    // MARK: Header

    private var counting: Bool { companion.weekend?.start != nil && !companion.isResultsPending }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(companion.weekend?.name ?? "Formula 1")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.paper)
                    .lineLimit(1).truncationMode(.tail)
                    .help(companion.weekend?.name ?? "Formula 1")
                Text(companion.weekend.map { "Round \($0.round) · \($0.circuit)" } ?? "The next weekend will appear here.")
                    .font(Typeface.caption).foregroundStyle(Palette.graphite).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                // A countdown is the biggest thing here; words like "Results pending" stay smaller.
                Text(companion.countdown)
                    .font(.system(size: counting ? 22 : 13, weight: .bold))
                    .monospacedDigit().foregroundStyle(Palette.paper)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(counting ? "to lights out" : companion.isResultsPending ? "Race status" : "")
                    .font(Typeface.caption).foregroundStyle(Palette.graphite)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Schedule

    /// The first session that hasn't started; nil once the whole weekend has.
    private func nextIndex(_ sessions: [F1Session]) -> Int? {
        sessions.firstIndex { ($0.start ?? .distantFuture) > companion.now }
    }

    private var schedule: some View {
        Group {
            if let weekend = companion.weekend, !weekend.sessions.isEmpty {
                let next = nextIndex(weekend.sessions)
                VStack(spacing: 1) {
                    ForEach(Array(weekend.sessions.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session, done: next.map { index < $0 } ?? true, isNext: index == next)
                    }
                }
                .padding(.leading, -6)
            } else {
                Text(companion.isRefreshing ? "Checking the calendar…" : "The next schedule isn’t published yet.")
                    .font(Typeface.body).foregroundStyle(Palette.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One session: a status mark, its name, then its day and time in aligned columns.
    /// Done sessions fade, the next one sits on a highlight with how long until it starts, and the race has a flag.
    private func sessionRow(_ session: F1Session, done: Bool, isNext: Bool) -> some View {
        let isRace = session.id == "race"
        let emphasis = isNext || (isRace && !done)
        return HStack(spacing: 0) {
            Group {
                if isRace && !done {
                    CheckeredFlag().frame(width: 11, height: 11)
                        .foregroundStyle(isNext ? Palette.live : Palette.paper)
                } else if done {
                    Circle().fill(Palette.rail).frame(width: 5, height: 5)
                } else if isNext {
                    Circle().fill(Palette.live).frame(width: 6, height: 6)
                } else {
                    Circle().strokeBorder(Palette.graphite, lineWidth: 1).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18)

            Text(session.title)
                .font(emphasis ? Typeface.headline : Typeface.row)
                .foregroundStyle(done ? Palette.ash : emphasis ? Palette.paper : Palette.graphite)
                .lineLimit(1)
            if isNext, let start = session.start {
                Text(Self.until(start, from: companion.now))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Palette.live)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Palette.live.opacity(0.16)))
                    .padding(.leading, 6)
                    .fixedSize()
            }
            Spacer(minLength: 8)
            Text(session.dayLabel())
                .font(Typeface.body).foregroundStyle(done ? Palette.ash : Palette.graphite)
                .lineLimit(1)
                .padding(.trailing, 10)
            Text(session.timeLabel())
                .font(emphasis ? Typeface.headline : Typeface.row).monospacedDigit()
                .foregroundStyle(done ? Palette.ash : Palette.paper)
                .lineLimit(1)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .frame(height: 22)
        .padding(.leading, 0).padding(.trailing, 6)
        .background {
            if isNext { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.well) }
        }
        .help("\(session.title), \(session.dayLabel()) · \(session.timeLabel())")
        .accessibilityElement(children: .combine)
    }

    /// "in 2d 4h", "in 3h 20m", "in 12m".
    static func until(_ start: Date, from now: Date) -> String {
        let minutes = max(1, Int(ceil(start.timeIntervalSince(now) / 60)))
        if minutes >= 24 * 60 { return "in \(minutes / (24 * 60))d \((minutes / 60) % 24)h" }
        if minutes >= 60 { return "in \(minutes / 60)h \(minutes % 60)m" }
        return "in \(minutes)m"
    }

    // MARK: Podium

    /// Silver and bronze for second and third (index 1 and 2), muted so they sit quietly on black.
    /// The winner gets the champagne bottle instead.
    private static let medals: [Color] = [
        Color(red: 0.91, green: 0.77, blue: 0.42),
        Color(red: 0.80, green: 0.82, blue: 0.85),
        Color(red: 0.82, green: 0.58, blue: 0.39),
    ]

    private var podium: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(companion.latestPodium.map { "Last podium · \($0.race.shortName)" } ?? "Last podium")
                .font(Typeface.caption).foregroundStyle(Palette.graphite).lineLimit(1)
                .help(companion.latestPodium.map { "\($0.race.name), \($0.race.season)" } ?? "")
            if let podium = companion.latestPodium {
                ForEach(podium.drivers, id: \.position) { driver in
                    // One line per place: badge, surname (as on timing screens: "Andrea Kimi Antonelli" reads as
                    // "Antonelli"), then the team, quieter, on the right.
                    HStack(spacing: 9) {
                        // The winner gets the champagne; second and third keep numbered silver and bronze badges.
                        if driver.position == 1 {
                            ChampagneBottle().frame(width: 20, height: 20).padding(-1)
                        } else {
                            Text("\(driver.position)")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(driver.position <= 3 ? Self.medals[driver.position - 1] : Palette.rail))
                        }
                        Text(Self.surname(driver.name)).font(Typeface.headline).foregroundStyle(Palette.paper)
                        Spacer(minLength: 6)
                        Text(driver.team).font(Typeface.caption).foregroundStyle(Palette.graphite)
                    }
                    .lineLimit(1)
                    .frame(height: 20)
                    .help("\(driver.position). \(driver.name), \(driver.team)")
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("The podium appears once results are published.")
                    .font(Typeface.body).foregroundStyle(Palette.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}

struct F1CompactView: View {
    let companion: F1Companion
    let height: CGFloat

    /// The camera keeps its own space; the wings only reserve what their labels need.
    static func wingWidth(for companion: F1Companion) -> CGFloat {
        let font = companion.isResultsPending ? NSFont.systemFont(ofSize: 10.5, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let labelWidth = (companion.countdown as NSString).size(withAttributes: [.font: font]).width
        // Fourteen points of outer padding plus eight clear of the camera, including offseason dates.
        return max(64, ceil(labelWidth) + 22)
    }

    var body: some View {
        Wings(height: height) {
            F1Mark().frame(width: 28, height: 11)
        } trailing: {
            Text(companion.countdown)
                .font(companion.isResultsPending ? Typeface.caption : Typeface.wing)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Formula 1, \(companion.weekend?.name ?? "next race"), \(companion.countdown)")
    }
}

/// Ledge's own F1 mark, not Formula 1's trademarked logo: a soft, rounded "F1" with speed lines, slanted
/// forward. Drawn on a 52 × 20 grid and scaled to fit; it fills with the foreground style, like an icon.
struct F1Mark: Shape {
    /// One outline per piece (three speed lines, the F, the 1), already slanted; every corner is rounded.
    private static let pieces: [[CGPoint]] = outlines.map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
    private static let outlines: [[(CGFloat, CGFloat)]] = [
        [(6.64, 4.2), (15.14, 4.2), (14.13, 6.6), (5.63, 6.6)],
        [(7.7, 8.8), (13.2, 8.8), (12.2, 11.2), (6.7, 11.2)],
        [(8.77, 13.4), (11.27, 13.4), (10.26, 15.8), (7.76, 15.8)],
        [(19.4, 0), (40.4, 0), (38.22, 5.2), (22.72, 5.2), (21.46, 8.2), (31.46, 8.2), (29.61, 12.6), (19.61, 12.6), (16.5, 20), (11.0, 20)],
        [(42.9, 0), (51.9, 0), (43.5, 20), (38.0, 20), (44.47, 4.6), (40.97, 4.6)],
    ]
    private static let radius: CGFloat = 1.7

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 52, rect.height / 20)
        let origin = CGPoint(x: rect.midX - 26 * scale, y: rect.midY - 10 * scale)
        func place(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }
        /// A point `radius` along the edge from `corner` toward `other` (at most halfway, so thin pieces become pills).
        func toward(_ corner: CGPoint, _ other: CGPoint) -> CGPoint {
            let dx = other.x - corner.x, dy = other.y - corner.y, length = hypot(dx, dy)
            let t = min(Self.radius, length / 2) / length
            return CGPoint(x: corner.x + dx * t, y: corner.y + dy * t)
        }
        var path = Path()
        for piece in Self.pieces {
            let count = piece.count
            for index in 0...count {
                let corner = piece[index % count]
                let before = toward(corner, piece[(index + count - 1) % count])
                let after = toward(corner, piece[(index + 1) % count])
                if index == 0 {
                    path.move(to: place(after))
                } else {
                    path.addLine(to: place(before))
                    path.addQuadCurve(to: place(after), control: place(corner))
                }
            }
            path.closeSubpath()
        }
        return path
    }
}

/// The winner's champagne: a bottle tipped to spray, with a few bubbles. Drawn on a 20 × 20 grid.
struct ChampagneBottle: View {
    private static let foam = Color(red: 0.97, green: 0.91, blue: 0.72)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    BottleShape().fill(LinearGradient(colors: [Color(red: 0.96, green: 0.86, blue: 0.60), Color(red: 0.83, green: 0.68, blue: 0.38)],
                                                      startPoint: .leading, endPoint: .trailing))
                    Path(roundedRect: CGRect(x: 8.2, y: 1.2, width: 3.6, height: 2.4), cornerRadius: 0.4).fill(Self.foam)
                    Path(CGRect(x: 5.8, y: 12.5, width: 8.4, height: 3.1)).fill(Color(red: 0.29, green: 0.23, blue: 0.11))
                }
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(28))
                Path { path in
                    for (x, y, r) in [(16.6, 2.6, 1.0), (18.6, 5.0, 0.8), (15.2, 0.7, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    }
                }
                .fill(Self.foam)
            }
            .frame(width: 20, height: 20, alignment: .topLeading)
            .scaleEffect(min(proxy.size.width, proxy.size.height) / 20, anchor: .topLeading)
        }
        .accessibilityHidden(true)
    }

    private struct BottleShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 8.6, y: 3.5))
            path.addLine(to: CGPoint(x: 11.4, y: 3.5))
            path.addLine(to: CGPoint(x: 11.4, y: 7))
            path.addCurve(to: CGPoint(x: 14.2, y: 11), control1: CGPoint(x: 11.4, y: 8.3), control2: CGPoint(x: 14.2, y: 8.6))
            path.addLine(to: CGPoint(x: 14.2, y: 18))
            path.addQuadCurve(to: CGPoint(x: 13.4, y: 19), control: CGPoint(x: 14.2, y: 19))
            path.addLine(to: CGPoint(x: 6.6, y: 19))
            path.addQuadCurve(to: CGPoint(x: 5.8, y: 18), control: CGPoint(x: 5.8, y: 19))
            path.addLine(to: CGPoint(x: 5.8, y: 11))
            path.addCurve(to: CGPoint(x: 8.6, y: 7), control1: CGPoint(x: 5.8, y: 8.6), control2: CGPoint(x: 8.6, y: 8.3))
            path.closeSubpath()
            return path
        }
    }
}

/// A small checkered flag in the soft style of the F1 mark: a rounded pole and a rounded cloth with three
/// checks, in the foreground style so it follows the row. Drawn on a 14 × 14 grid.
struct CheckeredFlag: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 14
            context.scaleBy(x: scale, y: scale)
            context.fill(Path(roundedRect: CGRect(x: 1.2, y: 1, width: 1.2, height: 12), cornerRadius: 0.6), with: .foreground)
            var cloth = context
            cloth.clip(to: Path(roundedRect: CGRect(x: 2.4, y: 1.6, width: 10.2, height: 7), cornerRadius: 1.4))
            for (x, y) in [(2.4, 1.6), (9.2, 1.6), (5.8, 5.1)] as [(CGFloat, CGFloat)] {
                cloth.fill(Path(CGRect(x: x, y: y, width: 3.4, height: 3.5)), with: .foreground)
            }
            context.stroke(Path(roundedRect: CGRect(x: 2.9, y: 2.1, width: 9.2, height: 6), cornerRadius: 0.9), with: .foreground, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

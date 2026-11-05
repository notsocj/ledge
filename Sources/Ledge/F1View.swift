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
                    Image(systemName: "flag.checkered").font(.system(size: 9, weight: .bold))
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

    /// Champagne for the winner (a soft metallic gradient, so first place reads first), then silver and
    /// bronze, muted so they sit quietly on black.
    private static let medals: [AnyShapeStyle] = [
        AnyShapeStyle(LinearGradient(colors: [Color(red: 0.97, green: 0.93, blue: 0.81), Color(red: 0.85, green: 0.74, blue: 0.53)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)),
        AnyShapeStyle(Color(red: 0.80, green: 0.82, blue: 0.85)),
        AnyShapeStyle(Color(red: 0.82, green: 0.58, blue: 0.39)),
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
                        Text("\(driver.position)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(driver.position >= 1 && driver.position <= 3 ? Self.medals[driver.position - 1] : AnyShapeStyle(Palette.rail)))
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
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered").font(.system(size: 12, weight: .semibold))
                Text("F1").font(Typeface.wing)
            }
        } trailing: {
            Text(companion.countdown)
                .font(companion.isResultsPending ? Typeface.caption : Typeface.wing)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Formula 1, \(companion.weekend?.name ?? "next race"), \(companion.countdown)")
    }
}

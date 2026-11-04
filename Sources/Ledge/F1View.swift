import SwiftUI

/// A quiet companion inside the existing island. Data changes never replay the island's spring.
struct F1View: View {
    let companion: F1Companion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(companion.weekend?.name ?? "Formula 1")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.paper)
                        .lineLimit(1).truncationMode(.tail)
                        .help(companion.weekend?.name ?? "Formula 1")
                    Text(companion.weekend?.circuit ?? "The next weekend will appear here.")
                        .font(Typeface.caption).foregroundStyle(Palette.graphite).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(companion.isResultsPending ? "Race status" : "Next race")
                        .font(Typeface.caption).foregroundStyle(Palette.graphite)
                    Text(companion.countdown)
                        .font(.system(size: companion.weekend?.start != nil && !companion.isResultsPending ? 18 : 12, weight: .semibold))
                        .monospacedDigit().foregroundStyle(Palette.paper)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(alignment: .top, spacing: 16) {
                schedule.frame(maxWidth: .infinity, alignment: .leading)
                podium.frame(width: 184, alignment: .leading)
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.rail).frame(width: 1)
                    }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(companion.statusText)
                    .foregroundStyle(Palette.graphite)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link("Jolpica ↗", destination: URL(string: "https://jolpi.ca/")!)
                    .foregroundStyle(Palette.graphite)
                    .help("Schedule and published results by Jolpica · CC BY-NC-SA 4.0")
            }
            .font(Typeface.caption)
        }
        .animation(nil, value: companion.now)
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Weekend schedule").font(Typeface.headline).foregroundStyle(Palette.paper)
                Spacer(minLength: 0)
                Text("Local time")
                    .font(Typeface.caption).foregroundStyle(Palette.graphite)
                    .help("Session times in \(TimeZone.current.identifier)")
            }
            if let weekend = companion.weekend, !weekend.sessions.isEmpty {
                VStack(spacing: 5) {
                    ForEach(weekend.sessions) { session in
                        HStack(spacing: 8) {
                            Text(session.title)
                                .foregroundStyle(session.id == "race" ? Palette.paper : Palette.graphite)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(sessionTime(session))
                                .foregroundStyle(Palette.paper)
                                .monospacedDigit()
                        }
                        .font(Typeface.body)
                        .lineLimit(1)
                        .help("\(session.title), \(sessionTime(session))")
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text(companion.isRefreshing ? "Checking the calendar…" : "The next schedule is not published yet.")
                    .font(Typeface.body).foregroundStyle(Palette.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var podium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Latest podium").font(Typeface.headline).foregroundStyle(Palette.paper)
                    .fixedSize()
                if let podium = companion.latestPodium {
                    Spacer(minLength: 0)
                    Text(podium.race.shortName)
                        .font(Typeface.caption).foregroundStyle(Palette.graphite).lineLimit(1)
                        .help("\(podium.race.name), \(podium.race.season)")
                }
            }
            if let podium = companion.latestPodium {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(podium.drivers, id: \.position) { driver in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(driver.position)")
                                .font(Typeface.headline).foregroundStyle(Palette.graphite)
                                .frame(width: 10, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(driver.name).font(Typeface.headline).foregroundStyle(Palette.paper)
                                Text(driver.team).font(Typeface.caption).foregroundStyle(Palette.graphite)
                            }
                            .lineLimit(1)
                        }
                        .help("\(driver.position). \(driver.name), \(driver.team)")
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("The podium appears after results are published.")
                    .font(Typeface.body).foregroundStyle(Palette.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sessionTime(_ session: F1Session) -> String {
        "\(session.dayLabel()) · \(session.timeLabel())"
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

import SwiftUI

/// One countdown at a time, ticking in the closed notch while it runs. Focus sessions are countdowns
/// that chain: 25 minutes of focus, then a 5 minute break, counting the sessions done.
@Observable @MainActor
final class Countdown {
    enum Finish { case timer, focusDone, breakOver }
    struct Focus: Equatable {
        var onBreak = false
        var completed = 0
    }

    static let focusMinutes: Double = 25
    static let breakMinutes: Double = 5

    private(set) var endsAt: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    /// Set while doing focus sessions; nil for a plain timer.
    private(set) var focus: Focus?
    @ObservationIgnored var onFinish: ((Finish) -> Void)?
    @ObservationIgnored private var finish: Task<Void, Never>?

    var isRunning: Bool { endsAt != nil }
    var isActive: Bool { endsAt != nil || pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    func start(minutes: Double) {
        focus = nil
        total = minutes * 60
        run(for: total)
    }

    func startFocus() {
        focus = Focus(onBreak: false, completed: focus?.completed ?? 0)
        total = Self.focusMinutes * 60
        run(for: total)
    }

    func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        self.endsAt = nil
        finish?.cancel()
    }

    func resume() {
        if let pausedRemaining { run(for: pausedRemaining) }
    }

    func addMinute() {
        total += 60
        if let endsAt { run(for: endsAt.timeIntervalSinceNow + 60) } else if let pausedRemaining { self.pausedRemaining = pausedRemaining + 60 }
    }

    func cancel() {
        finish?.cancel()
        endsAt = nil
        pausedRemaining = nil
        focus?.onBreak = false // keep the session count, drop the half-done one
    }

    /// A countdown reached zero. Focus rolls straight into its break; a break waits for you to start the next focus.
    func finished() {
        finish?.cancel()
        endsAt = nil
        pausedRemaining = nil
        guard var session = focus else {
            onFinish?(.timer)
            return
        }
        if session.onBreak {
            session.onBreak = false
            focus = session
            onFinish?(.breakOver)
        } else {
            session.completed += 1
            session.onBreak = true
            focus = session
            total = Self.breakMinutes * 60
            run(for: total)
            onFinish?(.focusDone)
        }
    }

    private func run(for seconds: TimeInterval) {
        pausedRemaining = nil
        endsAt = .now + seconds
        finish?.cancel()
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            finished()
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TimerView: View {
    let countdown: Countdown
    private static let presets: [Double] = [1, 5, 10, 15, 25, 45]

    var body: some View {
        if countdown.isActive {
            HStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let remaining = countdown.remaining(at: context.date)
                    VStack(alignment: .leading, spacing: 6) {
                        if let focus = countdown.focus {
                            Text(focus.onBreak ? "Break" : "Focus session \(focus.completed + 1)")
                                .font(Typeface.label)
                                .foregroundStyle(focus.onBreak ? .green : .orange)
                        }
                        Text(Countdown.format(remaining))
                            .font(Typeface.display)
                            .tracking(-1) // large digits read better slightly tighter
                            .foregroundStyle(countdown.isRunning ? Palette.paper : Palette.graphite)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(Motion.easeOut(0.25), value: Int(remaining))
                        Capsule()
                            .fill(Palette.rail)
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Capsule().fill(countdown.focus?.onBreak == true ? .green : .orange).frame(width: geometry.size.width * (countdown.total > 0 ? remaining / countdown.total : 0))
                                }
                            }
                            .frame(height: 4)
                    }
                }
                HStack(spacing: 2) {
                    IconButton(symbol: countdown.isRunning ? "pause-bold" : "play-bold", label: countdown.isRunning ? "Pause timer" : "Resume timer", size: 20) {
                        countdown.isRunning ? countdown.pause() : countdown.resume()
                    }
                    IconButton(symbol: "add-circle-linear", label: "Add a minute") { countdown.addMinute() }
                    IconButton(symbol: "close-circle-linear", label: "Cancel timer") { countdown.cancel() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Start a timer")
                        .font(Typeface.title)
                        .foregroundStyle(Palette.paper)
                    Spacer()
                    if let done = countdown.focus?.completed, done > 0 {
                        Text(done == 1 ? "1 focus session done" : "\(done) focus sessions done")
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.ash)
                    }
                }
                Button {
                    withAnimation(Motion.easeOut(0.2)) { countdown.startFocus() }
                } label: {
                    HStack(spacing: 6) {
                        Icon(name: "target-linear", size: 13)
                        Text("Focus \(Int(Countdown.focusMinutes)) min, then a \(Int(Countdown.breakMinutes)) min break")
                    }
                }
                .buttonStyle(PresetStyle())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button("\(Int(minutes)) min") { withAnimation(Motion.easeOut(0.2)) { countdown.start(minutes: minutes) } }
                            .buttonStyle(PresetStyle())
                    }
                }
            }
        }
    }
}

private struct PresetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.value)
            .foregroundStyle(Palette.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.rail))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.easeOut(0.16), value: configuration.isPressed)
    }
}

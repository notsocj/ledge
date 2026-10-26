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
                // The main thing this tab is for gets the big target; plain timers sit in one row under it.
                Button {
                    withAnimation(Motion.easeOut(0.2)) { countdown.startFocus() }
                } label: {
                    HStack(spacing: 12) {
                        Icon(name: "brain-linear", size: 17)
                            .foregroundStyle(.orange)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.orange.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start a focus session")
                                .font(Typeface.title)
                                .foregroundStyle(Palette.paper)
                            Text("\(Int(Countdown.focusMinutes)) minutes of focus, then a \(Int(Countdown.breakMinutes)) minute break")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.ash)
                        }
                        Spacer(minLength: 8)
                        if let done = countdown.focus?.completed, done > 0 {
                            Text(done == 1 ? "1 done today" : "\(done) done today")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.graphite)
                        }
                        Icon(name: "play-bold", size: 11)
                            .foregroundStyle(.black)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.paper))
                    }
                }
                .buttonStyle(CardStyle())
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button { withAnimation(Motion.easeOut(0.2)) { countdown.start(minutes: minutes) } } label: {
                            Text("\(Int(minutes)) min").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TintedStyle(height: 28))
                        .accessibilityLabel("Start a \(Int(minutes)) minute timer")
                    }
                }
            }
        }
    }
}

/// A whole row that's one button: a quiet well that brightens under the pointer and dips when pressed.
private struct CardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Card(configuration: configuration)
    }

    private struct Card: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.well, style: .continuous).fill(hovering ? Palette.rail : Palette.well))
                .contentShape(RoundedRectangle(cornerRadius: Radius.well, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.ease(0.15), value: hovering)
                .animation(Motion.easeOut(0.16), value: configuration.isPressed)
        }
    }
}

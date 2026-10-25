import SwiftUI

/// One countdown at a time, ticking in the closed notch while it runs.
@Observable @MainActor
final class Countdown {
    private(set) var endsAt: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finish: Task<Void, Never>?

    var isRunning: Bool { endsAt != nil }
    var isActive: Bool { endsAt != nil || pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
        return pausedRemaining ?? 0
    }

    func start(minutes: Double) {
        total = minutes * 60
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
    }

    private func run(for seconds: TimeInterval) {
        pausedRemaining = nil
        endsAt = .now + seconds
        finish?.cancel()
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            cancel()
            onFinish?()
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
                    VStack(alignment: .leading, spacing: 10) {
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
                                    Capsule().fill(.orange).frame(width: geometry.size.width * (countdown.total > 0 ? remaining / countdown.total : 0))
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
                Text("Start a timer")
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
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

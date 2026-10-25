import EventKit
import Foundation

/// A heads-up beside the notch two minutes before each meeting, once per meeting.
@MainActor
final class MeetingAlerts {
    static let leadTime: TimeInterval = 120

    var onBanner: ((Banner) -> Void)?
    private let agenda: Agenda
    private var timer: Timer?
    private var announced: Set<String> = []

    init(agenda: Agenda) {
        self.agenda = agenda
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        Task {
            await agenda.refreshIfAllowed() // never prompts; without calendar access there's nothing to announce
            for event in Self.startingSoon(agenda.week, at: .now) {
                let id = "\(event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)"
                guard !announced.contains(id) else { continue }
                announced.insert(id)
                onBanner?(.meeting(title: event.title ?? "Meeting", startsAt: event.startDate))
            }
        }
    }

    /// Timed events that start within the lead time.
    static func startingSoon(_ events: [EKEvent], at now: Date) -> [EKEvent] {
        events.filter { $0.startDate > now && $0.startDate.timeIntervalSince(now) <= leadTime }
    }
}

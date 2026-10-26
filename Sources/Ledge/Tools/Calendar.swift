import AppKit
import EventKit
import SwiftUI

/// This week's timed events, from every calendar the Mac's Calendar app knows about.
@Observable @MainActor
final class Agenda {
    enum Access { case unknown, denied, granted }

    private(set) var access = Access.unknown
    private(set) var week: [EKEvent] = []
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observing = false

    /// Asks for access when the user chooses to connect, so the prompt has context.
    func refresh() async {
        if access != .granted {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            guard granted else { return }
        }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.load() }
            }
        }
        load()
    }

    /// For places that shouldn't trigger the permission prompt.
    func refreshIfAllowed() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: await refresh()
        case .denied, .restricted: access = .denied
        default: break
        }
    }

    var weekDays: [Date] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// A day's events; for today, only the ones that haven't ended.
    func events(on day: Date) -> [EKEvent] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        let now = Date.now
        return week.filter { $0.startDate < interval.end && $0.endDate > interval.start && (!calendar.isDateInToday(day) || $0.endDate > now) }
    }

    private func load() {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return }
        week = store.events(matching: store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil))
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    /// The first Zoom, Google Meet, Teams or Webex link in an event's URL, location or notes.
    static func meetingLink(in text: String) -> URL? {
        let pattern = #"https://[^\s<>"]*(zoom\.us/j/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/)[^\s<>"]*"#
        return text.range(of: pattern, options: .regularExpression).flatMap { URL(string: String(text[$0])) }
    }

    static func meetingLink(for event: EKEvent) -> URL? {
        meetingLink(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " "))
    }
}

/// One event: its calendar's color, title, time, and Join when it has a meeting link.
struct EventLine: View {
    let event: EKEvent

    var body: some View {
        let happening = event.startDate <= .now && event.endDate > .now
        HStack(spacing: 8) {
            Capsule()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(Typeface.headline)
                    .foregroundStyle(Palette.paper)
                Text(happening ? "Now, until \(event.endDate.formatted(date: .omitted, time: .shortened))" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(Typeface.caption.monospacedDigit())
                    .foregroundStyle(happening ? Palette.paper : Palette.ash)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if let link = Agenda.meetingLink(for: event) {
                Button("Join") { NSWorkspace.shared.open(link) }
                    .buttonStyle(JoinStyle())
            }
        }
    }
}

struct JoinStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Palette.paper))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.easeOut(0.16), value: configuration.isPressed)
    }
}

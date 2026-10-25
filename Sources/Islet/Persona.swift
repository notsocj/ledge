import Foundation

/// What someone does. Each persona is a ranked list of tools, which decides what's switched on, the
/// tab order, what Home shows, and what wins the space beside the closed notch.
enum Persona: String, CaseIterable, Identifiable {
    case developer, designer, creator, student, professional, essentials

    /// Everyone gets these, whatever they do.
    static let basics: [Tool] = [.home, .volumeHUD, .alerts]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: "Developer"
        case .designer: "Designer"
        case .creator: "Creator"
        case .student: "Student"
        case .professional: "Professional"
        case .essentials: "Just the essentials"
        }
    }

    var blurb: String {
        switch self {
        case .developer: "AI usage limits, clipboard, notes and window snapping."
        case .designer: "A color picker, screenshots, and a shelf for assets."
        case .creator: "Music, timers, screenshots and a shelf for clips."
        case .student: "Timers, notes and your class calendar."
        case .professional: "Meeting countdowns, mic mute, world clock and notes."
        case .essentials: "Music, shelf, clipboard and calendar. Nothing more."
        }
    }

    var symbol: String {
        switch self {
        case .developer: "code-linear"
        case .designer: "pallete-2-linear"
        case .creator: "videocamera-record-linear"
        case .student: "square-academic-cap-linear"
        case .professional: "case-round-linear"
        case .essentials: "star-linear"
        }
    }

    /// Most important first. Tools left out are switched off for this persona.
    var ranking: [Tool] {
        switch self {
        case .developer: [.stats, .clipboard, .notes, .shelf, .calendar, .media, .timer, .windowSnapping, .keepAwake, .screenshot, .menuBarHider]
        case .designer: [.colorPicker, .shelf, .clipboard, .screenshot, .media, .notes, .calendar, .windowSnapping, .timer]
        case .creator: [.media, .timer, .shelf, .screenshot, .notes, .stats, .keepAwake, .micMute]
        case .student: [.timer, .notes, .calendar, .media, .clipboard, .keepAwake]
        case .professional: [.calendar, .meetingAlerts, .notes, .micMute, .worldClock, .clipboard, .timer, .shelf, .media, .keepAwake, .screenshot]
        case .essentials: [.media, .shelf, .clipboard, .calendar, .keepAwake, .timer]
        }
    }

    var homeWidgets: [HomeWidget] {
        switch self {
        case .student, .professional: [.week, .media]
        default: [.media, .week]
        }
    }

    var chips: [StatusChip] {
        switch self {
        case .developer: [.claude, .codex, .cpu, .clipboard, .shelf, .timer, .battery]
        case .designer: [.shelf, .clipboard, .battery, .timer]
        case .creator: [.timer, .shelf, .cpu, .battery]
        case .student: [.timer, .battery, .shelf]
        case .professional: [.clocks, .timer, .clipboard, .battery, .shelf]
        case .essentials: [.timer, .shelf, .clipboard, .battery]
        }
    }

    /// What shows beside the closed notch when both are live. Banners always come first.
    var closedOrder: [ClosedActivity] {
        switch self {
        case .creator, .essentials: [.media, .timer]
        default: [.timer, .media]
        }
    }
}

enum HomeWidget: Equatable { case media, week }
enum StatusChip: CaseIterable, Equatable { case timer, shelf, clipboard, battery, cpu, claude, codex, clocks }
enum ClosedActivity: Equatable { case timer, media }

/// Everything the island's arrangement depends on, worked out from the chosen personas.
struct Layout: Equatable {
    static let maxTabs = 7

    var tools: Set<Tool>
    var tabOrder: [Tool]
    var homeWidgets: [HomeWidget]
    var chips: [StatusChip]
    var closedOrder: [ClosedActivity]

    /// Before anyone picks a persona: everything on, in the original order.
    static let standard = Layout(tools: Set(Tool.allCases), tabOrder: Tool.tabs.filter { $0 != .colorPicker }, homeWidgets: [.media, .week],
                                 chips: StatusChip.allCases, closedOrder: [.timer, .media])

    /// Several personas merge: a tool is on if any of them wants it, and ranks as high as the persona
    /// that cares most about it. The first persona picked breaks ties and decides Home and the notch.
    static func merging(_ personas: [Persona]) -> Layout {
        guard let primary = personas.first else { return .standard }
        func rank<T: Equatable>(_ item: T, in lists: [[T]]) -> Int { lists.compactMap { $0.firstIndex(of: item) }.min() ?? .max }
        func ordered<T: Equatable>(_ items: [T], by lists: [[T]]) -> [T] {
            // Equal ranks go to the first persona's order, then to the order the items were given in.
            func key(_ item: T, _ offset: Int) -> (Int, Int, Int) { (rank(item, in: lists), rank(item, in: [lists[0]]), offset) }
            return items.enumerated().sorted { key($0.element, $0.offset) < key($1.element, $1.offset) }.map(\.element)
        }

        let rankings = personas.map(\.ranking)
        let tools = Set(Persona.basics + rankings.flatMap { $0 })
        let tabs = [Tool.home] + ordered(Tool.tabs.filter { $0 != .home && tools.contains($0) }, by: rankings)
        let widgets = personas.flatMap(\.homeWidgets).reduce(into: [HomeWidget]()) { if !$0.contains($1) { $0.append($1) } }
        let chipLists = personas.map(\.chips)
        let chips = ordered(StatusChip.allCases.filter { chip in chipLists.contains { $0.contains(chip) } }, by: chipLists)
        return Layout(tools: tools, tabOrder: Array(tabs.prefix(maxTabs)), homeWidgets: widgets, chips: chips, closedOrder: primary.closedOrder)
    }
}

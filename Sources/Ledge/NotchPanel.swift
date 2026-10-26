import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // Borderless windows still get pushed below the menu bar; the island has to sit over it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A short-lived message beside the closed notch, like the iPhone's Dynamic Island.
enum Banner: Equatable {
    case level(symbol: String, value: Double)
    case battery(percent: Int, charging: Bool)
    case headphones(name: String, battery: Int?)
    case screenshot(NSImage)
    case message(symbol: String, text: String)
    case color(hex: String)
    case meeting(title: String, startsAt: Date)
    case mic(muted: Bool)
    case agent(name: String, waiting: Bool, project: String)
}

@Observable @MainActor
final class NotchModel {
    static let width: CGFloat = 560
    static let maxHeight: CGFloat = 330
    /// Space above and below a tab's content inside the open island.
    static let contentInsets = (top: CGFloat(8), bottom: CGFloat(14))

    var expanded = false
    var notchSize = CGSize(width: 180, height: 32)
    var tab: Tool = .home { didSet { onResize?() } }
    /// Each tab's measured content height, so the island fits what it shows and reopening doesn't resize again.
    var contentHeights: [Tool: CGFloat] = [:] { didSet { onResize?() } }
    /// Set while first-run setup runs inside the island; the island stays open until it's done.
    var onboarding: Onboarding? { didSet { onResize?() } }
    /// Once the trial is over the island shows only how to buy, in place of the tabs.
    var locked = false { didSet { onResize?() } }
    /// The measured height of setup or the trial-ended page, whichever is showing.
    var pageHeight: CGFloat = 200 { didSet { onResize?() } }
    /// A drag carrying files, anywhere on screen. `.far` hints at the notch; `.near` has opened the shelf to catch it.
    var fileDrag: FileDrag?
    @ObservationIgnored var onResize: (() -> Void)?

    var expandedSize: CGSize {
        let content = onboarding != nil || locked ? pageHeight : contentHeights[tab] ?? 120
        return CGSize(width: Self.width, height: min(Self.maxHeight, notchSize.height + Self.contentInsets.top + content + Self.contentInsets.bottom))
    }
    private(set) var banner: Banner?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    func tabs(in preferences: Preferences) -> [Tool] { preferences.layout.tabOrder.filter(preferences.isOn) }

    func show(_ banner: Banner, seconds: Double = 2) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : Motion.open) { self.banner = banner }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : Motion.close) { self?.banner = nil }
        }
    }
}

enum FileDrag { case far, near }

/// Owns the island window and every tool. The window is a fixed, expanded-size panel pinned to the
/// top center of the notched screen; it ignores the mouse while closed so the menu bar under its
/// clear area stays clickable.
@MainActor
final class NotchController {
    let model = NotchModel()
    let preferences = Preferences.shared
    let license = License.shared
    let nowPlaying = NowPlaying()
    let usage = Usage()
    let shelf = Shelf()
    let clipboard = ClipboardHistory()
    let keepAwake = KeepAwake()
    let agenda = Agenda()
    let countdown = Countdown()
    let colorPicker = ColorPicker()
    let worldClock = WorldClock.shared
    let microphone = Microphone()
    let audioOutputs = AudioOutputs()
    let ports = Ports()
    let inUse = InUse()
    let agents = AgentAlerts.shared
    private lazy var meetingAlerts = MeetingAlerts(agenda: agenda)
    let notes = Notes()
    let stats = SystemStats()
    private let mediaKeys = MediaKeys()
    private let alerts = Alerts()
    private let snapper = WindowSnapper()
    private let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var mouseMonitor: Any?
    private var pendingOpen: Task<Void, Never>?
    private var pendingClose: Task<Void, Never>?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var dragChangeCount = 0
    private var checkedDragCount = -1 // the drag pasteboard generation already looked at, so it's read once per drag
    private var dragWatch: Task<Void, Never>?
    private var lastMove: (point: NSPoint, time: TimeInterval)?
    private var speed: CGFloat = 0 // pointer speed in points per second, smoothed

    /// In the order your personas rank them; the first `leftTabCount` go left of the notch.
    var tabs: [Tool] { preferences.layout.tabOrder.filter(preferences.isOn) }
    var leftTabs: [Tool] { Array(tabs.prefix(Tool.leftTabCount)) }
    var rightTabs: [Tool] { Array(tabs.dropFirst(Tool.leftTabCount)) }

    init() {
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        model.onResize = { [weak self] in self?.fitPanel() }
        let host = NSHostingView(rootView: NotchView(app: self))
        host.sizingOptions = [] // the panel frame is ours; don't let SwiftUI resize it
        panel.contentView = host
        layout()
        if Snapshots.folder == nil { panel.orderFrontRegardless() } // snapshots render off-screen instead

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // Global monitors only see events aimed at other apps: exactly when the cursor is outside our
        // panel, or over it while it ignores the mouse. That covers both entering and leaving.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }

        let show: (Banner) -> Void = { [weak self] in self?.model.show($0) }
        mediaKeys.onChange = show
        alerts.onBanner = { [weak self] in self?.model.show($0, seconds: 3) }
        countdown.onFinish = { [weak self] finish in
            NSSound(named: "Glass")?.play()
            let banner: Banner = switch finish {
            case .timer: .message(symbol: "stopwatch-bold", text: "Time's up")
            case .focusDone: .message(symbol: "leaf-linear", text: "Break time")
            case .breakOver: .message(symbol: "brain-linear", text: "Back to focus")
            }
            self?.model.show(banner, seconds: 4)
        }
        colorPicker.onPicked = { [weak self] in self?.model.show(.color(hex: $0), seconds: 2.5) }
        microphone.onChange = { [weak self] in self?.model.show(.mic(muted: $0)) }
        meetingAlerts.onBanner = { [weak self] in self?.model.show($0, seconds: 8) }
        audioOutputs.onSwitch = { [weak self] in self?.model.show(.message(symbol: "speaker-minimalistic-linear", text: $0), seconds: 2.5) }
        preferences.onChange = { [weak self] tool, on in self?.apply(tool, on: on) }
        license.onChange = { [weak self] in self?.applyLicense() }
        model.locked = !license.unlocked
        for tool in Tool.allCases { apply(tool, on: preferences.isOn(tool)) }
        if let folder = Snapshots.folder {
            Task { await Snapshots.run(self, into: folder) }
            return
        }
        waitForAccessibility()

        NotificationCenter.default.addObserver(forName: .startOnboarding, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startOnboarding() }
        }
        if !preferences.onboarded {
            // First launch: let the menu bar settle, then grow the island out of the notch to say hello.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startOnboarding()
            }
        } else if case .trial(let days) = license.state, days <= 2 {
            model.show(.message(symbol: "ledge-mark", text: days == 1 ? "Last trial day" : "2 days left"), seconds: 4)
        }
    }

    // MARK: Setup

    func startOnboarding() {
        let flow = Onboarding()
        flow.personas = preferences.personas
        flow.tools = Set(Tool.allCases.filter(preferences.isOn))
        withAnimation(Motion.snappy) { model.onboarding = flow }
        if !model.expanded { setExpanded(true) }
    }

    /// Applies the picked personas and tools, so services start (and ask for permissions) before the permissions step.
    func applyOnboardingChoices() {
        guard let flow = model.onboarding else { return }
        preferences.choose(flow.personas)
        for tool in Tool.allCases where tool != .home && preferences.isOn(tool) != flow.tools.contains(tool) {
            preferences.set(tool, on: flow.tools.contains(tool))
        }
        if !model.tabs(in: preferences).contains(model.tab) { model.tab = .home }
    }

    func finishOnboarding() {
        preferences.onboarded = true
        setExpanded(false)
        model.onboarding = nil
        model.show(.message(symbol: "ledge-mark", text: "Hover here"), seconds: 3) // where to find it from now on
    }

    func measuredPage(_ height: CGFloat) {
        guard abs(model.pageHeight - height) > 0.5 else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : Motion.snappy) { model.pageHeight = height }
    }

    /// The trial ended, or a key was activated or removed: stop or start every tool to match.
    private func applyLicense() {
        model.locked = !license.unlocked
        for tool in Tool.allCases { apply(tool, on: preferences.isOn(tool)) }
    }

    func quit() {
        nowPlaying.stop()
        notes.save()
        keepAwake.off()
    }

    func open(_ tab: Tool) {
        model.tab = tab
        if !model.expanded { setExpanded(true) }
    }

    /// `ledge://agent/<claude|codex>/<done|waiting>?project=<folder>`, sent by the agent alert script.
    func open(_ url: URL) {
        guard url.scheme == "ledge", url.host == "agent", preferences.isOn(.agentAlerts), license.unlocked else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, let agent = AgentAlerts.Agent(rawValue: parts[0]) else { return }
        let waiting = parts[1] == "waiting"
        let project = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "project" }?.value ?? ""
        NSSound(named: waiting ? "Tink" : "Pop")?.play()
        model.show(.agent(name: agent == .claude ? "Claude" : "Codex", waiting: waiting, project: project), seconds: waiting ? 10 : 6)
    }

    func pickColor() {
        setExpanded(false) // keep the island out of the way of what you're sampling
        colorPicker.pick()
    }

    func takeScreenshot() {
        setExpanded(false) // keep the island out of the shot
        Screenshot.capture { [weak self] url in
            guard let self, let image = NSImage(contentsOf: url) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            if preferences.isOn(.shelf) { shelf.add([url]) }
            model.show(.screenshot(image), seconds: 3)
        }
    }

    private func apply(_ tool: Tool, on wanted: Bool) {
        let on = wanted && license.unlocked
        switch tool {
        case .media: if on, Snapshots.folder == nil { nowPlaying.start() } // keeps streaming until relaunch once on; it's cheap. Snapshots use demo music.
        case .clipboard: on ? clipboard.start() : clipboard.stop()
        case .keepAwake: if !on { keepAwake.off() }
        case .volumeHUD: on ? mediaKeys.start() : mediaKeys.stop()
        case .alerts: on ? alerts.start() : alerts.stop()
        case .windowSnapping: on ? snapper.start() : snapper.stop()
        case .screenshot:
            if on {
                HotKeys.register(10, key: kVK_ANSI_S, modifiers: controlKey | optionKey) { [weak self] in self?.takeScreenshot() }
            } else {
                HotKeys.unregister(10)
            }
        case .colorPicker:
            if on {
                HotKeys.register(11, key: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in self?.pickColor() }
            } else {
                HotKeys.unregister(11)
            }
        case .micMute:
            if on {
                microphone.start()
                HotKeys.register(12, key: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in self?.microphone.toggle() }
            } else {
                microphone.stop()
                HotKeys.unregister(12)
            }
        case .meetingAlerts: on ? meetingAlerts.start() : meetingAlerts.stop()
        case .inUse: on ? inUse.start() : inUse.stop()
        case .audioOutput: if on { audioOutputs.refresh() }
        case .ports, .agentAlerts: break // ports scan while their tab is open; agent links arrive by URL
        case .home, .shelf, .calendar, .timer, .notes, .stats, .menuBarHider, .worldClock: break // nothing to start or stop
        }
        if !on, model.tab == tool { model.tab = tabs.first ?? .media }
    }

    /// Accessibility tools can't start until the user allows it, which happens outside the app.
    private func waitForAccessibility() {
        let needed = Tool.allCases.filter { $0.needsAccessibility && preferences.isOn($0) }
        guard !needed.isEmpty, !AXIsProcessTrusted() else { return }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Task { [weak self] in
            while !AXIsProcessTrusted() { try? await Task.sleep(for: .seconds(2)) }
            guard let self else { return }
            for tool in needed where preferences.isOn(tool) { apply(tool, on: true) }
        }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchSize = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            model.notchSize = CGSize(width: 180, height: NSStatusBar.system.thickness) // no notch: draw a pill instead
        }
        setPanelHeight(model.expandedSize.height)
    }

    private var pendingShrink: Task<Void, Never>?

    /// The window follows the island: it grows at once so nothing is clipped, and shrinks only after
    /// the island's spring has settled, so empty window never keeps the island open under the cursor.
    private func fitPanel() {
        let target = model.expandedSize.height
        pendingShrink?.cancel()
        if target >= panel.frame.height {
            setPanelHeight(target)
        } else {
            pendingShrink = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, !Task.isCancelled else { return }
                setPanelHeight(model.expandedSize.height)
            }
        }
    }

    private func setPanelHeight(_ height: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - NotchModel.width / 2, y: frame.maxY - height, width: NotchModel.width, height: height), display: true)
    }

    /// Called by the view with each tab's natural content height.
    func measured(_ heights: [Tool: CGFloat]) {
        var updated = model.contentHeights
        for (tab, height) in heights where abs((updated[tab] ?? 0) - height) > 0.5 { updated[tab] = height }
        guard updated != model.contentHeights else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion || !model.expanded ? nil : Motion.snappy) { model.contentHeights = updated }
    }

    private func handle(_ event: NSEvent) {
        guard Snapshots.folder == nil else { return } // the snapshot renderer drives the island itself
        let point = NSEvent.mouseLocation
        // Most moves happen nowhere near the notch: drop them before doing any work.
        if event.type == .mouseMoved, !model.expanded, model.fileDrag == nil, point.y < panel.frame.maxY - 200 {
            if pendingOpen != nil { pendingOpen?.cancel(); pendingOpen = nil }
            lastMove = nil
            return
        }
        track(point, at: event.timestamp)
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = dragPasteboard.changeCount
            if snapping { snapper.mouseDown() }
        case .leftMouseDragged:
            if snapping { snapper.mouseDragged() }
            followFileDrag(to: point)
        case .leftMouseUp:
            if snapping { snapper.mouseUp() }
            if model.fileDrag != nil { endFileDrag() }
        default:
            break
        }
        guard model.fileDrag == nil else { return } // a file drag has its own open and close rules
        if model.expanded {
            guard model.onboarding == nil, !keepOpenZone.contains(point) else { return }
            // Leaving decisively closes at once; slipping just past the edge gets a moment's grace.
            if !panel.frame.insetBy(dx: -90, dy: -90).contains(point) { setExpanded(false) } else { scheduleClose() }
        } else if event.type == .mouseMoved {
            considerOpening(at: point)
        }
    }

    private var snapping: Bool { preferences.isOn(.windowSnapping) && license.unlocked }

    /// The closed notch, widened a little and extended past the top edge where the cursor rests.
    private var hotZone: NSRect {
        let frame = panel.frame, notch = model.notchSize
        return NSRect(x: frame.midX - notch.width / 2 - 14, y: frame.maxY - notch.height, width: notch.width + 28, height: notch.height + 2)
    }

    /// The open island plus a small margin, so a pointer resting on its edge doesn't flicker it shut.
    private var keepOpenZone: NSRect { panel.frame.insetBy(dx: -14, dy: -14) }

    /// Where a dragged file counts as "heading for the notch": a generous area under it.
    private var dropZone: NSRect {
        let frame = panel.frame
        return NSRect(x: frame.midX - 320, y: frame.maxY - 200, width: 640, height: 200)
    }

    // MARK: Hover

    private func track(_ point: NSPoint, at time: TimeInterval) {
        if let last = lastMove, time > last.time {
            let instant = hypot(point.x - last.point.x, point.y - last.point.y) / CGFloat(time - last.time)
            speed = speed * 0.6 + instant * 0.4
        }
        lastMove = (point, time)
    }

    /// The pointer's speed now: a pointer that has stopped sends no events, so a stale reading means it's at rest.
    private var currentSpeed: CGFloat {
        guard let last = lastMove, ProcessInfo.processInfo.systemUptime - last.time < 0.06 else { return 0 }
        return speed
    }

    /// Opens on intent: a brief rest over the notch, or a push against the top edge. A pointer sweeping
    /// along the menu bar passes over without setting it off.
    private func considerOpening(at point: NSPoint) {
        guard hotZone.contains(point) else {
            if pendingOpen != nil { pendingOpen?.cancel(); pendingOpen = nil }
            return
        }
        if point.y >= panel.frame.maxY - 1, currentSpeed < 2400 {
            pendingOpen?.cancel(); pendingOpen = nil
            setExpanded(true)
            return
        }
        guard pendingOpen == nil else { return }
        pendingOpen = Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(55))
                guard let self, !Task.isCancelled else { return }
                guard hotZone.contains(NSEvent.mouseLocation) else { pendingOpen = nil; return }
                if currentSpeed < 650 { pendingOpen = nil; setExpanded(true); return }
            }
            self?.pendingOpen = nil
        }
    }

    private func scheduleClose() {
        guard pendingClose == nil else { return }
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(170))
            guard let self, !Task.isCancelled else { return }
            pendingClose = nil
            if model.expanded, model.onboarding == nil, model.fileDrag == nil, !keepOpenZone.contains(NSEvent.mouseLocation) {
                setExpanded(false)
            }
        }
    }

    // MARK: File drags

    /// Notices a drag carrying files anywhere on screen, hints at the notch, and opens the shelf as the
    /// drag comes near, so it's there to catch the drop without having to aim for the notch itself.
    private func followFileDrag(to point: NSPoint) {
        guard preferences.isOn(.shelf), license.unlocked else { return }
        if model.fileDrag == nil {
            let count = dragPasteboard.changeCount
            guard count != dragChangeCount, count != checkedDragCount else { return }
            checkedDragCount = count
            guard dragPasteboard.types?.contains(.fileURL) == true else { return }
            startFileDrag()
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if dropZone.contains(point), model.fileDrag != .near {
            withAnimation(reduceMotion ? nil : Motion.snappy) { model.fileDrag = .near }
            open(.shelf)
        } else if model.fileDrag == .near, !dropZone.insetBy(dx: -50, dy: -50).contains(point) {
            // Changed its mind: back to the hint, a little way out so the edge doesn't flicker.
            withAnimation(reduceMotion ? nil : Motion.snappy) { model.fileDrag = .far }
            setExpanded(false)
        }
    }

    private func startFileDrag() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : Motion.open) { model.fileDrag = .far }
        // A drop on another app may not reach our monitor, so the drag also ends when the button lifts.
        dragWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.endFileDrag(); return }
            }
        }
    }

    private func endFileDrag() {
        dragWatch?.cancel()
        dragWatch = nil
        guard model.fileDrag != nil else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : Motion.close) { model.fileDrag = nil }
        // Dropped on the shelf: it stays open to show what landed. Dropped anywhere else: it closes.
        if model.expanded, !keepOpenZone.contains(NSEvent.mouseLocation) { setExpanded(false) }
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded { pendingClose?.cancel(); pendingClose = nil } else { pendingOpen?.cancel(); pendingOpen = nil }
        panel.ignoresMouseEvents = !expanded
        if expanded, !preferences.isOn(model.tab) { model.tab = tabs.first ?? .media }
        // Reduce Motion: the island snaps between states instead of morphing.
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : expanded ? Motion.open : Motion.close
        withAnimation(animation) { model.expanded = expanded }
    }
}

import Foundation

/// A small in-memory queue. Display time pauses while the island is open, but freshness never does.
/// The caller supplies time so expiry, replacement and interruption can be checked without sleeps.
struct NotificationQueue {
    struct Entry {
        let id: Int
        let banner: Banner
        let key: String
        let priority: Int
        let expiresAt: Date
        var remaining: TimeInterval
        var visibleUntil: Date?
        var hasPresented = false
    }

    private struct Recent {
        let banner: Banner
        let expiresAt: Date
        let order: Int
    }

    private(set) var current: Entry?
    private(set) var pending: [Entry] = []
    private(set) var suspended = false
    private var recent: [String: Recent] = [:]
    private var sequence = 0
    static let capacity = 4

    var banner: Banner? { current?.banner }
    var nextDeadline: Date? {
        ([current?.visibleUntil, current?.expiresAt].compactMap { $0 }
         + pending.map(\.expiresAt)).min()
    }

    /// Returns only a newly delivered alert, never a duplicate or a resumed presentation.
    mutating func submit(_ banner: Banner, seconds: TimeInterval, at now: Date, allowRepeat: Bool = false) -> Banner? {
        advance(at: now)
        let duration = seconds.isFinite ? min(300, max(0, seconds)) : 2
        let policy = banner.queuePolicy
        let expiry = min(now.addingTimeInterval(max(duration, policy.freshness)), policy.latestDelivery ?? .distantFuture)
        guard expiry > now else { return delivered() }

        if banner.isImmediateFeedback {
            // Repeated key presses may refresh their feedback, but it must never replay later.
            guard !suspended else { return delivered() }
            parkCurrent(at: now)
            sequence += 1
            current = Entry(id: sequence, banner: banner, key: policy.key, priority: 100,
                            expiresAt: expiry, remaining: duration, visibleUntil: now.addingTimeInterval(duration))
            return delivered()
        }

        if !allowRepeat, let previous = recent[policy.key], previous.banner == banner {
            return delivered()
        }
        sequence += 1
        recent[policy.key] = Recent(banner: banner, expiresAt: expiry, order: sequence)
        if recent.count > 32, let oldest = recent.min(by: { $0.value.order < $1.value.order })?.key {
            recent.removeValue(forKey: oldest)
        }
        let entry = Entry(id: sequence, banner: banner, key: policy.key, priority: policy.priority,
                          expiresAt: expiry, remaining: duration)
        pending.removeAll { $0.key == policy.key }

        if suspended {
            enqueue(entry, at: now)
        } else if current?.key == policy.key {
            // A later state resolves the older one. If it lowers urgency, already-waiting
            // attention alerts take precedence over this source's new completion message.
            current = nil
            if duration == 0 {
                current = entry
                current?.visibleUntil = now
            } else {
                enqueue(entry, at: now)
                advance(at: now)
            }
        } else if current == nil || policy.priority > current!.priority {
            parkCurrent(at: now)
            current = entry
            current?.visibleUntil = now.addingTimeInterval(duration)
        } else {
            enqueue(entry, at: now)
        }
        return delivered()
    }

    mutating func remove(where matches: (Banner) -> Bool, at now: Date) -> Banner? {
        if let current, matches(current.banner) { self.current = nil }
        pending.removeAll { matches($0.banner) }
        recent = recent.filter { !matches($0.value.banner) }
        advance(at: now)
        return delivered()
    }

    mutating func tick(at now: Date) -> Banner? {
        advance(at: now)
        return delivered()
    }

    mutating func setSuspended(_ suspended: Bool, at now: Date) -> Banner? {
        advance(at: now)
        if suspended != self.suspended {
            self.suspended = suspended
            if suspended { parkCurrent(at: now) }
            else { advance(at: now) }
        }
        return delivered()
    }

    private mutating func advance(at now: Date) {
        recent = recent.filter { $0.value.expiresAt > now }
        pending.removeAll { $0.expiresAt <= now || $0.remaining <= 0 }
        if let current, current.expiresAt <= now || (current.visibleUntil ?? .distantFuture) <= now {
            self.current = nil
        }
        guard !suspended, current == nil, !pending.isEmpty else { return }
        pending.sort { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
        var next = pending.removeFirst()
        next.visibleUntil = min(now.addingTimeInterval(next.remaining), next.expiresAt)
        current = next
    }

    private mutating func parkCurrent(at now: Date) {
        guard var entry = current else { return }
        current = nil
        guard !entry.banner.isImmediateFeedback else { return }
        entry.remaining = max(0, (entry.visibleUntil ?? now).timeIntervalSince(now))
        entry.visibleUntil = nil
        enqueue(entry, at: now)
    }

    private mutating func enqueue(_ entry: Entry, at now: Date) {
        guard entry.remaining > 0, entry.expiresAt > now else { return }
        pending.append(entry)
        if pending.count > Self.capacity {
            let lowest = pending.indices.min {
                pending[$0].priority == pending[$1].priority
                    ? pending[$0].id < pending[$1].id : pending[$0].priority < pending[$1].priority
            }!
            pending.remove(at: lowest)
        }
    }

    private mutating func delivered() -> Banner? {
        guard current?.hasPresented == false else { return nil }
        current?.hasPresented = true
        return current?.banner
    }
}

extension Banner {
    struct QueuePolicy {
        let key: String
        let priority: Int
        let latestDelivery: Date?
        var freshness: TimeInterval { priority >= 30 ? 30 : priority >= 20 ? 20 : 15 }
    }

    var queuePolicy: QueuePolicy {
        switch self {
        case .agent(let name, let waiting, let project):
            let context = project.trimmingCharacters(in: .whitespacesAndNewlines)
            return QueuePolicy(key: "agent:\(name):\(context)", priority: waiting ? 30 : 20, latestDelivery: nil)
        case .meeting(let title, let startsAt):
            return QueuePolicy(key: "meeting:\(title):\(startsAt.timeIntervalSinceReferenceDate)", priority: 30,
                               latestDelivery: startsAt.addingTimeInterval(30))
        case .battery(let percent, let charging):
            return QueuePolicy(key: "battery", priority: !charging && percent <= 20 ? 20 : 10, latestDelivery: nil)
        case .headphones(let name, _):
            return QueuePolicy(key: "headphones:\(name)", priority: 10, latestDelivery: nil)
        case .message(let symbol, _):
            let timer = ["stopwatch-bold", "leaf-linear", "brain-linear"].contains(symbol)
            return QueuePolicy(key: timer ? "timer" : "message:\(symbol)", priority: timer ? 30 : 10, latestDelivery: nil)
        case .level(let symbol, _):
            return QueuePolicy(key: "level:\(symbol)", priority: 100, latestDelivery: nil)
        case .mic:
            return QueuePolicy(key: "microphone", priority: 100, latestDelivery: nil)
        case .screenshot:
            return QueuePolicy(key: "screenshot", priority: 100, latestDelivery: nil)
        case .color:
            return QueuePolicy(key: "color", priority: 100, latestDelivery: nil)
        }
    }

    /// Source ownership is independent of display text, allowing a disabled tool to purge
    /// its alerts without disturbing other tools or the built-in notification preview.
    var sourceTool: Tool? {
        switch self {
        case .agent: return .agentAlerts
        case .meeting: return .meetingAlerts
        case .battery, .headphones: return .alerts
        case .level: return .volumeHUD
        case .mic: return .micMute
        case .screenshot: return .screenshot
        case .color: return .colorPicker
        case .message(let symbol, _):
            if ["stopwatch-bold", "leaf-linear", "brain-linear"].contains(symbol) { return .timer }
            return symbol == "speaker-minimalistic-linear" ? .audioOutput : nil
        }
    }

    /// Sounds belong to delivery, so queued, suppressed and duplicate events stay quiet.
    var notificationSound: String? {
        switch self {
        case .agent(_, let waiting, _): return waiting ? "Tink" : "Pop"
        case .message(let symbol, let text):
            if ["stopwatch-bold", "leaf-linear", "brain-linear"].contains(symbol) { return "Glass" }
            return symbol == "ledge-mark" && text == "Notification preview" ? "Pop" : nil
        default: return nil
        }
    }
}

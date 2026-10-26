import AppKit
import Security
import SwiftUI

/// The 7-day trial, then a Lemon Squeezy license key good for two Macs. Lemon Squeezy's license
/// API needs no secret, so the app talks to it directly and there's no server of our own.
@Observable @MainActor
final class License {
    static let shared = License()
    static let trialDays = 7
    // shortcut: 0 accepts a key from any Lemon Squeezy store; set both from the dashboard before selling.
    static let storeID = 0
    static let productID = 0
    // Replace with the product's checkout link from Lemon Squeezy (Products › Share).
    static let buyURL = URL(string: "https://kestrel.lemonsqueezy.com/buy")!

    enum State: Equatable { case trial(daysLeft: Int), expired, licensed }

    private(set) var state = State.licensed
    var unlocked: Bool { state != .expired }
    var licensed: Bool { state == .licensed }
    /// Called when the app locks or unlocks, so tools can stop or start.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var trialStart = Date.now
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var instance: String?

    private init() {
        guard Snapshots.folder == nil else { return } // renders show the full app
        key = Keychain.read("licenseKey")
        instance = Keychain.read("instance")
        // Kept in both places, earliest wins: deleting the app's preferences doesn't restart the trial.
        let saved = [Keychain.read("trialStart").flatMap(Double.init), UserDefaults.standard.object(forKey: "trialStart") as? Double]
        trialStart = saved.compactMap { $0 }.min().map(Date.init(timeIntervalSince1970:)) ?? .now
        Keychain.write("trialStart", String(trialStart.timeIntervalSince1970))
        UserDefaults.standard.set(trialStart.timeIntervalSince1970, forKey: "trialStart")
        refresh()
        Task { [weak self] in
            await self?.check()
            while !Task.isCancelled { // so the trial ends on time while Kestrel keeps running
                try? await Task.sleep(for: .seconds(3600))
                self?.refresh()
            }
        }
    }

    nonisolated static func state(trialStart: Date, now: Date, licensed: Bool) -> State {
        if licensed { return .licensed }
        let daysUsed = max(0, now.timeIntervalSince(trialStart)) / 86_400 // a clock set back doesn't add days
        let left = Double(trialDays) - daysUsed
        return left <= 0 ? .expired : .trial(daysLeft: Int(left.rounded(.up)))
    }

    /// Activates this Mac. Returns what went wrong, or nil once it's licensed.
    func activate(_ input: String) async -> String? {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Paste the license key from your receipt email." }
        let name = Host.current().localizedName ?? "Mac"
        guard let response = await Self.post("activate", ["license_key": key, "instance_name": name]) else { return Self.offline }
        guard response.activated == true, let instance = response.instance?.id else {
            if response.error?.contains("not found") == true { return "That key wasn't found. Check it against your receipt email." }
            return response.error ?? "That key didn't work."
        }
        guard Self.isOurs(response.meta, store: Self.storeID, product: Self.productID) else {
            _ = await Self.post("deactivate", ["license_key": key, "instance_id": instance]) // don't use up the other product's slot
            return "That key is for a different app."
        }
        save(key: key, instance: instance)
        return nil
    }

    /// Frees this Mac's slot so the key can be used on another one.
    func deactivate() async -> String? {
        guard let key, let instance else { save(key: nil, instance: nil); return nil }
        guard let response = await Self.post("deactivate", ["license_key": key, "instance_id": instance]) else { return Self.offline }
        guard response.deactivated == true else { return response.error ?? "Couldn't deactivate this Mac." }
        save(key: nil, instance: nil)
        return nil
    }

    /// A refunded or disabled key stops working. Offline, a licensed Mac stays licensed.
    private func check() async {
        guard let key, let instance else { return }
        let response = await Self.post("validate", ["license_key": key, "instance_id": instance])
        if response?.valid == false { save(key: nil, instance: nil) }
    }

    private func save(key: String?, instance: String?) {
        (self.key, self.instance) = (key, instance)
        Keychain.write("licenseKey", key)
        Keychain.write("instance", instance)
        refresh()
    }

    private func refresh() {
        let new = Self.state(trialStart: trialStart, now: .now, licensed: instance != nil)
        guard new != state else { return }
        let wasUnlocked = unlocked
        state = new
        if unlocked != wasUnlocked { onChange?() }
    }

    // MARK: Lemon Squeezy

    struct Response: Decodable {
        var activated: Bool?
        var valid: Bool?
        var deactivated: Bool?
        var error: String?
        var instance: Instance?
        var meta: Meta?
        struct Instance: Decodable { var id: String }
        struct Meta: Decodable { var storeId: Int; var productId: Int }
    }

    nonisolated static func isOurs(_ meta: Response.Meta?, store: Int, product: Int) -> Bool {
        guard let meta else { return false }
        return (store == 0 || meta.storeId == store) && (product == 0 || meta.productId == product)
    }

    nonisolated static func decode(_ data: Data) -> Response? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Response.self, from: data)
    }

    private static let offline = "Couldn't reach the license server. Check your connection and try again."

    /// nil when the server couldn't be reached. Errors (a wrong key, the limit reached) come back as
    /// a 4xx with the same JSON shape, so the body is read whatever the status.
    private static func post(_ action: String, _ fields: [String: String]) async -> Response? {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(action)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // A form body reads "+" as a space, which URLComponents leaves alone.
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return decode(data)
    }
}

/// Generic passwords in the login keychain: they survive deleting the app, unlike its preferences.
private enum Keychain {
    private static let service = "com.kestrel.Kestrel"

    static func read(_ account: String) -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ account: String, _ value: String?) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var item = query
        item[kSecValueData] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

// MARK: Views

/// Shown in the open island once the trial is over, in place of the tabs.
struct TrialEndedView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Your free week is up")
                    .font(Typeface.heading)
                    .foregroundStyle(Palette.paper)
                Text("Buy Kestrel once to keep using it on this Mac and one more. Everything you set up is still here.")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.graphite)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            HStack(spacing: 10) {
                Button("Enter license key") {
                    NSApp.activate()
                    openSettings()
                }
                .buttonStyle(SecondaryStyle())
                Button("Buy Kestrel, $19.99") { NSWorkspace.shared.open(License.buyURL) }
                    .buttonStyle(PrimaryStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// The License section at the top of Settings.
struct LicenseSettings: View {
    let license: License
    @State private var key = ""
    @State private var working = false
    @State private var problem: String?
    @State private var confirmDeactivate = false

    var body: some View {
        Section {
            if license.licensed {
                LabeledContent("Kestrel", value: "Licensed on this Mac")
                Button("Deactivate on this Mac…") { confirmDeactivate = true }
                    .disabled(working)
                    .confirmationDialog("Deactivate Kestrel on this Mac?", isPresented: $confirmDeactivate) {
                        Button("Deactivate") { run { await license.deactivate() } }
                    } message: {
                        Text("This frees one of your key's two Macs. You'll need the key from your receipt email to activate again.")
                    }
            } else {
                LabeledContent("Kestrel", value: status)
                HStack {
                    TextField("License key", text: $key, prompt: Text("Paste the key from your receipt"))
                        .labelsHidden()
                        .onSubmit { activate() }
                    Button(working ? "Activating…" : "Activate", action: activate)
                        .disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Buy Kestrel, $19.99", destination: License.buyURL)
            }
        } header: {
            Text("License")
        } footer: {
            if let problem {
                Text(problem).foregroundStyle(.red)
            } else if !license.licensed {
                Text("One key works on two Macs, with every 1.x update.").foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        switch license.state {
        case .trial(let days): days == 1 ? "Free trial, last day" : "Free trial, \(days) days left"
        case .expired: "Free trial ended"
        case .licensed: "Licensed on this Mac"
        }
    }

    private func activate() {
        run {
            let problem = await license.activate(key)
            if problem == nil { key = "" }
            return problem
        }
    }

    private func run(_ action: @escaping () async -> String?) {
        working = true
        problem = nil
        Task {
            problem = await action()
            working = false
        }
    }
}

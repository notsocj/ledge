import AppKit
import Security
import SwiftUI

/// The 7-day trial, then a Polar license key good for two Macs. Polar's customer-portal license API
/// needs no secret, so the app talks to it directly and there's no server of our own.
@Observable @MainActor
final class License {
    static let shared = License()
    nonisolated static let trialDays = 7
    // From the Polar dashboard: the organization ID (Settings › General) and, if you sell more than one
    // product, the license key benefit's ID so only Ledge keys unlock Ledge. While testing with sandbox
    // keys, point `api` at https://sandbox-api.polar.sh.
    static let organizationID = ""
    static let benefitID: String? = nil
    static let api = "https://api.polar.sh/v1/customer-portal/license-keys/"
    // Replace with the product's checkout link from Polar (Products › Checkout Links).
    static let buyURL = URL(string: "https://buy.polar.sh/ledge")!

    enum State: Equatable { case trial(daysLeft: Int), expired, licensed }

    private(set) var state = State.licensed
    var unlocked: Bool { state != .expired }
    var licensed: Bool { state == .licensed }
    /// Called when the app locks or unlocks, so tools can stop or start.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var trialStart = Date.now
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var activation: String?

    private init() {
        guard Snapshots.folder == nil else { return } // renders show the full app
        key = Keychain.read("licenseKey")
        activation = Keychain.read("activation")
        // Kept in both places, earliest wins: deleting the app's preferences doesn't restart the trial.
        // A trial started back when the app was called Kestrel carries over too.
        let saved = [Keychain.read("trialStart"), Keychain.read("trialStart", service: Migration.oldBundleID)].map { $0.flatMap(Double.init) }
            + [UserDefaults.standard.object(forKey: "trialStart") as? Double]
        trialStart = saved.compactMap { $0 }.min().map(Date.init(timeIntervalSince1970:)) ?? .now
        Keychain.write("trialStart", String(trialStart.timeIntervalSince1970))
        UserDefaults.standard.set(trialStart.timeIntervalSince1970, forKey: "trialStart")
        refresh()
        Task { [weak self] in
            await self?.check()
            while !Task.isCancelled { // so the trial ends on time while Ledge keeps running
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
        guard !Self.organizationID.isEmpty else { return "This build of Ledge can't take license keys yet." }
        let label = Host.current().localizedName ?? "Mac"
        guard let (status, reply) = await Self.post("activate", ["key": key, "organization_id": Self.organizationID, "label": label]) else {
            return Self.offline
        }
        guard status == 200, let activation = reply?.id else { return Self.problem(status: status, reply: reply) }
        guard Self.isOurs(benefit: reply?.licenseKey?.benefitId, expected: Self.benefitID) else {
            // Don't use up a slot on the other product's key.
            _ = await Self.post("deactivate", ["key": key, "organization_id": Self.organizationID, "activation_id": activation])
            return "That key is for a different product."
        }
        save(key: key, activation: activation)
        return nil
    }

    /// Frees this Mac's slot so the key can be used on another one.
    func deactivate() async -> String? {
        guard let key, let activation else { save(key: nil, activation: nil); return nil }
        guard let (status, reply) = await Self.post("deactivate", ["key": key, "organization_id": Self.organizationID, "activation_id": activation]) else {
            return Self.offline
        }
        // 404: Polar no longer has this activation, so the slot is already free.
        guard status == 204 || status == 404 else { return reply?.detail ?? "Couldn't deactivate this Mac." }
        save(key: nil, activation: nil)
        return nil
    }

    /// A refunded or revoked key stops working; Polar answers 404 for it. Offline, or on any server
    /// trouble, a licensed Mac stays licensed.
    private func check() async {
        guard let key, let activation else { return }
        let result = await Self.post("validate", ["key": key, "organization_id": Self.organizationID, "activation_id": activation])
        if result?.status == 404 { save(key: nil, activation: nil) }
    }

    private func save(key: String?, activation: String?) {
        (self.key, self.activation) = (key, activation)
        Keychain.write("licenseKey", key)
        Keychain.write("activation", activation)
        refresh()
    }

    private func refresh() {
        let new = Self.state(trialStart: trialStart, now: .now, licensed: activation != nil)
        guard new != state else { return }
        let wasUnlocked = unlocked
        state = new
        if unlocked != wasUnlocked { onChange?() }
    }

    // MARK: Polar

    /// What Polar sends back: the activation on success, `{"error", "detail"}` on failure. Field
    /// checks send `detail` as a list instead of a sentence, so each field is read on its own.
    struct Reply: Decodable {
        var id: String?
        var error: String?
        var detail: String?
        var licenseKey: Key?
        struct Key: Decodable { var benefitId: String? }

        enum CodingKeys: String, CodingKey { case id, error, detail, licenseKey }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            error = try? container.decodeIfPresent(String.self, forKey: .error)
            detail = try? container.decodeIfPresent(String.self, forKey: .detail)
            licenseKey = try? container.decodeIfPresent(Key.self, forKey: .licenseKey)
        }
    }

    nonisolated static func isOurs(benefit: String?, expected: String?) -> Bool {
        guard let expected else { return true } // one product: every key in the organization is a Ledge key
        return benefit == expected
    }

    nonisolated static func decode(_ data: Data) -> Reply? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Reply.self, from: data)
    }

    /// The sentence to show for a refused activation.
    nonisolated static func problem(status: Int, reply: Reply?) -> String {
        switch status {
        case 404: return "That key wasn't found. Check it against your receipt email."
        case 403 where reply?.detail?.localizedCaseInsensitiveContains("limit") == true:
            return "This key is already on two Macs. Deactivate it on one of them in Ledge's Settings, then try again."
        case 403: return reply?.detail ?? "That key can't be activated."
        default: return reply?.detail ?? "That key didn't work. Try again in a moment."
        }
    }

    private static let offline = "Couldn't reach the license server. Check your connection and try again."

    /// The status and reply, or nil when the server couldn't be reached.
    private static func post(_ action: String, _ fields: [String: String]) async -> (status: Int, reply: Reply?)? {
        var request = URLRequest(url: URL(string: api + action)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, decode(data))
    }
}

/// Generic passwords in the login keychain: they survive deleting the app, unlike its preferences.
private enum Keychain {
    private static let service = "com.ledge.Ledge"

    static func read(_ account: String, service: String = service) -> String? {
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
                Text("Buy Ledge once to keep using it on this Mac and one more. Everything you set up is still here.")
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
                Button("Buy Ledge, $19.99") { NSWorkspace.shared.open(License.buyURL) }
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
                LabeledContent("Ledge", value: "Licensed on this Mac")
                Button("Deactivate on this Mac…") { confirmDeactivate = true }
                    .disabled(working)
                    .confirmationDialog("Deactivate Ledge on this Mac?", isPresented: $confirmDeactivate) {
                        Button("Deactivate") { run { await license.deactivate() } }
                    } message: {
                        Text("This frees one of your key's two Macs. You'll need the key from your receipt email to activate again.")
                    }
            } else {
                LabeledContent("Ledge", value: status)
                HStack {
                    TextField("License key", text: $key, prompt: Text("Paste the key from your receipt"))
                        .labelsHidden()
                        .onSubmit { activate() }
                    Button(working ? "Activating…" : "Activate", action: activate)
                        .disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Buy Ledge, $19.99", destination: License.buyURL)
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

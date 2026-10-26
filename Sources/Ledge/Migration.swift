import Foundation

/// Ledge was called Kestrel before (and Islet before that). On the first launch as Ledge, bring over
/// what Kestrel saved: its settings (stored under Kestrel's bundle identifier) and its folder in
/// Application Support (notes, the agent script).
enum Migration {
    static let oldBundleID = "com.kestrel.Kestrel"

    static func fromKestrel() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromKestrel") else { return }
        defer { defaults.set(true, forKey: "migratedFromKestrel") }

        for (key, value) in defaults.persistentDomain(forName: oldBundleID) ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appending(path: "Kestrel"), newFolder = support.appending(path: "Ledge")
        if FileManager.default.fileExists(atPath: oldFolder.path), !FileManager.default.fileExists(atPath: newFolder.path) {
            try? FileManager.default.moveItem(at: oldFolder, to: newFolder)
        }
    }
}

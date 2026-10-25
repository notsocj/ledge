import Foundation

/// Kestrel was called Islet before. On the first launch as Kestrel, bring over what Islet saved: its
/// settings (stored under Islet's bundle identifier) and its folder in Application Support (notes).
enum Migration {
    static func fromIslet() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromIslet") else { return }
        defer { defaults.set(true, forKey: "migratedFromIslet") }

        if let old = UserDefaults(suiteName: "com.islet.Islet") {
            for key in ["disabledTools", "personas", "onboarded", "knownTools", "shelf", "pickedColors", "worldClock"]
            where defaults.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appending(path: "Islet"), newFolder = support.appending(path: "Kestrel")
        if FileManager.default.fileExists(atPath: oldFolder.path), !FileManager.default.fileExists(atPath: newFolder.path) {
            try? FileManager.default.moveItem(at: oldFolder, to: newFolder)
        }
    }
}

import SwiftUI

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let updater = AppUpdater.shared
    private static var isPreview: Bool { NotificationPreview.isRequested || HomeMusicPreview.isRequested || F1Preview.isRequested }

    init() {
        if !Self.isPreview {
            Migration.fromKestrel() // before anything reads settings
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!Self.isPreview)) {
            if !Self.isPreview {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",")
                Button("Preview notification") { NotificationCenter.default.post(name: .previewNotification, object: nil) }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Divider()
                Button("Set up again…") { NotificationCenter.default.post(name: .startOnboarding, object: nil) }
                if Preferences.shared.isOn(.menuBarHider) {
                    // macOS 26+ draws every app's menu bar icon itself, so choosing which show is a system setting.
                    Button("Choose Menu Bar Icons…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                    }
                }
                Divider()
                Button("Quit Ledge") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        } label: {
            if let icon = Icon.image("ledge-mark") { Image(nsImage: icon) } else { Text("Ledge") }
        }
        Settings {
            if !Self.isPreview {
                SettingsView(preferences: .shared, updater: updater)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !NotificationPreview.startIfRequested(), !HomeMusicPreview.startIfRequested(), !F1Preview.startIfRequested() else { return }
        notch = NotchController()
        if Snapshots.folder == nil { AppUpdater.shared.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { notch?.open(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.quit()
    }
}

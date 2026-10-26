import SwiftUI

@main
struct LedgeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        Migration.fromKestrel() // before anything reads settings
    }

    var body: some Scene {
        MenuBarExtra {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
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
        } label: {
            if let icon = Icon.image("ledge-mark") { Image(nsImage: icon) } else { Text("Ledge") }
        }
        Settings {
            SettingsView(preferences: .shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { notch?.open(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.quit()
    }
}

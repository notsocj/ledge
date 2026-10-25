import SwiftUI

@main
struct IsletApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Islet") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            if let icon = Icon.image("widget-5-bold") { Image(nsImage: icon) } else { Text("Islet") }
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

    func applicationWillTerminate(_ notification: Notification) {
        notch?.quit()
    }
}

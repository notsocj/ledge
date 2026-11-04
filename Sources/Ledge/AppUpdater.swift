import Foundation
import Observation
import Sparkle

/// Sparkle owns the update schedule, installation UI and its persisted preferences. Creating this
/// model is inert; normal app startup explicitly starts it after excluding preview/test launches.
@Observable @MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private(set) var isAvailable = false
    private(set) var canCheckForUpdates = false
    private(set) var startupError: String?
    private var automaticChecksEnabled = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// Only user changes write to Sparkle. Reading or starting this model never overrides an
    /// existing preference or restarts Sparkle's scheduled checking cycle.
    var automaticallyChecksForUpdates: Bool {
        get { automaticChecksEnabled }
        set {
            guard let updater = controller?.updater, isAvailable,
                  updater.automaticallyChecksForUpdates != newValue else { return }
            updater.automaticallyChecksForUpdates = newValue
            automaticChecksEnabled = updater.automaticallyChecksForUpdates
        }
    }

    func start() {
        guard controller == nil,
              UpdateStartup.isAllowed(bundleURL: Bundle.main.bundleURL,
                                      information: Bundle.main.infoDictionary ?? [:],
                                      arguments: CommandLine.arguments,
                                      environment: ProcessInfo.processInfo.environment) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                      updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        do {
            // Use the throwing API so a broken developer bundle cannot display an unexpected
            // configuration alert. The release pipeline verifies all updater helpers and keys.
            try updater.start()
            isAvailable = true
            startupError = nil
            canCheckForUpdates = updater.canCheckForUpdates
            automaticChecksEnabled = updater.automaticallyChecksForUpdates
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
                },
                updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor [weak self] in self?.automaticChecksEnabled = value }
                },
            ]
        } catch {
            startupError = error.localizedDescription
            print("Ledge: update checking could not start: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        guard isAvailable, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}

/// A preview, test runner or raw Swift executable must never contact the update feed or launch an
/// installer. Validate the release configuration before even constructing Sparkle's controller.
enum UpdateStartup {
    static func isAllowed(bundleURL: URL, information: [String: Any], arguments: [String],
                          environment: [String: String]) -> Bool {
        let previewArguments: Set<String> = ["--snapshot", "--notification-preview", "--home-music-preview"]
        guard bundleURL.pathExtension == "app",
              information["CFBundleIdentifier"] as? String == "com.ledge.Ledge",
              information["CFBundleVersion"] as? String != nil,
              previewArguments.isDisjoint(with: arguments),
              environment["XCTestConfigurationFilePath"] == nil,
              environment["XCTestBundlePath"] == nil,
              let feed = information["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let publicKey = information["SUPublicEDKey"] as? String,
              Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }
}

import Foundation
import Testing
@testable import Ledge

private let updateBundle = URL(fileURLWithPath: "/Applications/Ledge.app")
private let updateInformation: [String: Any] = [
    "CFBundleIdentifier": "com.ledge.Ledge",
    "CFBundleVersion": "5",
    "SUFeedURL": "https://keepledge.vercel.app/appcast.xml",
    "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
]

@Test func updaterOnlyStartsFromAConfiguredAppBundle() {
    #expect(UpdateStartup.isAllowed(bundleURL: updateBundle, information: updateInformation,
                                    arguments: ["Ledge"], environment: [:]))
    #expect(!UpdateStartup.isAllowed(bundleURL: URL(fileURLWithPath: "/tmp/debug/Ledge"),
                                     information: updateInformation, arguments: ["Ledge"], environment: [:]))
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: [:],
                                     arguments: ["Ledge"], environment: [:]))
    var otherApp = updateInformation
    otherApp["CFBundleIdentifier"] = "example.OtherApp"
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: otherApp,
                                     arguments: ["Ledge"], environment: [:]))
}

@Test(arguments: ["--snapshot", "--notification-preview", "--home-music-preview", "--f1-preview"])
func updaterNeverRunsDuringPreviewCapture(argument: String) {
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: updateInformation,
                                     arguments: ["Ledge", argument, "/tmp/preview"], environment: [:]))
}

@Test func updaterDoesNotRunInsideTestsOrWithoutSecureReleaseConfiguration() {
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: updateInformation,
                                     arguments: ["Ledge"], environment: ["XCTestBundlePath": "/tmp/LedgeTests.xctest"]))
    var insecureFeed = updateInformation
    insecureFeed["SUFeedURL"] = "http://keepledge.vercel.app/appcast.xml"
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: insecureFeed,
                                     arguments: ["Ledge"], environment: [:]))
    var missingKey = updateInformation
    missingKey["SUPublicEDKey"] = "not-an-ed25519-key"
    #expect(!UpdateStartup.isAllowed(bundleURL: updateBundle, information: missingKey,
                                     arguments: ["Ledge"], environment: [:]))
}

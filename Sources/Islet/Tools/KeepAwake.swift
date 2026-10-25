import IOKit.pwr_mgt
import Observation

/// Keeps the display (and so the Mac) awake, like Amphetamine or `caffeinate -d`.
@Observable @MainActor
final class KeepAwake {
    private(set) var isOn = false
    @ObservationIgnored private var assertion = IOPMAssertionID(0)

    func toggle() {
        isOn ? off() : on()
    }

    func on() {
        guard !isOn else { return }
        isOn = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Islet: Keep awake" as CFString, &assertion) == kIOReturnSuccess
    }

    func off() {
        guard isOn else { return }
        IOPMAssertionRelease(assertion)
        isOn = false
    }
}

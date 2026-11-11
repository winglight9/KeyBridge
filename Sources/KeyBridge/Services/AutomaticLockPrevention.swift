import Foundation
import IOKit.pwr_mgt

/// Holds a display-sleep assertion only while KeyBridge is connected.
/// This does not unlock the Mac or override an explicit lock, lid close, or sleep.
final class AutomaticLockPrevention {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false
    private(set) var lastError = ""

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        if active {
            guard !isActive else { return true }
            var identifier: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "KeyBridge keeps the connected Mac awake" as CFString,
                &identifier
            )
            guard result == kIOReturnSuccess else {
                lastError = "Unable to prevent automatic lock (\(result))."
                return false
            }
            assertionID = identifier
            isActive = true
            lastError = ""
            return true
        }

        guard isActive else { return true }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
        lastError = ""
        return true
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}

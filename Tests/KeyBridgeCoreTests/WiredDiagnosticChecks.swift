import KeyBridgeCore

/// Return failures for the shared command-line runner; no system settings are touched.
func runWiredDiagnosticChecks() -> Int {
    var failures = 0
    func expect(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures += 1 }
    }
    func bridge(_ enabled: Bool = true, _ link: Bool? = true, _ addressed: Bool = true, name: String = "bridge0") -> WiredBridgeState {
        WiredBridgeState(name: name, enabled: enabled, linkActive: link, hasAddress: addressed)
    }
    expect(WiredDiagnosis.evaluate(configurationAvailable: false, bridges: []).stage == .configurationUnavailable, "testUnreadablePreferencesAreNotReportedAsMissingCable")
    expect(WiredDiagnosis.evaluate(bridges: []).stage == .bridgeMissing, "testMissingThunderboltConfiguration")
    expect(WiredDiagnosis.evaluate(bridges: [bridge(false)]).stage == .bridgeDisabled, "testDisabledThunderboltService")
    let noLink = WiredDiagnosis.evaluate(bridges: [bridge(true, false, false)])
    expect(noLink.stage == .noLink && noLink.message.contains("does not prove"), "testNoLinkDoesNotAssertUnsupportedCable")
    expect(WiredDiagnosis.evaluate(bridges: [bridge(true, true, false)]).stage == .waitingAddress, "testActiveLinkWaitsForAddressWithoutBlamingCable")
    expect(WiredDiagnosis.evaluate(bridges: [bridge(true, nil, false)]).stage == .linkUnknown, "testUnknownLinkIsNotTreatedAsDisconnected")
    expect(WiredDiagnosis.evaluate(bridges: [bridge(true, false, true)]).stage == .noLink, "testStaleAddressDoesNotOverrideExplicitLinkDown")
    let ready = WiredDiagnosis.evaluate(bridges: [bridge(false), bridge(true, true, true, name: "bridge1")])
    expect(ready.stage == .ready && ready.interfaceName == "bridge1", "testWorkingBridgeWinsOverDisabledAlternative")
    expect(WiredDiagnosis.evaluate(bridges: [bridge(true, nil, true)]).stage == .ready, "testUsableAddressCanProceedWhenLinkKeyIsUnavailable")
    return failures
}

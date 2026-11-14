import Foundation
import XCTest
@testable import LanGuardFeature

final class SupportPromptTests: XCTestCase {
    private let day = SupportPromptState.day
    private let install = Date(timeIntervalSince1970: 1_794_528_000)  // 2026-11-13 (UTC)

    private func mayAsk(_ s: SupportPromptState, day d: Double, switches: Int = 50, version: String = "1.3.2") -> Bool {
        s.mayAsk(now: install.addingTimeInterval(d * day), installDate: install, autoSwitches: switches, appVersion: version)
    }

    func testFirstAskNeedsSevenDaysAndMoreThan24Switches() {
        let s = SupportPromptState()
        XCTAssertFalse(mayAsk(s, day: 6.9))
        XCTAssertFalse(mayAsk(s, day: 30, switches: 24), "never at 24 or fewer, however long installed")
        XCTAssertTrue(mayAsk(s, day: 7, switches: 25))
    }

    func testSnoozeHidesFourteenDays() {
        var s = SupportPromptState()
        s.record(.snooze, now: install.addingTimeInterval(10 * day), appVersion: "1.3.2")
        XCTAssertFalse(mayAsk(s, day: 23.9))
        XCTAssertTrue(mayAsk(s, day: 24))
    }

    func testSupportQuietFor180Days() {
        var s = SupportPromptState()
        s.record(.support, now: install.addingTimeInterval(10 * day), appVersion: "1.3.2")
        XCTAssertFalse(mayAsk(s, day: 189))
        XCTAssertTrue(mayAsk(s, day: 190))
    }

    func testNeverLastsUntilNextMajorAndNinetyDays() {
        var s = SupportPromptState()
        s.record(.never, now: install.addingTimeInterval(10 * day), appVersion: "1.3.2")
        XCTAssertFalse(mayAsk(s, day: 300, version: "1.4.0"), "a feature release must not undo 'never'")
        XCTAssertFalse(mayAsk(s, day: 50, version: "2.0.0"), "a major release within 90 days must not undo it")
        XCTAssertTrue(mayAsk(s, day: 100, version: "2.0.0"))
    }

    func testAtMostThreeAsksPerRolling365Days() {
        var s = SupportPromptState()
        for d in [10.0, 40, 70] { s.recordShown(install.addingTimeInterval(d * day)) }
        XCTAssertFalse(mayAsk(s, day: 300))
        XCTAssertTrue(mayAsk(s, day: 376), "the first ask has rolled out of the window")
    }

    func testOldStateWithMissingKeysStillDecodes() throws {
        let snoozed = try JSONEncoder().encode(install)
        let json = #"{"snoozedUntil":\#(String(decoding: snoozed, as: UTF8.self))}"#
        let s = try JSONDecoder().decode(SupportPromptState.self, from: Data(json.utf8))
        XCTAssertEqual(s.snoozedUntil, install, "a missing key must not wipe the ones present")
        XCTAssertEqual(s.shownAt, [])
        XCTAssertNil(s.neverVersion)
        XCTAssertEqual(try JSONDecoder().decode(SupportPromptState.self, from: Data("{}".utf8)), SupportPromptState())
    }
}

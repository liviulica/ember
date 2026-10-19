import EmberLink
import Foundation
import XCTest

final class MessagesTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try LinkCoding.encoder().encode(value), as: UTF8.self)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try LinkCoding.decoder().decode(T.self, from: LinkCoding.encoder().encode(value))
    }

    func testStatusRoundTrips() throws {
        let since = Date(timeIntervalSince1970: 1_792_300_000)
        let status = LinkStatus(
            mode: .lid,
            paused: false,
            endsAt: Date(timeIntervalSince1970: 1_792_311_520),
            remaining: nil,
            duration: 28_800,
            sessionStartedAt: since,
            internet: LinkInternet(kind: .hotspot, ssid: "Liviu's iPhone"),
            battery: LinkBattery(percent: 64, charging: true),
            thermal: .normal,
            memory: .tight,
            agents: [
                LinkAgent(id: "s1", project: "ember", state: .working, activity: "Running a command", message: nil, since: since),
                LinkAgent(id: "s2", project: "daily-book", state: .waiting, activity: nil, message: "Claude needs your permission to use Bash", since: since),
            ],
            emberVersion: "0.3.0",
            sentAt: since
        )
        XCTAssertEqual(try roundTrip(status), status)
    }

    func testCommandKindJSON() throws {
        XCTAssertEqual(try json(LinkCommandKind.extend(seconds: 3600)), #"{"kind":"extend","seconds":3600}"#)
        XCTAssertEqual(try json(LinkCommandKind.stop), #"{"kind":"stop"}"#)
        XCTAssertEqual(try roundTrip(LinkCommandKind.extend(seconds: 7200)), .extend(seconds: 7200))
        XCTAssertEqual(try roundTrip(LinkCommandKind.stop), .stop)
    }

    func testCommandFreshness() {
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        func command(_ offset: TimeInterval) -> LinkCommand {
            LinkCommand(id: UUID(), kind: .stop, issuedAt: now.addingTimeInterval(offset))
        }
        XCTAssertTrue(command(-540).isFresh(now: now))
        XCTAssertTrue(command(540).isFresh(now: now))
        XCTAssertFalse(command(-660).isFresh(now: now))
        XCTAssertFalse(command(660).isFresh(now: now))
    }

    func testThermalMapping() {
        XCTAssertEqual(LinkThermal(.nominal), .normal)
        XCTAssertEqual(LinkThermal(.fair), .warm)
        XCTAssertEqual(LinkThermal(.serious), .hot)
        XCTAssertEqual(LinkThermal(.critical), .critical)
    }

    func testActivityStateUsesEpochSeconds() throws {
        let state = LinkActivityState(mode: .lid, paused: false, endsAtEpoch: 1_792_300_000, remainingSeconds: nil, status: .working)
        XCTAssertTrue(try json(state).contains(#""endsAtEpoch":1792300000"#))
        XCTAssertEqual(try roundTrip(state), state)
    }

    func testDatesAreEpochMilliseconds() throws {
        let event = LinkEvent(id: UUID(), kind: .endsSoon, title: "t", body: "b", sentAt: Date(timeIntervalSince1970: 1.5))
        XCTAssertTrue(try json(event).contains(#""sentAt":1500"#))
        XCTAssertEqual(try roundTrip(event), event)
    }

    func testAckRoundTrips() throws {
        let id = UUID()
        XCTAssertEqual(try roundTrip(LinkAck(commandID: id, result: .done)), LinkAck(commandID: id, result: .done))
        let refused = LinkAck(commandID: id, result: .refused(reason: "Lid mode is off"))
        XCTAssertEqual(try roundTrip(refused), refused)
    }

    func testUnknownValuesFromANewerMacStillDecode() throws {
        let json = #"""
        {"mode":"warp","paused":false,"internet":{"kind":"satellite"},"thermal":"molten","memory":"swapping",
         "agents":[{"id":"a","project":"p","state":"thinking","since":0}],"emberVersion":"9.0.0","sentAt":0}
        """#
        let status = try LinkCoding.decoder().decode(LinkStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.mode, .unknown)
        XCTAssertEqual(status.internet.kind, .unknown)
        XCTAssertEqual(status.thermal, .critical)
        XCTAssertEqual(status.memory, .critical)
        XCTAssertEqual(status.agents.first?.state, .working)
        let event = try LinkCoding.decoder().decode(LinkEvent.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"meteor","title":"t","body":"b","sentAt":0}"#.utf8))
        XCTAssertEqual(event.kind, .notice)
        let activity = try LinkCoding.decoder().decode(LinkActivityState.self, from: Data(#"{"mode":"lid","paused":false,"status":"dreaming"}"#.utf8))
        XCTAssertEqual(activity.status, .working)
    }
}

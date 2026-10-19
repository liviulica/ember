import EmberLink
import Foundation
import XCTest

final class PairingCodeTests: XCTestCase {
    private func sample(key: Data = Data(repeating: 7, count: 32)) -> PairingCode {
        PairingCode(
            relay: URL(string: "https://relay.chargingpixels.com")!,
            group: "g_abc",
            macDevice: "d_mac",
            macName: "Liviu's MacBook Pro",
            ticket: Base64URL.encode(Data(repeating: 1, count: 32)),
            key: Base64URL.encode(key)
        )
    }

    func testURLRoundTrip() {
        let code = sample()
        XCTAssertEqual(PairingCode(url: code.url), code)
    }

    func testURLHasNoQueryAndUsesFragment() {
        let url = sample().url
        XCTAssertEqual(url.host, "chargingpixels.com")
        XCTAssertEqual(url.path, "/ember/pair")
        XCTAssertNil(url.query)
        XCTAssertFalse(url.fragment?.isEmpty ?? true)
    }

    func testRejectsOtherHostOrPath() {
        let fragment = sample().url.fragment!
        XCTAssertNil(PairingCode(url: URL(string: "https://example.com/ember/pair#\(fragment)")!))
        XCTAssertNil(PairingCode(url: URL(string: "https://chargingpixels.com/ember/other#\(fragment)")!))
        XCTAssertNil(PairingCode(url: URL(string: "http://chargingpixels.com/ember/pair#\(fragment)")!))
        XCTAssertNil(PairingCode(url: URL(string: "https://chargingpixels.com/ember/pair#not-json")!))
    }

    func testRejectsShortKey() {
        XCTAssertNil(sample(key: Data(repeating: 7, count: 16)).sealingKey)
        XCTAssertNotNil(sample().sealingKey)
    }

    func testTicketHash() {
        XCTAssertEqual(PairingCode.ticketHash("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

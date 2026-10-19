import CryptoKit
@testable import EmberLink
import Foundation
import XCTest

final class SealerTests: XCTestCase {
    private struct Body: Codable, Equatable { var a: Int }

    private let context = SealContext(type: "event", id: "e1", from: "d_mac", to: "d_phone")

    func testRoundTrip() throws {
        let key = Sealer.newKey()
        let sealed = try Sealer.seal(Body(a: 1), key: key, context: context)
        XCTAssertEqual(try Sealer.open(Body.self, from: sealed, key: key, context: context), Body(a: 1))
    }

    func testWrongKeyFails() throws {
        let sealed = try Sealer.seal(Body(a: 1), key: Sealer.newKey(), context: context)
        XCTAssertThrowsError(try Sealer.open(Body.self, from: sealed, key: Sealer.newKey(), context: context)) {
            XCTAssertEqual($0 as? SealError, .authenticationFailed)
        }
    }

    func testContextIsBound() throws {
        let key = Sealer.newKey()
        let sealed = try Sealer.seal(Body(a: 1), key: key, context: context)
        let others = [
            SealContext(type: "event", id: "e1", from: "d_mac", to: "d_other"),
            SealContext(type: "status", id: "e1", from: "d_mac", to: "d_phone"),
            SealContext(type: "event", id: "e2", from: "d_mac", to: "d_phone"),
            SealContext(type: "event", id: "e1", from: "d_x", to: "d_phone"),
            SealContext(type: "event", id: "e1", from: "d_mac", to: nil),
        ]
        for other in others {
            XCTAssertThrowsError(try Sealer.open(Body.self, from: sealed, key: key, context: other)) {
                XCTAssertEqual($0 as? SealError, .authenticationFailed, "\(other)")
            }
        }
    }

    func testFlippedByteFails() throws {
        let key = Sealer.newKey()
        var bytes = Data(base64Encoded: try Sealer.seal(Body(a: 1), key: key, context: context))!
        bytes[14] ^= 0x01
        XCTAssertThrowsError(try Sealer.open(Body.self, from: bytes.base64EncodedString(), key: key, context: context)) {
            XCTAssertEqual($0 as? SealError, .authenticationFailed)
        }
    }

    func testGarbageIsMalformed() {
        XCTAssertThrowsError(try Sealer.open(Body.self, from: "not base64!", key: Sealer.newKey(), context: context)) {
            XCTAssertEqual($0 as? SealError, .malformed)
        }
        XCTAssertThrowsError(try Sealer.open(Body.self, from: "AAAA", key: Sealer.newKey(), context: context)) {
            XCTAssertEqual($0 as? SealError, .malformed)
        }
    }

    func testFixedVector() throws {
        let key = SymmetricKey(data: Data((1...32).map { UInt8($0) }))
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
        let sealed = try Sealer.seal(Body(a: 1), key: key, context: context, nonce: nonce)
        // Cross-checked with Node's chacha20-poly1305 (same key, nonce and AAD).
        XCTAssertEqual(sealed, "AAAAAAAAAAAAAAAAGKi2NF3z1APxrXBoYELGFHuLb2Xz9BU=")
    }
}

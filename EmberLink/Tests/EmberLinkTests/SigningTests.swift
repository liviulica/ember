import CryptoKit
import EmberLink
import Foundation
import XCTest

final class SigningTests: XCTestCase {
    private let body = Data(#"{"x":1}"#.utf8)
    private let now: Int64 = 1_792_300_000_000

    func testCanonicalString() {
        XCTAssertEqual(
            RequestSigner.canonical(method: "post", path: "/v1/a?b=1", timestampMs: now, body: body),
            "POST\n/v1/a?b=1\n1792300000000\n5041bf1f713df204784353e82f6a4a535931cb64f1f4b4a5aeaffcb720918b22"
        )
    }

    func testSignVerifyRoundTrip() throws {
        let identity = DeviceIdentity()
        let header = try RequestSigner.authorization(device: "d_1", key: identity.privateKey, method: "POST", path: "/v1/x", timestampMs: now, body: body)
        XCTAssertTrue(header.hasPrefix("EmberSig device=d_1,ts=1792300000000,sig="))
        XCTAssertTrue(RequestSigner.verify(header: header, publicKeyX963: identity.privateKey.publicKey.x963Representation, method: "POST", path: "/v1/x", body: body, nowMs: now))
    }

    func testVerifyRejectsSkew() throws {
        let key = P256.Signing.PrivateKey()
        let public963 = key.publicKey.x963Representation
        func verifies(_ ts: Int64) throws -> Bool {
            let header = try RequestSigner.authorization(device: "d_1", key: key, method: "GET", path: "/v1/x", timestampMs: ts, body: Data())
            return RequestSigner.verify(header: header, publicKeyX963: public963, method: "GET", path: "/v1/x", body: Data(), nowMs: now)
        }
        XCTAssertTrue(try verifies(now - 300_000))
        XCTAssertTrue(try verifies(now + 300_000))
        XCTAssertFalse(try verifies(now - 300_001))
        XCTAssertFalse(try verifies(now + 300_001))
    }

    func testVerifyRejectsOtherBodyAndPath() throws {
        let key = P256.Signing.PrivateKey()
        let header = try RequestSigner.authorization(device: "d_1", key: key, method: "POST", path: "/v1/x", timestampMs: now, body: body)
        let public963 = key.publicKey.x963Representation
        XCTAssertFalse(RequestSigner.verify(header: header, publicKeyX963: public963, method: "POST", path: "/v1/x", body: Data(#"{"x":2}"#.utf8), nowMs: now))
        XCTAssertFalse(RequestSigner.verify(header: header, publicKeyX963: public963, method: "POST", path: "/v1/y", body: body, nowMs: now))
        XCTAssertFalse(RequestSigner.verify(header: header, publicKeyX963: public963, method: "PUT", path: "/v1/x", body: body, nowMs: now))
        XCTAssertFalse(RequestSigner.verify(header: header, publicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation, method: "POST", path: "/v1/x", body: body, nowMs: now))
        XCTAssertFalse(RequestSigner.verify(header: "EmberSig nonsense", publicKeyX963: public963, method: "POST", path: "/v1/x", body: body, nowMs: now))
    }

    func testVectorsFileVerifies() throws {
        struct Vector: Decodable {
            var publicKeyX963Base64, device, method, path, body, canonical, authorization: String
            var timestampMs: Int64
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestVectors/signing.json")
        let vector = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
        let body = Data(vector.body.utf8)
        XCTAssertEqual(RequestSigner.canonical(method: vector.method, path: vector.path, timestampMs: vector.timestampMs, body: body), vector.canonical)
        XCTAssertTrue(vector.authorization.hasPrefix("EmberSig device=\(vector.device),ts=\(vector.timestampMs),sig="))
        XCTAssertTrue(RequestSigner.verify(
            header: vector.authorization,
            publicKeyX963: try XCTUnwrap(Data(base64Encoded: vector.publicKeyX963Base64)),
            method: vector.method, path: vector.path, body: body, nowMs: vector.timestampMs
        ))
    }

    func testEnvelopeJSONShape() throws {
        let envelope = LinkEnvelope(type: "status", id: "m1", from: "d_mac", to: nil, sentAt: 1500, sealed: "abc", hints: nil)
        let json = String(decoding: try LinkCoding.encoder().encode(envelope), as: UTF8.self)
        XCTAssertEqual(json, #"{"from":"d_mac","id":"m1","sealed":"abc","sentAt":1500,"type":"status","v":1}"#)
        let hinted = LinkEnvelope(
            type: "activity", id: "m2", from: "d_mac", to: "d_phone", sentAt: 1, sealed: nil,
            hints: LinkHints(sessionOn: true, push: nil, alertKind: nil,
                             activity: LinkActivityState(mode: .lid, paused: false, endsAtEpoch: 10, remainingSeconds: nil, status: .working),
                             activityPhase: "start")
        )
        XCTAssertEqual(try LinkCoding.decoder().decode(LinkEnvelope.self, from: LinkCoding.encoder().encode(hinted)), hinted)
    }
}

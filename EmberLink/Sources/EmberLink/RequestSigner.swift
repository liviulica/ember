import CryptoKit
import Foundation

/// A device's signing key. The relay stores only the public half.
public struct DeviceIdentity: Sendable {
    public let privateKey: P256.Signing.PrivateKey

    public init(privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) {
        self.privateKey = privateKey
    }

    /// The public key, x9.63 uncompressed, standard base64: what the relay
    /// imports with WebCrypto as a raw P-256 key.
    public var publicKeyBase64: String {
        privateKey.publicKey.x963Representation.base64EncodedString()
    }
}

/// Signs requests to the relay and checks them (the relay does the same in
/// TypeScript; `EmberLink/TestVectors/signing.json` keeps the two in step).
///
/// Header: `EmberSig device=<id>,ts=<ms>,sig=<base64url raw r||s>`, signed
/// over `METHOD\npath\nts\nsha256hex(body)`, valid within 5 minutes of the
/// verifier's clock.
public enum RequestSigner {
    public static let window: Int64 = 300_000

    public static func canonical(method: String, path: String, timestampMs: Int64, body: Data) -> String {
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return "\(method.uppercased())\n\(path)\n\(timestampMs)\n\(digest)"
    }

    public static func authorization(device: String, key: P256.Signing.PrivateKey, method: String, path: String, timestampMs: Int64, body: Data) throws -> String {
        let message = Data(canonical(method: method, path: path, timestampMs: timestampMs, body: body).utf8)
        let signature = try key.signature(for: message)
        return "EmberSig device=\(device),ts=\(timestampMs),sig=\(Base64URL.encode(signature.rawRepresentation))"
    }

    public static func verify(header: String, publicKeyX963: Data, method: String, path: String, body: Data, nowMs: Int64) -> Bool {
        guard let parts = parse(header),
              abs(nowMs - parts.ts) <= window,
              let key = try? P256.Signing.PublicKey(x963Representation: publicKeyX963),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: parts.sig)
        else { return false }
        let message = Data(canonical(method: method, path: path, timestampMs: parts.ts, body: body).utf8)
        return key.isValidSignature(signature, for: message)
    }

    public static func parse(_ header: String) -> (device: String, ts: Int64, sig: Data)? {
        let prefix = "EmberSig "
        guard header.hasPrefix(prefix) else { return nil }
        var fields: [String: String] = [:]
        for pair in header.dropFirst(prefix.count).split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            fields[String(kv[0])] = String(kv[1])
        }
        guard let device = fields["device"], !device.isEmpty,
              let ts = fields["ts"].flatMap({ Int64($0) }),
              let sig = fields["sig"].flatMap(Base64URL.decode)
        else { return nil }
        return (device, ts, sig)
    }
}

/// base64url without padding.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), text.allSatisfy(\.isASCII) else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

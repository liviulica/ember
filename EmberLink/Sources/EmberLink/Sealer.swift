import CryptoKit
import Foundation

/// What a sealed body is bound to: the envelope's type, id, sender and
/// recipient. A body cut out of one envelope and pasted into another fails
/// to open.
public struct SealContext: Sendable, Equatable {
    public var type: String
    public var id: String
    public var from: String
    public var to: String?

    public init(type: String, id: String, from: String, to: String?) {
        self.type = type
        self.id = id
        self.from = from
        self.to = to
    }

    public var aad: Data {
        Data("ember1|\(type)|\(id)|\(from)|\(to ?? "")".utf8)
    }
}

public enum SealError: Error, Equatable {
    case malformed
    case authenticationFailed
}

/// Seals message bodies with the key one phone shares with its Mac
/// (ChaChaPoly). The relay carries the result and cannot read it.
public enum Sealer {
    public static func newKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Base64 (standard, padded) of ChaChaPoly's combined nonce, ciphertext
    /// and tag.
    public static func seal<T: Encodable>(_ value: T, key: SymmetricKey, context: SealContext) throws -> String {
        try seal(value, key: key, context: context, nonce: ChaChaPoly.Nonce())
    }

    static func seal<T: Encodable>(_ value: T, key: SymmetricKey, context: SealContext, nonce: ChaChaPoly.Nonce) throws -> String {
        let plaintext = try LinkCoding.encoder().encode(value)
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: context.aad)
        return box.combined.base64EncodedString()
    }

    public static func open<T: Decodable>(_ type: T.Type, from sealed: String, key: SymmetricKey, context: SealContext) throws -> T {
        guard let data = Data(base64Encoded: sealed),
              let box = try? ChaChaPoly.SealedBox(combined: data)
        else { throw SealError.malformed }
        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(box, using: key, authenticating: context.aad)
        } catch {
            throw SealError.authenticationFailed
        }
        return try LinkCoding.decoder().decode(T.self, from: plaintext)
    }
}

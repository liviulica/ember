import CryptoKit
import Foundation

/// What Ember's QR code carries to a new phone: where the relay is, which
/// group to join, a one-time ticket, and the sealing key that phone will
/// share with the Mac. Encoded as
/// `https://chargingpixels.com/ember/pair#<base64url JSON>`; a fragment is
/// never sent to a server, so the key only ever travels through the camera.
public struct PairingCode: Codable, Equatable, Sendable {
    public static let host = "chargingpixels.com"
    public static let path = "/ember/pair"

    public var relay: URL
    public var group: String
    public var macDevice: String
    public var macName: String
    /// base64url of 32 random bytes; the relay only ever sees its hash
    /// until the phone redeems it.
    public var ticket: String
    /// base64url of the phone's 32-byte sealing key.
    public var key: String

    public init(relay: URL, group: String, macDevice: String, macName: String, ticket: String, key: String) {
        self.relay = relay
        self.group = group
        self.macDevice = macDevice
        self.macName = macName
        self.ticket = ticket
        self.key = key
    }

    public var url: URL {
        let json = (try? LinkCoding.encoder().encode(self)) ?? Data()
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = Self.path
        components.fragment = Base64URL.encode(json)
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == "https", url.host == Self.host, url.path == Self.path, url.query == nil,
              let fragment = url.fragment, let json = Base64URL.decode(fragment),
              let code = try? LinkCoding.decoder().decode(PairingCode.self, from: json)
        else { return nil }
        self = code
    }

    /// The sealing key, or nil when it is not 32 bytes.
    public var sealingKey: SymmetricKey? {
        guard let data = Base64URL.decode(key), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// Lowercase hex SHA-256 of the ticket's text: what the Mac registers
    /// with the relay before showing the code.
    public static func ticketHash(_ ticket: String) -> String {
        SHA256.hash(data: Data(ticket.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

/// The plaintext wrapper every message travels in, between a device and the
/// relay. The relay reads it to route and push; `sealed` is the body only
/// the Mac and the addressed phone can open. Types: status, event, activity,
/// ack, ending, command.
public struct LinkEnvelope: Codable, Equatable, Sendable {
    public var v: Int
    public var type: String
    public var id: String
    public var from: String
    public var to: String?
    /// Milliseconds since 1970.
    public var sentAt: Int64
    public var sealed: String?
    public var hints: LinkHints?

    public init(type: String, id: String, from: String, to: String?, sentAt: Int64, sealed: String?, hints: LinkHints?) {
        self.v = 1
        self.type = type
        self.id = id
        self.from = from
        self.to = to
        self.sentAt = sentAt
        self.sealed = sealed
        self.hints = hints
    }

    /// What the sealed body is bound to.
    public var sealContext: SealContext {
        SealContext(type: type, id: id, from: from, to: to)
    }
}

/// The little the relay is allowed to know about a message.
public struct LinkHints: Codable, Equatable, Sendable {
    /// A mode is on: the relay watches for the Mac going quiet.
    public var sessionOn: Bool?
    /// "alert": push this event to the phone as a notification.
    public var push: String?
    /// The notification category (a LinkEventKind raw value).
    public var alertKind: String?
    /// The Live Activity's content, for `activity` envelopes.
    public var activity: LinkActivityState?
    /// "start", "update" or "end".
    public var activityPhase: String?

    public init(sessionOn: Bool?, push: String?, alertKind: String?, activity: LinkActivityState?, activityPhase: String?) {
        self.sessionOn = sessionOn
        self.push = push
        self.alertKind = alertKind
        self.activity = activity
        self.activityPhase = activityPhase
    }
}

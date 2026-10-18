import Foundation

// The messages Ember sends to its phones and the commands it takes back
// (spec 2026-10-18 "The protocol package"). Status, events, commands and acks
// travel sealed (Sealer); only LinkActivityState is plaintext, because the
// Live Activity on the lock screen cannot decrypt.

/// A string enum that decodes a value it does not know to `fallback`
/// instead of failing. Ember updates through Sparkle and the phone through
/// the App Store, so a newer Mac can send a case an older phone lacks; one
/// unknown value must not make the whole status unreadable.
public protocol LinkTolerantEnum: RawRepresentable, Codable where RawValue == String {
    static var fallback: Self { get }
}

public extension LinkTolerantEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

public enum LinkMode: String, LinkTolerantEnum, Equatable, Sendable {
    case off, screen, lid, unknown
    public static let fallback = LinkMode.unknown
}

public enum LinkInternetKind: String, LinkTolerantEnum, Equatable, Sendable {
    case wifi, hotspot, ethernet, none, unknown
    public static let fallback = LinkInternetKind.unknown
}

public struct LinkInternet: Codable, Equatable, Sendable {
    public var kind: LinkInternetKind
    /// The Wi-Fi name, when Ember can read it (it needs Location).
    public var ssid: String?

    public init(kind: LinkInternetKind, ssid: String?) {
        self.kind = kind
        self.ssid = ssid
    }
}

public struct LinkBattery: Codable, Equatable, Sendable {
    public var percent: Int
    public var charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }
}

public enum LinkThermal: String, LinkTolerantEnum, Equatable, Sendable {
    case normal, warm, hot, critical
    /// Unknown reads as the worst, so the phone warns rather than reassures.
    public static let fallback = LinkThermal.critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .normal
        case .fair: self = .warm
        case .serious: self = .hot
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

public enum LinkMemory: String, LinkTolerantEnum, Equatable, Sendable {
    case normal, tight, critical
    public static let fallback = LinkMemory.critical
}

public enum LinkAgentState: String, LinkTolerantEnum, Equatable, Sendable {
    case working, waiting, done
    public static let fallback = LinkAgentState.working
}

/// One coding agent session (Claude Code today). Never carries prompts, file
/// contents, commands or transcripts.
public struct LinkAgent: Codable, Equatable, Sendable {
    public var id: String
    /// The project folder's name, not its path.
    public var project: String
    public var state: LinkAgentState
    /// A few words on what it is doing ("Running a command").
    public var activity: String?
    /// Claude's short notification text while it waits for the user.
    public var message: String?
    public var since: Date

    public init(id: String, project: String, state: LinkAgentState, activity: String?, message: String?, since: Date) {
        self.id = id
        self.project = project
        self.state = state
        self.activity = activity
        self.message = message
        self.since = since
    }
}

public struct LinkStatus: Codable, Equatable, Sendable {
    public var mode: LinkMode
    /// Lid mode with the lid open: the timer stands still.
    public var paused: Bool
    /// When the mode ends; nil while paused (send `remaining` then) or for an
    /// unlimited Screen mode.
    public var endsAt: Date?
    public var remaining: TimeInterval?
    public var duration: TimeInterval?
    /// When the session started, for the 24 h cap on remote extends.
    public var sessionStartedAt: Date?
    public var internet: LinkInternet
    public var battery: LinkBattery?
    public var thermal: LinkThermal
    public var memory: LinkMemory
    public var agents: [LinkAgent]
    public var emberVersion: String
    public var sentAt: Date

    public init(
        mode: LinkMode, paused: Bool, endsAt: Date?, remaining: TimeInterval?, duration: TimeInterval?,
        sessionStartedAt: Date?, internet: LinkInternet, battery: LinkBattery?, thermal: LinkThermal,
        memory: LinkMemory, agents: [LinkAgent], emberVersion: String, sentAt: Date
    ) {
        self.mode = mode
        self.paused = paused
        self.endsAt = endsAt
        self.remaining = remaining
        self.duration = duration
        self.sessionStartedAt = sessionStartedAt
        self.internet = internet
        self.battery = battery
        self.thermal = thermal
        self.memory = memory
        self.agents = agents
        self.emberVersion = emberVersion
        self.sentAt = sentAt
    }
}

public enum LinkEventKind: String, LinkTolerantEnum, Equatable, Sendable {
    case endsSoon, ended, battery, thermal, agentWaiting, restoreWarning, notice
    public static let fallback = LinkEventKind.notice
}

/// A notification for the phone, with the text the Mac wrote.
public struct LinkEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: LinkEventKind
    public var title: String
    public var body: String
    public var sentAt: Date

    public init(id: UUID, kind: LinkEventKind, title: String, body: String, sentAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.sentAt = sentAt
    }
}

public enum LinkCommandKind: Codable, Equatable, Sendable {
    case extend(seconds: Int)
    case stop

    private enum CodingKeys: String, CodingKey { case kind, seconds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "extend": self = .extend(seconds: try container.decode(Int.self, forKey: .seconds))
        case "stop": self = .stop
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown command \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .extend(seconds):
            try container.encode("extend", forKey: .kind)
            try container.encode(seconds, forKey: .seconds)
        case .stop:
            try container.encode("stop", forKey: .kind)
        }
    }
}

public struct LinkCommand: Codable, Equatable, Sendable {
    /// How far `issuedAt` may be from the Mac's clock. Loose on purpose: the
    /// relay never queues commands, so this only bounds replays, and phone
    /// and Mac clocks can be minutes apart.
    public static let freshness: TimeInterval = 600

    public var id: UUID
    public var kind: LinkCommandKind
    public var issuedAt: Date

    public init(id: UUID, kind: LinkCommandKind, issuedAt: Date) {
        self.id = id
        self.kind = kind
        self.issuedAt = issuedAt
    }

    public func isFresh(now: Date) -> Bool {
        abs(issuedAt.timeIntervalSince(now)) <= Self.freshness
    }
}

public enum LinkAckResult: Codable, Equatable, Sendable {
    case done
    case refused(reason: String)

    private enum CodingKeys: String, CodingKey { case result, reason }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .result) {
        case "done": self = .done
        case "refused": self = .refused(reason: try container.decode(String.self, forKey: .reason))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "unknown result \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .done:
            try container.encode("done", forKey: .result)
        case let .refused(reason):
            try container.encode("refused", forKey: .result)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public struct LinkAck: Codable, Equatable, Sendable {
    public var commandID: UUID
    public var result: LinkAckResult

    public init(commandID: UUID, result: LinkAckResult) {
        self.commandID = commandID
        self.result = result
    }
}

public enum LinkActivityStatus: String, LinkTolerantEnum, Equatable, Sendable, Hashable {
    case working, offline, quiet, ended
    public static let fallback = LinkActivityStatus.working
}

/// The Live Activity's content, sent in plaintext through the relay. Times
/// are epoch seconds, never `Date`: ActivityKit decodes a `Date` as seconds
/// since 2001, and the relay builds this JSON itself when the Mac goes quiet.
public struct LinkActivityState: Codable, Equatable, Sendable, Hashable {
    public var mode: LinkMode
    public var paused: Bool
    public var endsAtEpoch: Double?
    public var remainingSeconds: Double?
    public var status: LinkActivityStatus

    public init(mode: LinkMode, paused: Bool, endsAtEpoch: Double?, remainingSeconds: Double?, status: LinkActivityStatus) {
        self.mode = mode
        self.paused = paused
        self.endsAtEpoch = endsAtEpoch
        self.remainingSeconds = remainingSeconds
        self.status = status
    }
}

public enum LinkCoding {
    /// Dates as milliseconds since 1970, keys sorted.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

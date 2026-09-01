import CursorBarDomain
import Foundation

/// Persists nicknames in Application Support. Keyed by identity or email, with seatID as a paint fallback.
public struct SeatUserLabelStore: Sendable {
    private let url: URL
    private let fileManager: FileManager

    public init(
        applicationSupportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = CursorBarDataDirectory.applicationSupportRoot(override: applicationSupportRoot)
        self.url = root.appendingPathComponent("seat-user-labels.json", isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() -> [Entry] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return envelope.entries.compactMap { raw in
                guard let label = SeatUserLabel(raw.text) else { return nil }
                return Entry(seatID: raw.seatID, identity: raw.identity, email: raw.email, label: label)
            }
        } catch {
            return []
        }
    }

    public func labelsBySeat() -> [SeatID: SeatUserLabel] {
        labels(seatIDs: load().map(\.seatID))
    }

    public func labels(for records: [StoredSeatRecord]) -> [SeatID: SeatUserLabel] {
        var emails: [SeatID: Email] = [:]
        var identities: [SeatID: SessionIdentity] = [:]
        for record in records {
            identities[record.seatID] = record.identity
            if let email = record.email {
                emails[record.seatID] = email
            }
        }
        return labels(seatIDs: records.map(\.seatID), emails: emails, identities: identities)
    }

    public func labels(
        seatIDs: [SeatID],
        emails: [SeatID: Email] = [:],
        identities: [SeatID: SessionIdentity] = [:]
    ) -> [SeatID: SeatUserLabel] {
        let entries = load()
        var byIdentity: [SessionIdentity: SeatUserLabel] = [:]
        var byEmail: [String: SeatUserLabel] = [:]
        var bySeat: [SeatID: SeatUserLabel] = [:]
        for entry in entries {
            if let identity = entry.identity {
                byIdentity[identity] = entry.label
                if case .email(let email) = identity {
                    byEmail[email.value.lowercased()] = entry.label
                }
            }
            if let email = entry.email {
                byEmail[email.value.lowercased()] = entry.label
            }
            bySeat[entry.seatID] = entry.label
        }
        var mapped: [SeatID: SeatUserLabel] = [:]
        for seatID in seatIDs {
            if let identity = identities[seatID], let label = byIdentity[identity] {
                mapped[seatID] = label
                continue
            }
            if let email = emails[seatID], let label = byEmail[email.value.lowercased()] {
                mapped[seatID] = label
                continue
            }
            if let label = bySeat[seatID] {
                mapped[seatID] = label
            }
        }
        return mapped
    }

    public func set(
        label: SeatUserLabel?,
        identity: SessionIdentity?,
        email: Email? = nil,
        seatID: SeatID
    ) {
        var entries = load()
        let emailKey = email?.value.lowercased()
        entries.removeAll { entry in
            if let identity, entry.identity == identity { return true }
            if let emailKey, entry.email?.value.lowercased() == emailKey { return true }
            if let emailKey, case .email(let stored) = entry.identity,
               stored.value.lowercased() == emailKey
            {
                return true
            }
            return entry.seatID == seatID
        }
        if let label {
            entries.append(Entry(seatID: seatID, identity: identity, email: email, label: label))
        }
        write(entries)
    }

    public struct Entry: Sendable, Equatable {
        public let seatID: SeatID
        public let identity: SessionIdentity?
        public let email: Email?
        public let label: SeatUserLabel
    }

    private func write(_ entries: [Entry]) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = Envelope(
                entries: entries.map {
                    WireEntry(seatID: $0.seatID, identity: $0.identity, email: $0.email, text: $0.label.value)
                }
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private struct Envelope: Codable {
        var entries: [WireEntry]
    }

    private struct WireEntry: Codable {
        var seatID: SeatID
        var identity: SessionIdentity?
        var email: Email?
        var text: String
    }
}

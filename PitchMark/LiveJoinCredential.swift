//
//  LiveJoinCredential.swift
//  PitchMark
//
//  How a partner's device got into a live room - the join code it typed or
//  the invite link it opened. firestore.rules only lets a partner create
//  their presence document (liveGames/{id}/participants/{uid}) when it names
//  one of those for that room and it hasn't expired (2026-10-31; before
//  that, knowing a room's id was enough).
//
//  Presence is deleted and recreated in ordinary use - opening another game
//  deletes it, re-entering from Home recreates it - so the credential is
//  remembered per room on the device and in the partner's joined-session
//  bookmark, and every presence write carries it.
//
//  PitchMark target only.
//

import Foundation

struct LiveJoinCredential: Equatable, Codable {
    enum Kind: String, Codable {
        case joinCode
        case inviteToken
    }

    var kind: Kind
    var value: String

    init?(kind: Kind, value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        self.kind = kind
        self.value = trimmed
    }

    /// The presence / bookmark field the rules read.
    var field: String { kind.rawValue }

    /// The credential stored in a joined-session bookmark (or any document
    /// carrying one of the two fields). A join code wins if both are there.
    init?(document data: [String: Any]) {
        if let code = LiveJoinCredential(kind: .joinCode, value: data[Kind.joinCode.rawValue] as? String) {
            self = code
        } else if let token = LiveJoinCredential(kind: .inviteToken, value: data[Kind.inviteToken.rawValue] as? String) {
            self = token
        } else {
            return nil
        }
    }

    /// A presence write: who, the given timestamps, and the credential when
    /// known. The owner needs none.
    static func presenceFields(uid: String, credential: LiveJoinCredential?, timestamps: [String: Any]) -> [String: Any] {
        var fields = timestamps
        fields["uid"] = uid
        if let credential { fields[credential.field] = credential.value }
        return fields
    }

    // MARK: - On this device

    private static func key(_ liveId: String) -> String { "liveJoinCredential.\(liveId)" }

    static func remembered(for liveId: String, in defaults: UserDefaults = .standard) -> LiveJoinCredential? {
        guard let data = defaults.data(forKey: key(liveId)) else { return nil }
        return try? JSONDecoder().decode(LiveJoinCredential.self, from: data)
    }

    static func remember(_ credential: LiveJoinCredential?, for liveId: String, in defaults: UserDefaults = .standard) {
        guard let credential, !liveId.isEmpty,
              let data = try? JSONEncoder().encode(credential)
        else { return }
        defaults.set(data, forKey: key(liveId))
    }

    static func forget(liveId: String, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(liveId))
    }
}

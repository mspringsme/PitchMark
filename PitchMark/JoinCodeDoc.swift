//
//  JoinCodeDoc.swift
//  PitchMark
//
//  Created by Mark Springer on 2/22/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firestore Models

struct JoinCodeDoc: Codable {
    let liveId: String
    let ownerUid: String
    let createdAt: Timestamp?
    let expiresAt: Timestamp
    var consumedByUid: String?
    var consumedAt: Timestamp?
}

struct LiveGameDoc: Codable {
    @DocumentID var id: String?
    let ownerUid: String
    let ownerGameId: String?

    var opponent: String
    var templateName: String?
    var templateId: String?
    
    var createdAt: Timestamp?
    var expiresAt: Timestamp?
    var status: String  // "active" | "ended"

    // --- Shared live state (mirror what your UI needs) ---
    var balls: Int
    var strikes: Int
    var inning: Int
    var hits: Int
    var walks: Int
    var us: Int
    var them: Int

    var batterSide: String?              // "L" / "R"
    var batterSideUpdatedAt: Timestamp?
    var batterSideUpdatedBy: String?

    var selectedBatterId: String?
    var selectedBatterJersey: String?

    var pending: [String: AnyCodable]?
    var resultSelection: String?
}

/// A live game this account joined as a partner, mirrored from
/// `users/{uid}/joinedLiveSessions/{liveId}`. See `LiveGameService.recordJoinedLiveSession`.
struct JoinedLiveSession: Identifiable, Equatable {
    var id: String { liveId }
    let liveId: String
    let ownerUid: String
    let ownerGameId: String?
    let opponent: String
    let joinedAt: Date?

    init?(liveId: String, data: [String: Any]) {
        guard let ownerUid = data["ownerUid"] as? String, !ownerUid.isEmpty else { return nil }
        self.liveId = liveId
        self.ownerUid = ownerUid
        self.ownerGameId = data["ownerGameId"] as? String
        self.opponent = (data["opponent"] as? String) ?? "Live Game"
        self.joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue()
    }
}

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let b = try? c.decode(Bool.self) { value = b; return }
        if let m = try? c.decode([String: AnyCodable].self) { value = m; return }
        if let a = try? c.decode([AnyCodable].self) { value = a; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let b as Bool: try c.encode(b)
        case let m as [String: AnyCodable]: try c.encode(m)
        case let a as [AnyCodable]: try c.encode(a)
        default: try c.encodeNil()
        }
    }
}

// MARK: - LiveGameService

final class LiveGameService {
    static let shared = LiveGameService()
    private init() {}

    private let db = Firestore.firestore()
    private let logPrefix = "🧩 LiveGameService"

    /// How long a live room, join code and invite link stay valid.
    static let sessionLifetime: TimeInterval = 4 * 60 * 60

    /// How close to `expiresAt` the owner starts pushing the window out.
    /// A baseball game routinely runs past a single lifetime, so the session
    /// has to renew itself while it is still in use - see `renewLiveSession`.
    static let renewalWindow: TimeInterval = 45 * 60

    // MARK: Firestore Paths / Keys

    private enum Col {
        static let liveGames = "liveGames"
        static let joinCodes = "joinCodes"
        static let inviteTokens = "inviteTokens"
        static let participants = "participants"
        static let pitchEvents = "pitchEvents"
        static let users = "users"
        static let games = "games"
        static let liveSessions = "liveSessions"
        static let joinedLiveSessions = "joinedLiveSessions"
    }

    private enum Key {
        static let liveId = "liveId"
        static let ownerUid = "ownerUid"
        static let ownerGameId = "ownerGameId"
        static let opponent = "opponent"
        static let templateName = "templateName"
        static let templateId = "templateId"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
        static let status = "status"
        static let inviteToken = "inviteToken"
        static let joinCode = "joinCode"

        static let balls = "balls"
        static let strikes = "strikes"
        static let inning = "inning"
        static let hits = "hits"
        static let walks = "walks"
        static let us = "us"
        static let them = "them"

        static let uid = "uid"
        static let joinedAt = "joinedAt"
        static let lastSeenAt = "lastSeenAt"
        
        static let jerseyNumbers = "jerseyNumbers"
        static let batterIds = "batterIds"
    }

    private enum JoinedSessionKey {
        static let liveId = "liveId"
        static let ownerUid = "ownerUid"
        static let ownerGameId = "ownerGameId"
        static let opponent = "opponent"
        static let joinedAt = "joinedAt"
        static let lastSeenAt = "lastSeenAt"
    }

    private enum LiveStatus {
        static let active = "active"
        static let ended = "ended"
    }

    // MARK: Errors (typed, but still convertible to NSError if needed)

    private enum LiveGameError: LocalizedError {
        case notSignedIn
        case timeout
        case joinCodeNotFound
        case joinCodeExpired
        case malformedJoinCode
        case couldNotGenerateUniqueCode
        case inviteTokenNotFound
        case inviteTokenExpired
        case malformedInviteToken

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Not signed in"
            case .timeout:
                return "Timed out generating code. Check network/App Check and try again."
            case .joinCodeNotFound:
                return "Code not found"
            case .joinCodeExpired:
                return "Code expired"
            case .malformedJoinCode:
                return "Malformed code document"
            case .couldNotGenerateUniqueCode:
                return "Could not generate a unique code. Try again."
            case .inviteTokenNotFound:
                return "Invite link not found"
            case .inviteTokenExpired:
                return "Invite link expired"
            case .malformedInviteToken:
                return "Malformed invite document"
            }
        }

        var nsError: NSError {
            let (domain, code): (String, Int) = {
                switch self {
                case .notSignedIn: return ("Auth", 401)
                case .timeout: return ("LiveGame", 408)
                case .joinCodeNotFound: return ("JoinCode", 404)
                case .joinCodeExpired: return ("JoinCode", 410)
                case .malformedJoinCode: return ("JoinCode", 422)
                case .couldNotGenerateUniqueCode: return ("JoinCode", 500)
                case .inviteTokenNotFound: return ("InviteToken", 404)
                case .inviteTokenExpired: return ("InviteToken", 410)
                case .malformedInviteToken: return ("InviteToken", 422)
                }
            }()
            return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Error"])
        }
    }

    // MARK: - Owner: create live room + join code

    func createLiveGameAndJoinCode(
        ownerGameId: String,
        opponent: String,
        templateId: String?,
        templateName: String?,
        completion: @escaping (Result<(liveId: String, code: String, inviteToken: String), Error>) -> Void
    ) {
        guard let ownerUid = Auth.auth().currentUser?.uid else {
            completion(.failure(LiveGameError.notSignedIn.nsError))
            return
        }

        // Best-effort cleanup (non-blocking).
        cleanupExpiredJoinArtifacts()

        let liveRef = db.collection(Col.liveGames).document()
        let liveId = liveRef.documentID
        let expires = Timestamp(date: Date().addingTimeInterval(Self.sessionLifetime))

        let liveData = makeLiveGamePayload(
            ownerUid: ownerUid,
            ownerGameId: ownerGameId,
            opponent: opponent,
            templateId: templateId,
            templateName: templateName,
            expires: expires
        )

        logCreateLiveStart(liveId: liveId, ownerUid: ownerUid, liveRef: liveRef)

        let finishOnce = finishOnceWrapper(completion)

        // ✅ Hard timeout so the UI never hangs forever
        let gate = CompletionGate()
        let timeoutWork = DispatchWorkItem { [weak gate] in
            guard let gate else { return }
            guard gate.tryFinish() else { return }
            debugLog("❌ \(self.logPrefix) createLiveGameAndJoinCode TIMEOUT after 20s (no Firestore callback) liveId=\(liveId)")
            finishOnce(.failure(LiveGameError.timeout.nsError))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWork)

        liveRef.setData(liveData, merge: false) { [weak self] err in
            guard let self else { return }

            self.logLiveSetDataCallback(liveRef: liveRef, timedOutOrFinished: gate.isFinished, err: err)

            // If timeout already fired, do nothing.
            guard gate.tryFinish() else {
                debugLog("⚠️ \(self.logPrefix) Callback arrived AFTER timeout; ignoring.")
                return
            }

            timeoutWork.cancel()

            debugLog("✅ \(self.logPrefix) liveGames setData succeeded liveId=\(liveId). Seeding lineup…")
            self.seedLiveLineupFromOwnerGame(ownerUid: ownerUid, ownerGameId: ownerGameId, liveId: liveId)

            debugLog("✅ \(self.logPrefix) Creating join code…")
            self.createUniqueJoinCode(
                liveId: liveId,
                ownerUid: ownerUid,
                expiresAt: expires
            ) { result in
                switch result {
                case .success(let join):
                    self.setActiveSessionCode(ownerUid: ownerUid, gameId: ownerGameId, code: join.code) { _ in
                        self.createInviteToken(liveId: liveId, ownerUid: ownerUid, expiresAt: expires) { tokenResult in
                            switch tokenResult {
                            case .success(let token):
                                self.recordOwnerSessionCredentials(
                                    ownerUid: ownerUid,
                                    liveId: liveId,
                                    joinCode: join.code,
                                    inviteToken: token
                                )
                                finishOnce(.success((liveId: join.liveId, code: join.code, inviteToken: token)))
                            case .failure(let err):
                                finishOnce(.failure(err))
                            }
                        }
                    }
                case .failure(let err):
                    finishOnce(.failure(err))
                }
            }
        }
        
    }

    private func createInviteToken(
        liveId: String,
        ownerUid: String,
        expiresAt: Timestamp,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        func attempt(_ n: Int) {
            if n > 4 {
                completion(.failure(LiveGameError.couldNotGenerateUniqueCode.nsError))
                return
            }

            let token = randomInviteToken(length: 24)
            let ref = db.collection(Col.inviteTokens).document(token)

            db.runTransaction({ txn, errPtr -> Any? in
                do {
                    let snap = try txn.getDocument(ref)
                    if snap.exists {
                        errPtr?.pointee = NSError(domain: "InviteToken", code: 409,
                                                  userInfo: [NSLocalizedDescriptionKey: "Invite token collision"])
                        return nil
                    }

                    txn.setData([
                        Key.liveId: liveId,
                        Key.ownerUid: ownerUid,
                        Key.expiresAt: expiresAt,
                        Key.createdAt: FieldValue.serverTimestamp()
                    ], forDocument: ref)
                    return nil
                } catch let e as NSError {
                    errPtr?.pointee = e
                    return nil
                }
            }) { _, error in
                if let nsError = error as NSError? {
                    if nsError.domain == "InviteToken", nsError.code == 409 {
                        attempt(n + 1)
                        return
                    }
                    completion(.failure(nsError))
                    return
                }
                completion(.success(token))
            }
        }

        attempt(0)
    }

    private func seedLiveLineupFromOwnerGame(ownerUid: String, ownerGameId: String, liveId: String) {
        let gameRef = db.collection(Col.users).document(ownerUid)
            .collection(Col.games).document(ownerGameId)

        gameRef.getDocument { [weak self] snap, err in
            guard let self else { return }

            if let err {
                debugLog("⚠️ \(self.logPrefix) seed lineup: failed to read owner game doc:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                debugLog("⚠️ \(self.logPrefix) seed lineup: owner game doc missing data")
                return
            }

            let jerseys = (data["jerseyNumbers"] as? [String]) ?? []
            let batterIds = (data["batterIds"] as? [String]) ?? []

            // Only seed if there is something to seed
            guard !jerseys.isEmpty else {
                debugLog("ℹ️ \(self.logPrefix) seed lineup: owner game has no jerseys; skipping")
                return
            }

            // If batterIds missing/mismatched, generate stable ids so participants can select reliably
            let finalIds: [String]
            if batterIds.count == jerseys.count, !batterIds.isEmpty {
                finalIds = batterIds
            } else {
                finalIds = jerseys.map { _ in UUID().uuidString }
            }

            self.db.collection(Col.liveGames).document(liveId).updateData([
                "jerseyNumbers": jerseys,
                "batterIds": finalIds
            ]) { err in
                if let err {
                    debugLog("⚠️ \(self.logPrefix) seed lineup: update live doc failed:", err.localizedDescription)
                } else {
                    debugLog("✅ \(self.logPrefix) seed lineup: copied \(jerseys.count) jerseys into liveGames/\(liveId)")
                }
            }
        }
    }

    private func setActiveSessionCode(
        ownerUid: String,
        gameId: String,
        code: String,
        completion: @escaping (Bool) -> Void
    ) {
        db.collection(Col.users).document(ownerUid)
            .collection(Col.games).document(gameId)
            .setData([
                "activeSessionCode": code
            ], merge: true) { err in
                if let err {
                    debugLog("⚠️ \(self.logPrefix) set activeSessionCode failed:", err.localizedDescription)
                    completion(false)
                    return
                }
                debugLog("✅ \(self.logPrefix) set activeSessionCode=\(code) on users/\(ownerUid)/games/\(gameId)")
                completion(true)
            }
    }
    
    // MARK: - Session lifetime

    /// Stores which code and invite link reach a room, in the owner's private
    /// tree, so the owner can still renew them after a relaunch.
    ///
    /// Deliberately **not** on the live document. `/liveGames/{liveId}` is
    /// readable by display participants and display-only sessions
    /// (firestore.rules), which are meant to render a called pitch and nothing
    /// else - putting the tracker join code there would let a display device
    /// read it and rejoin as a full participant with write access to pitch
    /// events. `users/{uid}/**` is owner-only.
    private func recordOwnerSessionCredentials(
        ownerUid: String,
        liveId: String,
        joinCode: String,
        inviteToken: String
    ) {
        db.collection(Col.users).document(ownerUid)
            .collection(Col.liveSessions).document(liveId)
            .setData([
                Key.liveId: liveId,
                Key.joinCode: joinCode,
                Key.inviteToken: inviteToken,
                Key.createdAt: FieldValue.serverTimestamp()
            ], merge: true) { err in
                if let err {
                    debugLog("⚠️ \(self.logPrefix) could not record owner session credentials:", err.localizedDescription)
                }
            }
    }

    /// Pushes `expiresAt` out on the room and on the credentials that reach it.
    ///
    /// A room was created with a fixed 4h window that nothing ever renewed.
    /// Past that mark the participant's live listener stops treating the room
    /// as active, so called pitches silently stop arriving mid-game, and a
    /// partner who has to rejoin finds a dead code. Owner-only: rules pin
    /// `expiresAt` for participant writes.
    ///
    /// Credentials are looked up from the owner's private record; `ownerGameId`
    /// gives a fallback for rooms created before that record existed, whose
    /// join code is still recoverable from the game's `activeSessionCode`.
    /// Renewing the code matters as much as renewing the room:
    /// `cleanupExpiredJoinArtifacts` deletes expired code documents, and
    /// `isActiveParticipantForThisGame` needs one to exist.
    ///
    /// The writes are deliberately independent rather than batched - a code
    /// that was already reaped would otherwise take the room's renewal with it.
    func renewLiveSession(
        liveId: String,
        ownerGameId: String?,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard let ownerUid = Auth.auth().currentUser?.uid else {
            completion?(LiveGameError.notSignedIn.nsError)
            return
        }

        let extended = Timestamp(date: Date().addingTimeInterval(Self.sessionLifetime))
        let fields: [String: Any] = [Key.expiresAt: extended]

        db.collection(Col.liveGames).document(liveId).updateData(fields) { err in
            if let err {
                debugLog("⚠️ \(self.logPrefix) renew live room failed:", err.localizedDescription)
            } else {
                debugLog("♻️ \(self.logPrefix) renewed live room \(liveId) until \(extended.dateValue())")
            }
            completion?(err)
        }

        resolveOwnerSessionCredentials(ownerUid: ownerUid, liveId: liveId, ownerGameId: ownerGameId) { code, token in
            if let code, !code.isEmpty {
                self.db.collection(Col.joinCodes).document(code).updateData(fields) { err in
                    if let err {
                        debugLog("⚠️ \(self.logPrefix) renew join code failed:", err.localizedDescription)
                    }
                }
            }
            if let token, !token.isEmpty {
                self.db.collection(Col.inviteTokens).document(token).updateData(fields) { err in
                    if let err {
                        debugLog("⚠️ \(self.logPrefix) renew invite token failed:", err.localizedDescription)
                    }
                }
            }
        }
    }

    private func resolveOwnerSessionCredentials(
        ownerUid: String,
        liveId: String,
        ownerGameId: String?,
        completion: @escaping (String?, String?) -> Void
    ) {
        db.collection(Col.users).document(ownerUid)
            .collection(Col.liveSessions).document(liveId)
            .getDocument { snap, _ in
                if let data = snap?.data() {
                    completion(data[Key.joinCode] as? String, data[Key.inviteToken] as? String)
                    return
                }

                // Room predates the private record. The invite token is not
                // recoverable, but the join code is mirrored onto the game as
                // `activeSessionCode`, and that is the credential whose expiry
                // gates participant access.
                guard let gameId = ownerGameId, !gameId.isEmpty else {
                    completion(nil, nil)
                    return
                }
                self.db.collection(Col.users).document(ownerUid)
                    .collection(Col.games).document(gameId)
                    .getDocument { gameSnap, _ in
                        completion(gameSnap?.data()?["activeSessionCode"] as? String, nil)
                    }
            }
    }

    /// Marks a room finished.
    ///
    /// Nothing wrote this before, so `LiveStatus.ended` and the client's
    /// "ended remotely" handling were both dead code: the owner's disconnect
    /// only tore down the owner's own session, leaving the partner connected
    /// and still recording into a room nobody was mirroring.
    func endLiveSession(liveId: String, completion: ((Error?) -> Void)? = nil) {
        updateLiveFields(
            liveId: liveId,
            fields: [
                Key.status: LiveStatus.ended,
                "endedAt": FieldValue.serverTimestamp()
            ],
            completion: completion
        )
    }

    // MARK: - Cleanup (Client-Side)

    func cleanupExpiredJoinArtifacts() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let now = Timestamp(date: Date())
        cleanupExpired(in: Col.joinCodes, ownerUid: uid, now: now)
        cleanupExpired(in: Col.inviteTokens, ownerUid: uid, now: now)
    }

    private func cleanupExpired(in collection: String, ownerUid: String, now: Timestamp) {
        db.collection(collection)
            .whereField(Key.ownerUid, isEqualTo: ownerUid)
            .whereField(Key.expiresAt, isLessThan: now)
            .limit(to: 200)
            .getDocuments { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    debugLog("⚠️ \(self.logPrefix) cleanup \(collection) failed:", err.localizedDescription)
                    return
                }
                let docs = snap?.documents ?? []
                guard !docs.isEmpty else { return }

                let batch = self.db.batch()
                for doc in docs {
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { err in
                    if let err {
                        debugLog("⚠️ \(self.logPrefix) cleanup \(collection) batch failed:", err.localizedDescription)
                    } else {
                        debugLog("✅ \(self.logPrefix) cleanup \(collection) deleted \(docs.count)")
                        if docs.count == 200 {
                            self.cleanupExpired(in: collection, ownerUid: ownerUid, now: now)
                        }
                    }
                }
            }
    }

    // MARK: - Join Code Generation (transaction)

    private func createUniqueJoinCode(
        liveId: String,
        ownerUid: String,
        expiresAt: Timestamp,
        maxAttempts: Int = 10,
        completion: @escaping (Result<(liveId: String, code: String), Error>) -> Void
    ) {
        func makeCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

        func attempt(_ n: Int) {
            if n >= maxAttempts {
                completion(.failure(LiveGameError.couldNotGenerateUniqueCode.nsError))
                return
            }

            let code = makeCode()
            let codeRef = db.collection(Col.joinCodes).document(code)

            db.runTransaction({ txn, errPtr -> Any? in
                do {
                    let snap = try txn.getDocument(codeRef)
                    if snap.exists {
                        errPtr?.pointee = NSError(domain: "JoinCode", code: 409, userInfo: [NSLocalizedDescriptionKey: "Code exists"])
                        return nil
                    }
                    txn.setData([
                        Key.liveId: liveId,
                        Key.ownerUid: ownerUid,
                        Key.expiresAt: expiresAt,
                        Key.createdAt: FieldValue.serverTimestamp()
                    ], forDocument: codeRef, merge: false)
                    return nil
                } catch let e as NSError {
                    errPtr?.pointee = e
                    return nil
                }
            }) { _, error in
                if let nsError = error as NSError? {
                    debugLog("❌ \(self.logPrefix) joinCodes transaction failed domain=\(nsError.domain) code=\(nsError.code) msg=\(nsError.localizedDescription)")

                    if nsError.domain == "JoinCode", nsError.code == 409 {
                        attempt(n + 1)
                        return
                    }

                    completion(.failure(nsError))
                    return
                }

                debugLog("✅ \(self.logPrefix) joinCodes transaction succeeded code=\(code) liveId=\(liveId)")
                completion(.success((liveId: liveId, code: code)))
            }
        }

        attempt(0)
    }

    // MARK: - Participant: resolve code + join live room

    func joinLiveGame(
        code: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(LiveGameError.notSignedIn.nsError))
            return
        }

        let codeRef = db.collection(Col.joinCodes).document(code)
        codeRef.getDocument { [weak self] snap, err in
            guard let self else { return }

            if let err { completion(.failure(err)); return }
            guard let snap, snap.exists, let data = snap.data() else {
                completion(.failure(LiveGameError.joinCodeNotFound.nsError))
                return
            }

            if let expiresAt = data[Key.expiresAt] as? Timestamp, expiresAt.dateValue() < Date() {
                completion(.failure(LiveGameError.joinCodeExpired.nsError))
                return
            }

            guard let liveId = data[Key.liveId] as? String else {
                completion(.failure(LiveGameError.malformedJoinCode.nsError))
                return
            }

            let ownerUid = data[Key.ownerUid] as? String ?? ""
            self.upsertPresence(liveId: liveId, uid: uid) { result in
                switch result {
                case .success:
                    self.recordJoinedLiveSession(liveId: liveId, ownerUid: ownerUid)
                    completion(.success(liveId))
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    func joinLiveGameByInviteToken(
        token: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(LiveGameError.notSignedIn.nsError))
            return
        }

        let ref = db.collection(Col.inviteTokens).document(token)
        ref.getDocument { [weak self] snap, err in
            guard let self else { return }
            if let err { completion(.failure(err)); return }
            guard let snap, snap.exists, let data = snap.data() else {
                completion(.failure(LiveGameError.inviteTokenNotFound.nsError))
                return
            }

            if let expiresAt = data[Key.expiresAt] as? Timestamp, expiresAt.dateValue() < Date() {
                completion(.failure(LiveGameError.inviteTokenExpired.nsError))
                return
            }

            guard let liveId = data[Key.liveId] as? String else {
                completion(.failure(LiveGameError.malformedInviteToken.nsError))
                return
            }

            let ownerUid = data[Key.ownerUid] as? String ?? ""
            self.upsertPresence(liveId: liveId, uid: uid) { result in
                switch result {
                case .success:
                    self.recordJoinedLiveSession(liveId: liveId, ownerUid: ownerUid)
                    completion(.success(liveId))
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    // MARK: - Presence

    private func upsertPresence(
        liveId: String,
        uid: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let presenceRef = db.collection(Col.liveGames).document(liveId)
            .collection(Col.participants).document(uid)

        presenceRef.setData([
            Key.uid: uid,
            Key.joinedAt: FieldValue.serverTimestamp(),
            Key.lastSeenAt: FieldValue.serverTimestamp()
        ], merge: true) { err in
            if let err { completion(.failure(err)); return }

            // ✅ Hard connection state: mark connected on join
            self.db.collection(Col.liveGames).document(liveId).updateData([
                "connection": [
                    "participantUid": uid,
                    "connected": true,
                    "connectedAt": FieldValue.serverTimestamp()
                ]
            ]) { updateErr in
                if let updateErr { completion(.failure(updateErr)); return }
                completion(.success(()))
            }
        }
    }

    // MARK: - Participant: joined-session bookmark

    /// Lets a partner see the game they joined in their own "My Games" list
    /// and re-enter it after leaving the screen, backgrounding, or closing
    /// the app - `activeLiveId` alone only survives on the one device that
    /// wrote it to `UserDefaults`. Lives under the participant's own account
    /// (`users/{uid}/joinedLiveSessions/{liveId}`), separate from
    /// `liveGames/{liveId}/participants/{uid}` (room-scoped presence, deleted
    /// by `endLiveSessionLocally`) and `users/{ownerUid}/liveSessions/{liveId}`
    /// (owner-only credentials). `opponent`/`ownerGameId` are best-effort here;
    /// the participant's live-room listener keeps them fresh afterward.
    func recordJoinedLiveSession(
        liveId: String,
        ownerUid: String,
        ownerGameId: String? = nil,
        opponent: String? = nil
    ) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            JoinedSessionKey.liveId: liveId,
            JoinedSessionKey.ownerUid: ownerUid,
            JoinedSessionKey.joinedAt: FieldValue.serverTimestamp(),
            JoinedSessionKey.lastSeenAt: FieldValue.serverTimestamp()
        ]
        if let ownerGameId, !ownerGameId.isEmpty { data[JoinedSessionKey.ownerGameId] = ownerGameId }
        if let opponent, !opponent.isEmpty { data[JoinedSessionKey.opponent] = opponent }

        db.collection(Col.users).document(uid)
            .collection(Col.joinedLiveSessions).document(liveId)
            .setData(data, merge: true) { err in
                if let err {
                    debugLog("⚠️ \(self.logPrefix) recordJoinedLiveSession failed:", err.localizedDescription)
                }
            }
    }

    /// Called once a session is truly over for this participant - the owner
    /// ended it, the room is gone, or it expired unrenewed - so it stops
    /// showing up as re-enterable in the games list. Also called from the
    /// participant's own explicit "Disconnect".
    func removeJoinedLiveSession(liveId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection(Col.users).document(uid)
            .collection(Col.joinedLiveSessions).document(liveId)
            .delete { err in
                if let err {
                    debugLog("⚠️ \(self.logPrefix) removeJoinedLiveSession failed:", err.localizedDescription)
                }
            }
    }

    func heartbeatPresence(liveId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let presenceRef = db.collection(Col.liveGames).document(liveId)
            .collection(Col.participants).document(uid)
        // Keep the UID on every heartbeat. If a presence document is recreated
        // while account deletion is running, the server can still find and
        // remove it with the collection-group UID query.
        presenceRef.setData([
            Key.uid: uid,
            Key.lastSeenAt: FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - Shared writes

    func updateLiveFields(
        liveId: String,
        fields: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        let keys = Array(fields.keys).sorted()
        debugLog("📤 updateLiveFields → \(Col.liveGames)/\(liveId)")
        debugLog("📤 keys:", keys)

        db.collection(Col.liveGames).document(liveId).updateData(fields) { err in
            if let err {
                debugLog("❌ updateLiveFields failed:", err.localizedDescription)
            } else {
                debugLog("✅ updateLiveFields success")
            }
            completion?(err)
        }
    }
    
    // MARK: - Lineup writes (LIVE)

    // Applies `mutate` to the lineup as it currently exists on the server, inside a
    // transaction, then writes the result back. Owner and participant can edit the
    // lineup from two different devices at nearly the same moment; a plain
    // updateData(fields:) built from a device's local jerseyCells silently clobbers
    // whatever the other device just wrote, because it overwrites the whole array
    // using a possibly-stale local copy as the base. Reading the live server copy
    // inside the transaction and mutating that instead makes concurrent add/edit/
    // reorder from both sides converge instead of racing.
    func mutateLiveLineup(
        liveId: String,
        mutate: @escaping (_ jerseys: inout [String], _ batterIds: inout [String]) -> Void,
        completion: ((Result<(jerseys: [String], batterIds: [String]), Error>) -> Void)? = nil
    ) {
        let liveRef = db.collection(Col.liveGames).document(liveId)

        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let snap = try txn.getDocument(liveRef)
                guard snap.exists, let data = snap.data() else { return nil }

                var jerseys = (data["jerseyNumbers"] as? [String]) ?? []
                var batterIds = (data["batterIds"] as? [String]) ?? []

                mutate(&jerseys, &batterIds)

                txn.updateData([
                    "jerseyNumbers": jerseys,
                    "batterIds": batterIds
                ], forDocument: liveRef)

                return ["jerseyNumbers": jerseys, "batterIds": batterIds]
            } catch let e as NSError {
                errPtr?.pointee = e
                return nil
            }
        }) { result, err in
            if let err {
                debugLog("❌ mutateLiveLineup failed:", err.localizedDescription)
                completion?(.failure(err))
                return
            }
            guard let dict = result as? [String: Any],
                  let jerseys = dict["jerseyNumbers"] as? [String],
                  let batterIds = dict["batterIds"] as? [String] else {
                completion?(.failure(NSError(domain: "LiveGame", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "mutateLiveLineup: malformed transaction result"])))
                return
            }
            debugLog("✅ mutateLiveLineup success")
            completion?(.success((jerseys, batterIds)))
        }
    }

    // MARK: - Progress writes (LIVE)

    // A plain `updateLiveFields` call let two devices race: each computes
    // "progressRevision" from its own last-known value and writes that guess,
    // so two nearly-simultaneous writes can carry the *same* revision number.
    // Whichever commit lands second in Firestore then gets silently dropped by
    // the other device's `remoteRevision > progressRevision` check, even
    // though it carries the real, later state (e.g. a 3rd-out reset landing
    // right after the flash). Reading the server's revision inside a
    // transaction and incrementing it there — the same pattern as
    // `mutateLiveLineup` — ties the number to actual commit order instead of
    // to two devices' stale local guesses, so it always strictly increases
    // and never collides.
    func commitLiveProgress(
        liveId: String,
        fields: [String: Any],
        completion: ((Result<Int, Error>) -> Void)? = nil
    ) {
        let liveRef = db.collection(Col.liveGames).document(liveId)

        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let snap = try txn.getDocument(liveRef)
                let currentRevision = (snap.data()?["progressRevision"] as? Int) ?? 0
                let nextRevision = currentRevision + 1

                var payload = fields
                payload["progressRevision"] = nextRevision
                payload["progressUpdatedAt"] = FieldValue.serverTimestamp()

                txn.updateData(payload, forDocument: liveRef)
                return nextRevision
            } catch let e as NSError {
                errPtr?.pointee = e
                return nil
            }
        }) { result, err in
            if let err {
                debugLog("❌ commitLiveProgress failed:", err.localizedDescription)
                completion?(.failure(err))
                return
            }
            guard let nextRevision = result as? Int else {
                completion?(.failure(NSError(domain: "LiveGame", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "commitLiveProgress: malformed transaction result"])))
                return
            }
            debugLog("✅ commitLiveProgress success rev=\(nextRevision)")
            completion?(.success(nextRevision))
        }
    }

    func addLivePitchEvent(
        liveId: String,
        eventData: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection(Col.liveGames).document(liveId)
            .collection(Col.pitchEvents).document()
            .setData(eventData, merge: false, completion: completion)
    }

    // MARK: - Payload / Logging Helpers

    private func makeLiveGamePayload(
        ownerUid: String,
        ownerGameId: String,
        opponent: String,
        templateId: String?,
        templateName: String?,
        expires: Timestamp
    ) -> [String: Any] {
        [
            Key.ownerUid: ownerUid,
            Key.ownerGameId: ownerGameId,
            Key.opponent: opponent,

            // ✅ Template flow
            Key.templateId: templateId as Any,
            Key.templateName: templateName as Any,

            Key.createdAt: FieldValue.serverTimestamp(),
            Key.expiresAt: expires,
            Key.status: LiveStatus.active,

            // Hard connection state
            "connection": [
                "ownerUid": ownerUid,
                "participantUid": NSNull(),
                "connected": false
            ],

            // Scoreboard defaults
            Key.balls: 0,
            Key.strikes: 0,
            Key.inning: 1,
            Key.hits: 0,
            Key.walks: 0,
            Key.us: 0,
            Key.them: 0,

            // Lineup defaults (keep this)
            "jerseyNumbers": [],
            "batterIds": []
        ]
    }

    private func logCreateLiveStart(liveId: String, ownerUid: String, liveRef: DocumentReference) {
        debugLog("\(logPrefix) createLiveGameAndJoinCode: writing \(Col.liveGames)/\(liveId) as uid=\(ownerUid)")
        debugLog("\(logPrefix) About to write:", liveRef.path)
        debugLog("\(logPrefix) joinCodes collection:", db.collection(Col.joinCodes).path)
        debugLog("\(logPrefix) joinCodes ownerUid:", ownerUid)
    }

    private func logLiveSetDataCallback(liveRef: DocumentReference, timedOutOrFinished: Bool, err: Error?) {
        debugLog("\(logPrefix) liveGames setData callback fired for \(liveRef.path) finished=\(timedOutOrFinished) err=\(err?.localizedDescription ?? "nil")")
    }
    
    private func randomInviteToken(length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            if let c = chars.randomElement() { result.append(c) }
        }
        return result
    }
    
    
}

// MARK: - Small Utilities (completion gating)

/// Ensures a closure is only invoked once (thread-safe).
private func finishOnceWrapper<T>(
    _ completion: @escaping (Result<T, Error>) -> Void
) -> (Result<T, Error>) -> Void {
    let lock = NSLock()
    var didFinish = false
    return { result in
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        completion(result)
    }
}

/// Used to guard racey paths like timeout + Firestore callback.
private final class CompletionGate {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    /// Returns true if it successfully marked finished (i.e. first finisher)
    func tryFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }
}

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

    // MARK: Firestore Paths / Keys

    private enum Col {
        static let liveGames = "liveGames"
        static let joinCodes = "joinCodes"
        static let participants = "participants"
        static let pitchEvents = "pitchEvents"
        static let users = "users"
        static let games = "games"
    }

    private enum Key {
        static let liveId = "liveId"
        static let ownerUid = "ownerUid"
        static let ownerGameId = "ownerGameId"
        static let opponent = "opponent"
        static let templateName = "templateName"

        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
        static let status = "status"

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
                }
            }()
            return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: errorDescription ?? "Error"])
        }
    }

    // MARK: - Owner: create live room + join code

    func createLiveGameAndJoinCode(
        ownerGameId: String,
        opponent: String,
        templateName: String?,
        completion: @escaping (Result<(liveId: String, code: String), Error>) -> Void
    ) {
        guard let ownerUid = Auth.auth().currentUser?.uid else {
            completion(.failure(LiveGameError.notSignedIn.nsError))
            return
        }

        let liveRef = db.collection(Col.liveGames).document()
        let liveId = liveRef.documentID
        let expires = Timestamp(date: Date().addingTimeInterval(2 * 60 * 60))

        let liveData = makeLiveGamePayload(
            ownerUid: ownerUid,
            ownerGameId: ownerGameId,
            opponent: opponent,
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
            print("❌ \(self.logPrefix) createLiveGameAndJoinCode TIMEOUT after 20s (no Firestore callback) liveId=\(liveId)")
            finishOnce(.failure(LiveGameError.timeout.nsError))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWork)

        liveRef.setData(liveData, merge: false) { [weak self] err in
            guard let self else { return }

            self.logLiveSetDataCallback(liveRef: liveRef, timedOutOrFinished: gate.isFinished, err: err)

            // If timeout already fired, do nothing.
            guard gate.tryFinish() else {
                print("⚠️ \(self.logPrefix) Callback arrived AFTER timeout; ignoring.")
                return
            }

            timeoutWork.cancel()

            print("✅ \(self.logPrefix) liveGames setData succeeded liveId=\(liveId). Seeding lineup…")
            self.seedLiveLineupFromOwnerGame(ownerUid: ownerUid, ownerGameId: ownerGameId, liveId: liveId)

            print("✅ \(self.logPrefix) Creating join code…")
            self.createUniqueJoinCode(
                liveId: liveId,
                ownerUid: ownerUid,
                expiresAt: expires,
                completion: finishOnce
            )
        }
        
    }
    private func seedLiveLineupFromOwnerGame(ownerUid: String, ownerGameId: String, liveId: String) {
        let gameRef = db.collection(Col.users).document(ownerUid)
            .collection(Col.games).document(ownerGameId)

        gameRef.getDocument { [weak self] snap, err in
            guard let self else { return }

            if let err {
                print("⚠️ \(self.logPrefix) seed lineup: failed to read owner game doc:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                print("⚠️ \(self.logPrefix) seed lineup: owner game doc missing data")
                return
            }

            let jerseys = (data["jerseyNumbers"] as? [String]) ?? []
            let batterIds = (data["batterIds"] as? [String]) ?? []

            // Only seed if there is something to seed
            guard !jerseys.isEmpty else {
                print("ℹ️ \(self.logPrefix) seed lineup: owner game has no jerseys; skipping")
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
                    print("⚠️ \(self.logPrefix) seed lineup: update live doc failed:", err.localizedDescription)
                } else {
                    print("✅ \(self.logPrefix) seed lineup: copied \(jerseys.count) jerseys into liveGames/\(liveId)")
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
                    print("❌ \(self.logPrefix) joinCodes transaction failed domain=\(nsError.domain) code=\(nsError.code) msg=\(nsError.localizedDescription)")

                    if nsError.domain == "JoinCode", nsError.code == 409 {
                        attempt(n + 1)
                        return
                    }

                    completion(.failure(nsError))
                    return
                }

                print("✅ \(self.logPrefix) joinCodes transaction succeeded code=\(code) liveId=\(liveId)")
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

            self.upsertPresence(liveId: liveId, uid: uid) { result in
                switch result {
                case .success:
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
            completion(.success(()))
        }
    }

    func heartbeatPresence(liveId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let presenceRef = db.collection(Col.liveGames).document(liveId)
            .collection(Col.participants).document(uid)
        presenceRef.setData([Key.lastSeenAt: FieldValue.serverTimestamp()], merge: true)
    }

    // MARK: - Shared writes

    func updateLiveFields(
        liveId: String,
        fields: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        let keys = Array(fields.keys).sorted()
        print("📤 updateLiveFields → \(Col.liveGames)/\(liveId)")
        print("📤 keys:", keys)

        db.collection(Col.liveGames).document(liveId).updateData(fields) { err in
            if let err {
                print("❌ updateLiveFields failed:", err.localizedDescription)
            } else {
                print("✅ updateLiveFields success")
            }
            completion?(err)
        }
    }
    
    // MARK: - Lineup writes (LIVE)
    func addLiveJersey(
        liveId: String,
        jerseyNumber: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        let liveRef = db.collection("liveGames").document(liveId)

        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let snap = try txn.getDocument(liveRef)
                guard snap.exists, let data = snap.data() else { return nil }

                var jerseys = (data["jerseyNumbers"] as? [String]) ?? []
                var batterIds = (data["batterIds"] as? [String]) ?? []

                // normalize
                let trimmed = jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                // prevent duplicates (optional)
                if jerseys.contains(trimmed) {
                    errPtr?.pointee = NSError(domain: "LiveGame", code: 409,
                                              userInfo: [NSLocalizedDescriptionKey: "Jersey already exists"])
                    return nil
                }

                jerseys.append(trimmed)
                batterIds.append(UUID().uuidString)

                txn.updateData([
                    "jerseyNumbers": jerseys,
                    "batterIds": batterIds
                ], forDocument: liveRef)

                return nil
            } catch let e as NSError {
                errPtr?.pointee = e
                return nil
            }
        }) { _, err in
            if let err {
                print("❌ addLiveJersey failed:", err.localizedDescription)
            } else {
                print("✅ addLiveJersey success jersey=\(jerseyNumber)")
            }
            completion?(err)
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
        templateName: String?,
        expires: Timestamp
    ) -> [String: Any] {
        [
            Key.ownerUid: ownerUid,
            Key.ownerGameId: ownerGameId,
            Key.opponent: opponent,
            Key.templateName: templateName as Any,
            Key.createdAt: FieldValue.serverTimestamp(),
            Key.expiresAt: expires,
            Key.status: LiveStatus.active,

            // Scoreboard defaults
            Key.balls: 0,
            Key.strikes: 0,
            Key.inning: 1,
            Key.hits: 0,
            Key.walks: 0,
            Key.us: 0,
            Key.them: 0,

            // ✅ Lineup defaults (critical so participant never sees "missing fields")
            "jerseyNumbers": [],
            "batterIds": []
        ]
    }

    private func logCreateLiveStart(liveId: String, ownerUid: String, liveRef: DocumentReference) {
        print("\(logPrefix) createLiveGameAndJoinCode: writing \(Col.liveGames)/\(liveId) as uid=\(ownerUid)")
        print("\(logPrefix) About to write:", liveRef.path)
        print("\(logPrefix) joinCodes collection:", db.collection(Col.joinCodes).path)
        print("\(logPrefix) joinCodes ownerUid:", ownerUid)
    }

    private func logLiveSetDataCallback(liveRef: DocumentReference, timedOutOrFinished: Bool, err: Error?) {
        print("\(logPrefix) liveGames setData callback fired for \(liveRef.path) finished=\(timedOutOrFinished) err=\(err?.localizedDescription ?? "nil")")
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

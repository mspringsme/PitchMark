//
//  JoinCodeDoc.swift
//  PitchMark
//
//  Created by Mark Springer on 2/22/26.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore

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
    var status: String // "active" | "ended"

    // --- Shared live state (mirror what your UI needs) ---
    var balls: Int
    var strikes: Int
    var inning: Int
    var hits: Int
    var walks: Int
    var us: Int
    var them: Int

    var batterSide: String?              // "L" / "R" (or your enum rawValue)
    var batterSideUpdatedAt: Timestamp?
    var batterSideUpdatedBy: String?

    var selectedBatterId: String?
    var selectedBatterJersey: String?

    // “pending” / “resultSelection” can stay if your UI needs them
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

final class LiveGameService {
    static let shared = LiveGameService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Owner: create live room + join code
    func createLiveGameAndJoinCode(
        ownerGameId: String,
        opponent: String,
        templateName: String?,
        completion: @escaping (Result<(liveId: String, code: String), Error>) -> Void
    ) {
        guard let ownerUid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let liveRef = db.collection("liveGames").document()
        let liveId = liveRef.documentID

        let expires = Timestamp(date: Date().addingTimeInterval(2 * 60 * 60))

        let liveData: [String: Any] = [
            "ownerUid": ownerUid,
            "ownerGameId": ownerGameId,
            "opponent": opponent,
            "templateName": templateName as Any,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": expires,
            "status": "active",
            "balls": 0,
            "strikes": 0,
            "inning": 1,
            "hits": 0,
            "walks": 0,
            "us": 0,
            "them": 0
        ]

        print("🧩 createLiveGameAndJoinCode: writing liveGames/\(liveId) as uid=\(ownerUid)")

        // ✅ Hard timeout so the UI never hangs forever
        var finished = false
        let timeoutWork = DispatchWorkItem {
            guard !finished else { return }
            finished = true
            print("❌ createLiveGameAndJoinCode TIMEOUT after 20s (no Firestore callback) liveId=\(liveId)")
            completion(.failure(NSError(domain: "LiveGame", code: 408, userInfo: [NSLocalizedDescriptionKey: "Timed out generating code. Check network/App Check and try again."])))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWork)
        print("🧩 About to write:", liveRef.path)
        print("🧩 joinCodes collection:", db.collection("joinCodes").path)
        print("🧩 joinCodes ownerUid:", ownerUid)


        liveRef.setData(liveData, merge: false) { [weak self] err in
            // ✅ Always log when callback fires (even after timeout)
            print("🧩 liveGames setData callback fired for \(liveRef.path) finished=\(finished) err=\(err?.localizedDescription ?? "nil")")

            if finished {
                print("⚠️ Callback arrived AFTER timeout; ignoring because UI already failed.")
                return
            }

            finished = true
            timeoutWork.cancel()

            if let err {
                print("❌ liveGames setData failed:", err.localizedDescription)
                completion(.failure(err))
                return
            }

            print("✅ liveGames setData succeeded liveId=\(liveId). Creating join code…")
            self?.createUniqueJoinCode(liveId: liveId, ownerUid: ownerUid, expiresAt: expires, completion: completion)
        }
    }


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
                completion(.failure(NSError(domain: "JoinCode", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not generate a unique code. Try again."])))
                return
            }

            let code = makeCode()
            let codeRef = db.collection("joinCodes").document(code)

            db.runTransaction({ txn, errPtr -> Any? in
                do {
                    let snap = try txn.getDocument(codeRef)
                    if snap.exists {
                        errPtr?.pointee = NSError(domain: "JoinCode", code: 409, userInfo: [NSLocalizedDescriptionKey: "Code exists"])
                        return nil
                    }
                    txn.setData([
                        "liveId": liveId,
                        "ownerUid": ownerUid,
                        "expiresAt": expiresAt,
                        "createdAt": FieldValue.serverTimestamp()
                    ], forDocument: codeRef, merge: false)
                    return nil
                } catch let e as NSError {
                    errPtr?.pointee = e
                    return nil
                }
            }) { _, error in
                if let nsError = error as NSError? {
                    print("❌ joinCodes transaction failed domain=\(nsError.domain) code=\(nsError.code) msg=\(nsError.localizedDescription)")

                    if nsError.domain == "JoinCode" && nsError.code == 409 {
                        attempt(n + 1)
                        return
                    }

                    completion(.failure(nsError))
                    return
                }

                print("✅ joinCodes transaction succeeded code=\(code) liveId=\(liveId)")
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
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let codeRef = db.collection("joinCodes").document(code)
        codeRef.getDocument { [weak self] snap, err in
            if let err { completion(.failure(err)); return }
            guard let snap, snap.exists, let data = snap.data() else {
                completion(.failure(NSError(domain: "JoinCode", code: 404, userInfo: [NSLocalizedDescriptionKey: "Code not found"])))
                return
            }

            if let expiresAt = data["expiresAt"] as? Timestamp, expiresAt.dateValue() < Date() {
                completion(.failure(NSError(domain: "JoinCode", code: 410, userInfo: [NSLocalizedDescriptionKey: "Code expired"])))
                return
            }

            guard let liveId = data["liveId"] as? String else {
                completion(.failure(NSError(domain: "JoinCode", code: 422, userInfo: [NSLocalizedDescriptionKey: "Malformed code document"])))
                return
            }

            self?.upsertPresence(liveId: liveId, uid: uid) { result in
                switch result {
                case .success:
                    completion(.success(liveId))
                case .failure(let e):
                    completion(.failure(e))
                }
            }
        }
    }

    private func upsertPresence(
        liveId: String,
        uid: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let presenceRef = db.collection("liveGames").document(liveId)
            .collection("participants").document(uid)

        presenceRef.setData([
            "uid": uid,
            "joinedAt": FieldValue.serverTimestamp(),
            "lastSeenAt": FieldValue.serverTimestamp()
        ], merge: true) { err in
            if let err { completion(.failure(err)); return }
            completion(.success(()))
        }
    }

    // MARK: - Shared writes
    func heartbeatPresence(liveId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let presenceRef = db.collection("liveGames").document(liveId)
            .collection("participants").document(uid)
        presenceRef.setData(["lastSeenAt": FieldValue.serverTimestamp()], merge: true)
    }

    func updateLiveFields(
        liveId: String,
        fields: [String: Any],
        completion: ((Error?) -> Void)? = nil
    ) {
        let keys = Array(fields.keys).sorted()
        print("📤 updateLiveFields → liveGames/\(liveId)")
        print("📤 keys:", keys)

        // Optional: if you want to see values (can be noisy)
        // print("📤 payload:", fields)

        db.collection("liveGames").document(liveId).updateData(fields) { err in
            if let err {
                print("❌ updateLiveFields failed:", err.localizedDescription)
            } else {
                print("✅ updateLiveFields success")
            }
            completion?(err)
        }
    }


    func addLivePitchEvent(liveId: String, eventData: [String: Any], completion: ((Error?) -> Void)? = nil) {
        db.collection("liveGames").document(liveId)
            .collection("pitchEvents").document()
            .setData(eventData, merge: false, completion: completion)
    }
}

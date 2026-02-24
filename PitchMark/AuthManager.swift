//
//  AuthManager.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//

import Foundation
import Combine
import GoogleSignIn
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

class AuthManager: ObservableObject {
    @Published var user: FirebaseAuth.User? = nil
    @Published var isSignedIn: Bool = false
    @Published var isCheckingAuth: Bool = true
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        isCheckingAuth = true

        // reflect any already-signed-in Firebase user immediately
        let current = Auth.auth().currentUser
        self.user = current
        self.isSignedIn = (current != nil)

        if let current {
            print("✅ currentUser on launch uid=\(current.uid) email=\(current.email ?? "")")
        } else {
            print("ℹ️ No Firebase currentUser on launch.")
        }

        // keep state in sync
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            DispatchQueue.main.async {
                self.user = user
                self.isSignedIn = (user != nil)
                self.isCheckingAuth = false

                if let user {
                    print("🔐 Auth -> SIGNED IN uid=\(user.uid) email=\(user.email ?? "")")
                    self.probeUserPrivateCollections(tag: "authStateDidChangeListener")

                } else {
                    print("🔐 Auth -> SIGNED OUT")
                }
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }
    
    var userEmail: String {
        user?.email ?? "Unknown"
    }
    
    func signInWithGoogle(presenting viewController: UIViewController) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            fatalError("Missing Firebase client ID")
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
            guard let resultUser = result?.user,
                  let idToken = resultUser.idToken?.tokenString else {
                print("Google Sign-In failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            let accessToken = resultUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Firebase Sign-In failed: \(error.localizedDescription)")
                    return
                }
                
                guard let firebaseUser = authResult?.user else { return }
                
                self.user = firebaseUser
                self.isSignedIn = true

                let db = Firestore.firestore()
                let userRef = db.collection("users").document(firebaseUser.uid)
                
                userRef.setData([
                    "email": firebaseUser.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ], merge: true) { error in
                    if let error = error {
                        print("Error creating user document: \(error.localizedDescription)")
                    } else {
                        print("User document created/updated successfully.")
                    }
                }
            }
        }
    }
    
    func restoreSignIn() {
        isCheckingAuth = true
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            guard let restoredUser = user,
                  let idToken = restoredUser.idToken?.tokenString else {
                print("No previous Google sign-in found.")
                self.isCheckingAuth = false
                return
            }
            
            let accessToken = restoredUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Firebase Sign-In failed: \(error.localizedDescription)")
                    self.isCheckingAuth = false
                } else if let firebaseUser = authResult?.user {
                    self.user = firebaseUser
                    self.isSignedIn = true
                    self.isCheckingAuth = false
                    print("Restored Firebase session for: \(firebaseUser.email ?? "Unknown")")
                }
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            print("Signed out from Firebase")
        } catch {
            print("Firebase sign-out failed: \(error.localizedDescription)")
        }
        
        GIDSignIn.sharedInstance.signOut()
        print("Signed out from Google")
        
        self.user = nil
        self.isSignedIn = false
    }
    
    func saveTemplate(_ template: PitchTemplate) {
        guard let user = user else {
            print("No signed-in user to save template for.")
            return
        }
        
        let db = Firestore.firestore()
        let templateRef = db.collection("users")
            .document(user.uid)
            .collection("templates")
            .document(template.id.uuidString)
        
        // Build strongly-typed components to avoid type inference ambiguity
        let codeAssignmentsArray: [[String: Any]] = template.codeAssignments.map { assignment in
            var dict: [String: Any] = [
                "pitch": assignment.pitch,
                "location": assignment.location,
                "code": assignment.code
            ]
            if let enc = assignment.encryptedCode {
                dict["encryptedCode"] = enc
            }
            return dict
        }
        
        // Serialize strongly-typed grid additions
        let headersArray: [[String: Any]] = template.pitchGridHeaders.map { h in
            var dict: [String: Any] = ["pitch": h.pitch]
            if let abbr = h.abbreviation { dict["abbreviation"] = abbr }
            return dict
        }
        
        // Firestore does not support nested arrays (arrays of arrays). Convert 2D arrays to maps keyed by row index.
        func rowsToMap(_ rows: [[String]]) -> [String: [String]] {
            var map: [String: [String]] = [:]
            for (idx, row) in rows.enumerated() {
                map[String(idx)] = row
            }
            return map
        }
        
        let pitchGridMap: [String: [String]] = rowsToMap(template.pitchGridValues)
        let strikeRowsMap: [String: [String]] = rowsToMap(template.strikeRows)
        let ballsRowsMap: [String: [String]] = rowsToMap(template.ballsRows)
        
        let data: [String: Any] = [
            "name": template.name,
            "pitches": template.pitches,
            "codeAssignments": codeAssignmentsArray,
            "isEncrypted": template.isEncrypted,
            "pitchGrid": [
                "headers": headersArray,
                "gridRows": pitchGridMap
            ],
            "strikeGrid": [
                "topRow": template.strikeTopRow,
                "rowsMap": strikeRowsMap
            ],
            "ballsGrid": [
                "topRow": template.ballsTopRow,
                "rowsMap": ballsRowsMap
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        templateRef.setData(data) { error in
            if let error = error {
                print("Error saving template: \(error.localizedDescription)")
            } else {
                print("Template saved successfully for user: \(user.email ?? "Unknown")")
            }
        }
    }
    
    func deleteTemplate(_ template: PitchTemplate) {
        guard let user = user else {
            print("No signed-in user to delete template for.")
            return
        }
        
        let db = Firestore.firestore()
        let templateRef = db.collection("users")
            .document(user.uid)
            .collection("templates")
            .document(template.id.uuidString)
        
        templateRef.delete { error in
            if let error = error {
                print("Error deleting template: \(error.localizedDescription)")
            } else {
                print("Template deleted successfully for user: \(user.email ?? "Unknown")")
            }
        }
    }

    func loadTemplates(completion: @escaping ([PitchTemplate]) -> Void) {
        guard let user = user else {
            print("⚠️ loadTemplates: user=nil")
            DispatchQueue.main.async { completion([]) }
            return
        }

        print("📥 loadTemplates uid=\(user.uid)")

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("templates")
            .getDocuments { snapshot, error in

                if let error = error {
                    print("❌ loadTemplates Firestore error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([]) }
                    return
                }

                let docs = snapshot?.documents ?? []
                print("📥 loadTemplates raw docs:", docs.count)

                Task { @MainActor in
                    var templates: [PitchTemplate] = []
                    templates.reserveCapacity(docs.count)

                    for doc in docs {
                        let data = doc.data()
                        let keys = Array(data.keys).sorted()
                        print("🧩 Template docId=\(doc.documentID) keys=\(keys)")

                        // ✅ Accept either "name" or "templateName" (common pivot break)
                        let name = (data["name"] as? String) ?? (data["templateName"] as? String) ?? ""
                        if name.isEmpty {
                            print("❌ Template missing name (name/templateName) docId=\(doc.documentID)")
                            continue
                        }

                        // ✅ pitches may be missing; default [] so it still shows in UI
                        let pitches = data["pitches"] as? [String] ?? []

                        // ✅ codeAssignments: accept array form OR map form OR missing
                        var codeAssignments: [PitchCodeAssignment] = []

                        if let raw = data["codeAssignments"] as? [[String: Any]] {
                            codeAssignments = raw.compactMap { dict in
                                guard let pitch = dict["pitch"] as? String,
                                      let location = dict["location"] as? String,
                                      let code = dict["code"] as? String else { return nil }
                                let encrypted = dict["encryptedCode"] as? String
                                return PitchCodeAssignment(code: code, pitch: pitch, location: location, encryptedCode: encrypted)
                            }
                        } else if let map = data["codeAssignments"] as? [String: Any] {
                            // Map form: { "0": {pitch,location,code}, "1": {...} }
                            let sortedKeys = map.keys.compactMap { Int($0) }.sorted()
                            for k in sortedKeys {
                                guard let dict = map[String(k)] as? [String: Any],
                                      let pitch = dict["pitch"] as? String,
                                      let location = dict["location"] as? String,
                                      let code = dict["code"] as? String else { continue }
                                let encrypted = dict["encryptedCode"] as? String
                                codeAssignments.append(PitchCodeAssignment(code: code, pitch: pitch, location: location, encryptedCode: encrypted))
                            }
                            print("⚠️ codeAssignments was MAP form docId=\(doc.documentID) count=\(codeAssignments.count)")
                        } else {
                            print("⚠️ codeAssignments missing docId=\(doc.documentID) (default empty)")
                        }

                        // Optional encrypted grid fields (keep yours, but tolerate missing)
                        let pitchGrid = data["pitchGrid"] as? [String: Any]
                        let headersRaw = pitchGrid?["headers"] as? [[String: Any]] ?? []
                        let headers: [PitchHeader] = headersRaw.compactMap { dict in
                            guard let pitch = dict["pitch"] as? String else { return nil }
                            let abbr = dict["abbreviation"] as? String
                            return PitchHeader(pitch: pitch, abbreviation: abbr)
                        }

                        var gridValues: [[String]] = []
                        if let gridMap = pitchGrid?["gridRows"] as? [String: [String]] {
                            let sorted = gridMap.keys.compactMap { Int($0) }.sorted()
                            gridValues = sorted.map { gridMap[String($0)] ?? [] }
                        }

                        let strikeGrid = data["strikeGrid"] as? [String: Any]
                        let strikeTop = strikeGrid?["topRow"] as? [String] ?? []
                        var strikeRows: [[String]] = []
                        if let rowsMap = strikeGrid?["rowsMap"] as? [String: [String]] {
                            let sorted = rowsMap.keys.compactMap { Int($0) }.sorted()
                            strikeRows = sorted.map { rowsMap[String($0)] ?? [] }
                        }

                        let ballsGrid = data["ballsGrid"] as? [String: Any]
                        let ballsTop = ballsGrid?["topRow"] as? [String] ?? []
                        var ballsRows: [[String]] = []
                        if let rowsMap = ballsGrid?["rowsMap"] as? [String: [String]] {
                            let sorted = rowsMap.keys.compactMap { Int($0) }.sorted()
                            ballsRows = sorted.map { rowsMap[String($0)] ?? [] }
                        }

                        let isEncrypted = data["isEncrypted"] as? Bool ?? false
                        let templateId = UUID(uuidString: doc.documentID) ?? UUID()

                        templates.append(
                            PitchTemplate(
                                id: templateId,
                                name: name,
                                pitches: pitches,
                                codeAssignments: codeAssignments,
                                isEncrypted: isEncrypted,
                                pitchGridHeaders: headers,
                                pitchGridValues: gridValues,
                                strikeTopRow: strikeTop,
                                strikeRows: strikeRows,
                                ballsTopRow: ballsTop,
                                ballsRows: ballsRows
                            )
                        )
                    }

                    print("✅ loadTemplates decoded:", templates.count)
                    completion(templates)
                }
            }
    }
    func loadTemplate(id: String) async -> PitchTemplate? {
        guard let user = user else {
            print("⚠️ loadTemplate(async): user=nil")
            return nil
        }

        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("templates").document(id)
                .getDocument()

            guard snap.exists else {
                print("⚠️ loadTemplate(async): doc not found id=\(id)")
                return nil
            }

            let data = snap.data() ?? [:]
            let keys = Array(data.keys).sorted()
            print("🧩 loadTemplate(async) id=\(id) keys=\(keys)")

            // ✅ Map on MainActor in case PitchTemplate is @MainActor-isolated
            return await MainActor.run {
                let name = (data["name"] as? String) ?? (data["templateName"] as? String) ?? ""
                if name.isEmpty {
                    print("❌ loadTemplate(async) missing name fields id=\(id)")
                    return nil
                }

                let pitches = data["pitches"] as? [String] ?? []

                var codeAssignments: [PitchCodeAssignment] = []
                if let raw = data["codeAssignments"] as? [[String: Any]] {
                    codeAssignments = raw.compactMap { dict in
                        guard let pitch = dict["pitch"] as? String,
                              let location = dict["location"] as? String,
                              let code = dict["code"] as? String else { return nil }
                        let encrypted = dict["encryptedCode"] as? String
                        return PitchCodeAssignment(code: code, pitch: pitch, location: location, encryptedCode: encrypted)
                    }
                } else if let map = data["codeAssignments"] as? [String: Any] {
                    let sortedKeys = map.keys.compactMap { Int($0) }.sorted()
                    for k in sortedKeys {
                        guard let dict = map[String(k)] as? [String: Any],
                              let pitch = dict["pitch"] as? String,
                              let location = dict["location"] as? String,
                              let code = dict["code"] as? String else { continue }
                        let encrypted = dict["encryptedCode"] as? String
                        codeAssignments.append(PitchCodeAssignment(code: code, pitch: pitch, location: location, encryptedCode: encrypted))
                    }
                }

                let pitchGrid = data["pitchGrid"] as? [String: Any]
                let headersRaw = pitchGrid?["headers"] as? [[String: Any]] ?? []
                let headers: [PitchHeader] = headersRaw.compactMap { dict in
                    guard let pitch = dict["pitch"] as? String else { return nil }
                    let abbr = dict["abbreviation"] as? String
                    return PitchHeader(pitch: pitch, abbreviation: abbr)
                }

                var gridValues: [[String]] = []
                if let gridMap = pitchGrid?["gridRows"] as? [String: [String]] {
                    let sorted = gridMap.keys.compactMap { Int($0) }.sorted()
                    gridValues = sorted.map { gridMap[String($0)] ?? [] }
                }

                let strikeGrid = data["strikeGrid"] as? [String: Any]
                let strikeTop = strikeGrid?["topRow"] as? [String] ?? []
                var strikeRows: [[String]] = []
                if let rowsMap = strikeGrid?["rowsMap"] as? [String: [String]] {
                    let sorted = rowsMap.keys.compactMap { Int($0) }.sorted()
                    strikeRows = sorted.map { rowsMap[String($0)] ?? [] }
                }

                let ballsGrid = data["ballsGrid"] as? [String: Any]
                let ballsTop = ballsGrid?["topRow"] as? [String] ?? []
                var ballsRows: [[String]] = []
                if let rowsMap = ballsGrid?["rowsMap"] as? [String: [String]] {
                    let sorted = rowsMap.keys.compactMap { Int($0) }.sorted()
                    ballsRows = sorted.map { rowsMap[String($0)] ?? [] }
                }

                let isEncrypted = data["isEncrypted"] as? Bool ?? false

                return PitchTemplate(
                    id: UUID(uuidString: id) ?? UUID(),
                    name: name,
                    pitches: pitches,
                    codeAssignments: codeAssignments,
                    isEncrypted: isEncrypted,
                    pitchGridHeaders: headers,
                    pitchGridValues: gridValues,
                    strikeTopRow: strikeTop,
                    strikeRows: strikeRows,
                    ballsTopRow: ballsTop,
                    ballsRows: ballsRows
                )
            }
        } catch {
            print("❌ loadTemplate(async) error:", error.localizedDescription)
            return nil
        }
    }

    
    func savePitchEvent(_ event: PitchEvent) {
        guard let user = user else {
            print("No signed-in user to save pitch event for.")
            return
        }
        
        let db = Firestore.firestore()
        let eventRef = db.collection("users")
            .document(user.uid)
            .collection("pitchEvents")
            .document() // auto-generated ID
        
        do {
            try eventRef.setData(from: event) { error in
                if let error = error {
                    print("Error saving pitch event: \(error.localizedDescription)")
                } else {
                    print("Pitch event saved successfully.")
                }
            }
        } catch {
            print("Encoding error: \(error.localizedDescription)")
        }
    }
    
    func loadPitchEvents(completion: @escaping ([PitchEvent]) -> Void) {
        guard let user = user else {
            print("❌ No signed-in user.")
            completion([])
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users")
            .document(user.uid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Firestore error: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    do {
                        return try doc.data(as: PitchEvent.self)
                    } catch {
                        print("❌ Decoding failed for doc \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                completion(events)
            }
    }
    
    func deletePracticeEvents(practiceId: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = user else {
            print("⚠️ No signed-in user; nothing to delete.")
            completion(.success(()))
            return
        }
        let db = Firestore.firestore()
        let collectionRef = db.collection("users").document(user.uid).collection("pitchEvents")
        
        // Base query: practice mode only
        var query: Query = collectionRef.whereField("mode", isEqualTo: "practice")
        
        if let pid = practiceId {
            // Filter to specific practice session
            query = query.whereField("practiceId", isEqualTo: pid)
            query.getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Failed to query practice events for practiceId=\(pid): \(error)")
                    completion(.failure(error))
                    return
                }
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    print("🧹 No practice events found to delete for practiceId=\(pid)")
                    completion(.success(()))
                    return
                }
                let batch = db.batch()
                docs.forEach { batch.deleteDocument($0.reference) }
                batch.commit { err in
                    if let err = err {
                        print("❌ Batch delete failed for practiceId=\(pid): \(err)")
                        completion(.failure(err))
                    } else {
                        print("✅ Deleted \(docs.count) practice events for practiceId=\(pid)")
                        completion(.success(()))
                    }
                }
            }
        } else {
            // General session (no practiceId stored). Firestore cannot query for missing fields directly.
            // Strategy: fetch practice-mode events and client-filter those with missing or empty practiceId.
            query.getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Failed to query general practice events: \(error)")
                    completion(.failure(error))
                    return
                }
                let allDocs = snapshot?.documents ?? []
                let toDelete = allDocs.filter { doc in
                    let data = doc.data()
                    // Consider missing or empty string as General. Adjust if you use a sentinel value.
                    if let pidAny = data["practiceId"] {
                        if let pidStr = pidAny as? String {
                            return pidStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        return false
                    } else {
                        return true // missing field
                    }
                }
                guard !toDelete.isEmpty else {
                    print("🧹 No general practice events found to delete")
                    completion(.success(()))
                    return
                }
                let batch = db.batch()
                toDelete.forEach { batch.deleteDocument($0.reference) }
                batch.commit { err in
                    if let err = err {
                        print("❌ Batch delete failed for general practice events: \(err)")
                        completion(.failure(err))
                    } else {
                        print("✅ Deleted \(toDelete.count) general practice events")
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    func updateGameSelectedBatter(ownerUserId: String?, gameId: String, selectedBatterId: String?) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId, debugTag: "updateGameSelectedBatter") else { return }
        
        ref.updateData([
            "selectedBatterId": selectedBatterId as Any
        ]) { error in
            if let error = error {
                print("❌ Error updating selectedBatterId:", error)
            }
        }
    }
    
    func migrateBatterIdsIfMissing(ownerUserId: String?, gameId: String) {
        guard let currentUid = user?.uid else { return }
        
        // ✅ Only the OWNER should ever run this migration write.
        if let ownerUserId, ownerUserId != currentUid {
            print("⏭️ migrateBatterIdsIfMissing skipped (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId, debugTag: "migrateBatterIdsIfMissing") else { return }
        
        let db = Firestore.firestore()
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            
            let data = snap.data() ?? [:]
            let jerseyNumbers = data["jerseyNumbers"] as? [String] ?? []
            let existingIds = data["batterIds"] as? [String]
            
            // If already present and aligned, do nothing
            if let existingIds, existingIds.count == jerseyNumbers.count, !existingIds.isEmpty {
                return nil
            }
            
            // Only migrate if there are jerseys
            guard !jerseyNumbers.isEmpty else { return nil }
            
            let newIds = jerseyNumbers.map { _ in UUID().uuidString }
            
            transaction.updateData([
                "batterIds": newIds
            ], forDocument: ref)
            
            return nil
        }) { _, error in
            if let error = error {
                print("❌ migrateBatterIdsIfMissing failed:", error)
            } else {
                print("✅ migrateBatterIdsIfMissing complete (or already migrated)")
            }
        }
    }
    
    func updateGameTemplateName(ownerUserId: String, gameId: String, templateName: String) {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
        guard let currentUid = user?.uid else { return }
        if ownerUserId != currentUid {
            print("⏭️ Skipping <functionName> (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        ref.updateData([
            "templateName": templateName
        ]) { err in
            if let err = err {
                print("❌ updateGameTemplateName:", err.localizedDescription)
            } else {
                print("✅ Game.templateName updated:", templateName)
            }
        }
    }
    
    func saveGamePitchEvent(ownerUserId: String, gameId: String, event: PitchEvent) {
        let db = Firestore.firestore()
        let ref = db.collection("users")
            .document(ownerUserId)
            .collection("games")
            .document(gameId)
            .collection("pitchEvents")
            .document()
        
        do {
            // Ensure required fields exist for rules
            var enriched = event
            enriched.gameId = gameId
            enriched.createdByUid = Auth.auth().currentUser?.uid
            
            try ref.setData(from: enriched) { err in
                if let err = err {
                    print("❌ saveGamePitchEvent failed:", err.localizedDescription)
                } else {
                    print("✅ Game pitch event saved.")
                }
            }
        } catch {
            print("❌ saveGamePitchEvent encode failed:", error.localizedDescription)
        }
    }
    
    func probeUserPrivateCollections(tag: String) {
        guard let u = user else {
            print("🧪 \(tag) probe: user=nil")
            return
        }

        let db = Firestore.firestore()
        print("🧪 \(tag) probe uid=\(u.uid) email=\(u.email ?? "")")

        db.collection("users").document(u.uid).collection("templates")
            .getDocuments { snap, err in
                if let err = err {
                    print("🧪 \(tag) templates ERROR:", err.localizedDescription)
                } else {
                    print("🧪 \(tag) templates count:", snap?.documents.count ?? 0)
                }
            }

        db.collection("users").document(u.uid).collection("games")
            .getDocuments { snap, err in
                if let err = err {
                    print("🧪 \(tag) games ERROR:", err.localizedDescription)
                } else {
                    print("🧪 \(tag) games count:", snap?.documents.count ?? 0)
                }
            }
    }


}

extension AuthManager {
    func saveGame(_ game: Game) {
        guard let user = user else {
            print("No signed-in user to save game for.")
            return
        }
        
        let db = Firestore.firestore()
        let gamesRef = db.collection("users").document(user.uid).collection("games")
        let docRef = (game.id != nil) ? gamesRef.document(game.id!) : gamesRef.document()
        let isNew = (game.id == nil)
        
        do {
            var toSave = game
            if isNew {
                toSave.jerseyNumbers = []   // keep your existing logic
            }
            
            toSave.id = docRef.documentID
            
            // ✅ Encode the Game model
            let encoded = try Firestore.Encoder().encode(toSave)
            
            // ✅ Add create-only fields (prevents overwriting participants on updates)
            var data = encoded
            if isNew {
                data["ownerUserId"] = user.uid
                data["participants"] = [user.uid: true]   // ✅ host is always included
                data["createdAt"] = FieldValue.serverTimestamp()
            }
            
            docRef.setData(data, merge: true) { error in
                if let error = error {
                    print("Error saving game: \(error)")
                } else {
                    print("✅ Game saved: \(docRef.documentID)")
                }
            }
            
        } catch {
            print("Encoding error saving game: \(error)")
        }
    }
    
    // ✅ Always writes to the host-owned game doc when ownerUserId is provided.
    // Adds a log so you can instantly see if a participant is writing to their own tree by mistake.
    private func gameDocRef(ownerUserId: String?, gameId: String, debugTag: String = "") -> DocumentReference? {
        guard let currentUid = user?.uid else { return nil }
        let owner = ownerUserId ?? currentUid
        let ref = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gameId)
        
        if !debugTag.isEmpty {
            print("🧭 \(debugTag) | currentUid=\(currentUid) ownerUserId=\(ownerUserId ?? "nil") -> path=\(ref.path)")
        }
        return ref
    }
    
    
    func loadGames(completion: @escaping ([Game]) -> Void) {
        guard let user = user else {
            print("⚠️ loadGames: user=nil")
            DispatchQueue.main.async { completion([]) }
            return
        }

        print("📥 loadGames uid=\(user.uid)")

        let query = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games")
            .order(by: "date", descending: true)

        // 1) Cache
        query.getDocuments(source: .cache) { snapshot, error in
            if let error = error {
                print("❌ loadGames(cache) error:", error.localizedDescription)
                return
            }

            let docs = snapshot?.documents ?? []
            Task { @MainActor in
                var decoded: [Game] = []

                for d in docs {
                    do {
                        decoded.append(try d.data(as: Game.self))
                    } catch {
                        print("❌ Game decode failed (cache) docId=\(d.documentID) error=\(error)")
                        print("   keys:", Array(d.data().keys).sorted())
                    }
                }

                completion(decoded)
            }
        }

        // 2) Server
        query.getDocuments { snapshot, error in
            if let error = error {
                print("❌ loadGames(server) error:", error.localizedDescription)
                return
            }

            let docs = snapshot?.documents ?? []
            var decoded: [Game] = []
            for d in docs {
                do {
                    decoded.append(try d.data(as: Game.self))
                } catch {
                    print("❌ Game decode failed (server) docId=\(d.documentID) error=\(error)")
                    print("   keys:", Array(d.data().keys).sorted())
                }
            }

            DispatchQueue.main.async { completion(decoded) }
        }
    }

    
    func loadGame(ownerUserId: String, gameId: String, completion: @escaping (Game?) -> Void) {
        Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
            .getDocument { snapshot, error in
                if let error = error {
                    print("Error loading game \(gameId) for owner \(ownerUserId): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    print("Game not found. owner=\(ownerUserId) gameId=\(gameId)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                do {
                    let game = try snapshot.data(as: Game.self)
                    DispatchQueue.main.async { completion(game) }
                } catch {
                    print("Error decoding game \(gameId): \(error)")
                    DispatchQueue.main.async { completion(nil) }
                }
            }
    }
    
    func updateGameLineup(ownerUserId: String?, gameId: String, jerseyNumbers: [String], batterIds: [String]) {
        guard let currentUid = user?.uid else { return }
        if ownerUserId != currentUid {
            print("⏭️ Skipping <functionName> (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        guard jerseyNumbers.count == batterIds.count else {
            print("❌ Lineup mismatch: jerseyNumbers=\(jerseyNumbers.count) batterIds=\(batterIds.count)")
            return
        }
        
        ref.updateData([
            "jerseyNumbers": jerseyNumbers,
            "batterIds": batterIds
        ]) { error in
            if let error = error { print("Error updating lineup: \(error)") }
        }
    }
    
    
    func deleteGame(gameId: String) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.delete { error in
            if let error = error {
                print("Error deleting game: \(error)")
            } else {
                print("Game \(gameId) deleted successfully")
            }
        }
    }
    
    // MARK: - Game field updates
    func updateGameInning(ownerUserId: String?, gameId: String, inning: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["inning": inning]) { error in
            if let error = error { print("Error updating inning: \(error)") }
        }
    }
    
    func updateGameHits(ownerUserId: String?, gameId: String, hits: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["hits": hits]) { error in
            if let error = error { print("Error updating hits: \(error)") }
        }
    }
    
    func updateGameWalks(ownerUserId: String?, gameId: String, walks: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["walks": walks]) { error in
            if let error = error { print("Error updating walks: \(error)") }
        }
    }
    
    func updateGameBalls(ownerUserId: String?, gameId: String, balls: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["balls": balls]) { error in
            if let error = error { print("Error updating balls: \(error)") }
        }
    }
    
    func updateGameStrikes(ownerUserId: String?, gameId: String, strikes: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["strikes": strikes]) { error in
            if let error = error { print("Error updating strikes: \(error)") }
        }
    }
    
    func updateGameUs(ownerUserId: String?, gameId: String, us: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["us": us]) { error in
            if let error = error { print("Error updating us score: \(error)") }
        }
    }
    
    func updateGameThem(ownerUserId: String?, gameId: String, them: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["them": them]) { error in
            if let error = error { print("Error updating them score: \(error)") }
        }
    }
    
    func updateGameCounts(
        ownerUserId: String?,
        gameId: String,
        inning: Int? = nil,
        hits: Int? = nil,
        walks: Int? = nil,
        balls: Int? = nil,
        strikes: Int? = nil,
        us: Int? = nil,
        them: Int? = nil
    ) {
        var data: [String: Any] = [:]
        if let inning = inning { data["inning"] = inning }
        if let hits = hits { data["hits"] = hits }
        if let walks = walks { data["walks"] = walks }
        if let balls = balls { data["balls"] = balls }
        if let strikes = strikes { data["strikes"] = strikes }
        if let us = us { data["us"] = us }
        if let them = them { data["them"] = them }
        guard !data.isEmpty else { return }
        
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(data) { error in
            if let error = error { print("Error updating game counts: \(error)") }
        }
    }
    
    func setPendingPitch(
        ownerUserId: String,
        gameId: String,
        pending: Game.PendingPitch
    ) {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
        
        do {
            let pendingData = try Firestore.Encoder().encode(pending)
            ref.updateData([
                "pending": pendingData
            ]) { err in
                if let err { print("❌ setPendingPitch failed:", err) }
            }
        } catch {
            print("❌ setPendingPitch encode failed:", error)
        }
    }
    
    func clearPendingPitch(ownerUserId: String, gameId: String) {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
        
        // easiest: delete the whole pending map
        ref.updateData([
            "pending": FieldValue.delete()
        ]) { err in
            if let err { print("❌ clearPendingPitch failed:", err) }
        }
    }
    
    func updateGameSelectedBatter(ownerUserId: String, gameId: String, selectedBatterId: String?, selectedBatterJersey: String?) {
        let db = Firestore.firestore()
        let ref = db.collection("users")
            .document(ownerUserId)
            .collection("games")
            .document(gameId)
        
        var data: [String: Any] = [
            "selectedBatterId": selectedBatterId as Any? ?? NSNull(),
            "selectedBatterJersey": selectedBatterJersey as Any? ?? NSNull()
        ]
        // If you prefer to remove fields when nil, use FieldValue.delete()
        if selectedBatterId == nil { data["selectedBatterId"] = FieldValue.delete() }
        if selectedBatterJersey == nil { data["selectedBatterJersey"] = FieldValue.delete() }
        
        ref.setData(data, merge: true) { error in
            if let error = error {
                print("❌ Failed to update selected batter: \(error)")
            }
        }
    }
    
}


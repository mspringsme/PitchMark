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

        let data: [String: Any] = [
            "name": template.name,
            "pitches": template.pitches,
            "codeAssignments": template.codeAssignments.map { assignment in
                [
                    "pitch": assignment.pitch,
                    "location": assignment.location,
                    "code": assignment.code
                ]
            },
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
            completion([])
            return
        }

        let db = Firestore.firestore()
        db.collection("users")
            .document(user.uid)
            .collection("templates")
            .getDocuments { (snapshot: QuerySnapshot?, error: Error?) in
                if let error = error {
                    print("Error loading templates: \(error.localizedDescription)")
                    completion([])
                    return
                }

                let templates = snapshot?.documents.compactMap { doc -> PitchTemplate? in
                    let data = doc.data()
                    guard let name = data["name"] as? String,
                          let pitches = data["pitches"] as? [String],
                          let codeAssignmentsRaw = data["codeAssignments"] as? [[String: String]] else {
                        return nil
                    }

                    let codeAssignments: [PitchCodeAssignment] = codeAssignmentsRaw.compactMap { dict in
                        guard let pitch = dict["pitch"],
                              let location = dict["location"],
                              let code = dict["code"] else {
                            return nil
                        }
                        return PitchCodeAssignment(code: code, pitch: pitch, location: location)
                    }

                    return PitchTemplate(
                        id: UUID(uuidString: doc.documentID) ?? UUID(),
                        name: name,
                        pitches: pitches,
                        codeAssignments: codeAssignments
                    )
                } ?? []

                completion(templates)
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

                print("📦 Loaded \(events.count) pitch events")
                completion(events)
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
        let ref = db.collection("users").document(user.uid).collection("games")
        let doc = (game.id != nil) ? ref.document(game.id!) : ref.document()
        do {
            var toSave = game
            toSave.id = doc.documentID
            try doc.setData(from: toSave, merge: true) { error in
                if let error = error { print("Error saving game: \(error)") }
            }
        } catch {
            print("Encoding error saving game: \(error)")
        }
    }

    func loadGames(completion: @escaping ([Game]) -> Void) {
        guard let user = user else { completion([]); return }
        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games")
            .order(by: "date", descending: true)
            .getDocuments { snapshot, error in
                guard let docs = snapshot?.documents, error == nil else {
                    print("Error loading games: \(error?.localizedDescription ?? "Unknown")")
                    completion([])
                    return
                }
                let games: [Game] = docs.compactMap { try? $0.data(as: Game.self) }
                completion(games)
            }
    }

    func updateGameLineup(gameId: String, jerseyNumbers: [String]) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["jerseyNumbers": jerseyNumbers]) { error in
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
    func updateGameInning(gameId: String, inning: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["inning": inning]) { error in
            if let error = error { print("Error updating inning: \(error)") }
        }
    }

    func updateGameHits(gameId: String, hits: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["hits": hits]) { error in
            if let error = error { print("Error updating hits: \(error)") }
        }
    }

    func updateGameWalks(gameId: String, walks: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["walks": walks]) { error in
            if let error = error { print("Error updating walks: \(error)") }
        }
    }

    func updateGameBalls(gameId: String, balls: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["balls": balls]) { error in
            if let error = error { print("Error updating balls: \(error)") }
        }
    }

    func updateGameStrikes(gameId: String, strikes: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["strikes": strikes]) { error in
            if let error = error { print("Error updating strikes: \(error)") }
        }
    }

    func updateGameUs(gameId: String, us: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["us": us]) { error in
            if let error = error { print("Error updating us score: \(error)") }
        }
    }

    func updateGameThem(gameId: String, them: Int) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.updateData(["them": them]) { error in
            if let error = error { print("Error updating them score: \(error)") }
        }
    }
    
    func updateGameCounts(
        gameId: String,
        inning: Int? = nil,
        hits: Int? = nil,
        walks: Int? = nil,
        balls: Int? = nil,
        strikes: Int? = nil,
        us: Int? = nil,
        them: Int? = nil
    ) {
        guard let user = user else { return }
        var data: [String: Any] = [:]
        if let inning = inning { data["inning"] = inning }
        if let hits = hits { data["hits"] = hits }
        if let walks = walks { data["walks"] = walks }
        if let balls = balls { data["balls"] = balls }
        if let strikes = strikes { data["strikes"] = strikes }
        if let us = us { data["us"] = us }
        if let them = them { data["them"] = them }
        guard !data.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)

        ref.updateData(data) { error in
            if let error = error { print("Error updating game counts: \(error)") }
        }
    }
}

//
//  CodeSessionResolver.swift
//  PitchMark
//
//  Created by Mark Springer on 1/30/26.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

final class CodeSessionResolver: ObservableObject {
    private var observer: NSObjectProtocol?

    deinit {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func startObserving() {
        // Listen for code-only notifications
        observer = NotificationCenter.default.addObserver(
            forName: .gameOrSessionChosen,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let userInfo = note.userInfo as? [String: Any],
                  let code = userInfo["code"] as? String else {
                return
            }
            // Validate 6-digit numeric
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSixDigits = trimmed.count == 6 && trimmed.allSatisfy({ $0.isNumber })
            guard isSixDigits else {
                print("Resolver: invalid code format: \(code)")
                return
            }
            self.resolve(code: trimmed)
        }
    }

    private func resolve(code: String) {
        let db = Firestore.firestore()
        let docRef = db.collection("sessions").document(code)
        docRef.getDocument { [weak self] snap, error in
            if let error = error {
                print("Resolver: failed to fetch session(\(code)): \(error)")
                return
            }
            guard let data = snap?.data(), snap?.exists == true else {
                print("Resolver: session not found for code \(code)")
                return
            }

            // Expecting a schema like:
            // {
            //   hostUid: String,
            //   ownerUserId: String, // owner of /users/{ownerUserId}
            //   type: "game" | "practice",
            //   gameId?: String,
            //   opponent?: String,
            //   practiceId?: String,
            //   practiceName?: String,
            //   templateId?: String,
            //   templateName?: String,
            //   createdAt: Timestamp,
            //   expiresAt?: Timestamp
            // }
            guard let type = data["type"] as? String else {
                print("Resolver: missing type in session(\(code))")
                return
            }
            if type == "game" {
                self?.handleGameSession(data: data)
            } else if type == "practice" {
                self?.handlePracticeSession(data: data)
            } else {
                print("Resolver: unknown session type \(type) for code \(code)")
            }
        }
    }

    private func handleGameSession(data: [String: Any]) {
        guard let ownerUserId = data["ownerUserId"] as? String,
              let gameId = data["gameId"] as? String else {
            print("Resolver: missing ownerUserId or gameId for game session")
            return
        }
        let opponent = data["opponent"] as? String

        guard let currentUid = Auth.auth().currentUser?.uid else {
            print("Resolver: no signed-in user, cannot join game")
            return
        }

        // Add self as participant to the owner's game doc
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)

        // Update only participants.<uid> = true to satisfy your rules
        ref.setData(["participants": [currentUid: true]], merge: true) { error in
            if let error = error {
                print("Resolver: failed to add participant: \(error)")
                return
            }
            // Repost enriched selection for PitchTrackerView
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "game",
                    "gameId": gameId,
                    "opponent": opponent as Any
                ]
            )
        }
    }

    private func handlePracticeSession(data: [String: Any]) {
        // For cross-device practice, keep guest practice local.
        // Use practiceName (if present) for a nicer label. Leave practiceId nil so the guest
        // remains in a "general" practice unless they choose/create one locally.
        let practiceName = data["practiceName"] as? String

        NotificationCenter.default.post(
            name: .gameOrSessionChosen,
            object: nil,
            userInfo: [
                "type": "practice",
                "practiceName": practiceName as Any
            ]
        )
    }
}

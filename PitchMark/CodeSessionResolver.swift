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
        // Prevent accidentally stacking multiple observers if startObserving() is called more than once
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }

        observer = NotificationCenter.default.addObserver(
            forName: .gameOrSessionChosen,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let userInfo = note.userInfo as? [String: Any] else { return }

            // Ignore already-resolved reposts (extra safety)
            if (userInfo["resolved"] as? Bool) == true { return }

            // Only handle code-only posts
            guard userInfo["type"] == nil else { return }

            guard let code = userInfo["code"] as? String else { return }
            guard let normalized = Self.normalizedSixDigitCode(code) else {
                print("Resolver: invalid code format: \(code)")
                return
            }

            self.resolve(code: normalized)
        }
    }


    private static func normalizedSixDigitCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else { return nil }
        return trimmed
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
            // ✅ Expiration check (optional field)
            if let expiresAt = data["expiresAt"] as? Timestamp {
                let expiryDate = expiresAt.dateValue()
                if expiryDate < Date() {
                    print("Resolver: session expired for code \(code) at \(expiryDate)")
                    // Optional cleanup:
                    // docRef.delete()
                    return
                }
            }

            guard let type = data["type"] as? String else {
                print("Resolver: missing type in session(\(code))")
                return
            }
            if type == "game" {
                self?.handleGameSession(data: data)
            } else {
                print("Resolver: unsupported session type '\(type)' for code \(code)")
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
        ref.setData(["participants.\(currentUid)": true], merge: true) { error in
            if let error = error {
                print("Resolver: failed to add participant: \(error)")
                return
            }
            // Repost enriched selection for PitchTrackerView
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "resolved": true,
                    "type": "game",
                    "gameId": gameId,
                    "ownerUserId": ownerUserId,
                    "opponent": opponent as Any
                ]
            )

        }
    }
}

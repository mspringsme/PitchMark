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
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            guard let restoredUser = user,
                  let idToken = restoredUser.idToken?.tokenString else {
                print("No previous Google sign-in found.")
                return
            }

            let accessToken = restoredUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("Firebase Sign-In failed: \(error.localizedDescription)")
                } else if let firebaseUser = authResult?.user {
                    self.user = firebaseUser
                    self.isSignedIn = true
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
}

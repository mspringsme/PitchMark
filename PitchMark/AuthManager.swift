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
import FirebaseFunctions
import AuthenticationServices
import CryptoKit
import UIKit

enum ChangeEmailError: LocalizedError {
    case emptyEmail
    case notSignedIn
    case invalidEmail
    case emailAlreadyInUse
    case requiresRecentLogin
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .emptyEmail:
            return "Email required."
        case .notSignedIn:
            return "Not signed in."
        case .invalidEmail:
            return "Enter a valid email address."
        case .emailAlreadyInUse:
            return "That email is already in use."
        case .requiresRecentLogin:
            return "For security, please sign in again to change your email."
        case .unknown(let message):
            return message
        }
    }
}

enum DeleteAccountError: LocalizedError {
    case notSignedIn
    case requiresRecentLogin
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .requiresRecentLogin:
            return "For security, please sign in again to delete your account."
        case .unknown(let message):
            return message
        }
    }
}

class AuthManager: ObservableObject {
    @Published var user: FirebaseAuth.User? = nil
    @Published var isSignedIn: Bool = false
    @Published var isCheckingAuth: Bool = true
    @Published private(set) var isRetailAdmin: Bool = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String? = nil
    private let pendingEmailLinkKey = "pendingEmailLinkSignInEmail"

    init() {
        isCheckingAuth = true

        // reflect any already-signed-in Firebase user immediately
        let current = Auth.auth().currentUser
        self.user = current
        self.isSignedIn = (current != nil)
        refreshRetailAdminStatus(for: current)

        if let current {
            debugLog("✅ currentUser on launch uid=\(current.uid) email=\(current.email ?? "")")
        } else {
            debugLog("ℹ️ No Firebase currentUser on launch.")
        }

        // keep state in sync
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            DispatchQueue.main.async {
                self.user = user
                self.isSignedIn = (user != nil)
                self.isCheckingAuth = false

                if let user {
                    debugLog("🔐 Auth -> SIGNED IN uid=\(user.uid) email=\(user.email ?? "")")
                    self.refreshRetailAdminStatus(for: user)
                    self.probeUserPrivateCollections(tag: "authStateDidChangeListener")

                } else {
                    debugLog("🔐 Auth -> SIGNED OUT")
                    self.isRetailAdmin = false
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

    private func refreshRetailAdminStatus(for user: FirebaseAuth.User?) {
        guard let user else {
            isRetailAdmin = false
            return
        }

        user.getIDTokenResult(forcingRefresh: true) { [weak self] result, error in
            guard let self else { return }
            if let error {
                debugLog("Retail admin claim check failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRetailAdmin = false
                }
                return
            }

            let isAdmin = (result?.claims["admin"] as? Bool) == true
            DispatchQueue.main.async {
                self.isRetailAdmin = isAdmin
            }
        }
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
                debugLog("Google Sign-In failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            let accessToken = resultUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    debugLog("Firebase Sign-In failed: \(error.localizedDescription)")
                    return
                }

                guard let firebaseUser = authResult?.user else { return }

                self.user = firebaseUser
                self.isSignedIn = true
                self.refreshRetailAdminStatus(for: firebaseUser)
                self.upsertUserDocument(for: firebaseUser)
            }
        }
    }


    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            debugLog("Apple Sign-In failed: \(error.localizedDescription)")
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                debugLog("Apple Sign-In failed: missing credential")
                return
            }
            guard let nonce = currentAppleNonce else {
                debugLog("Apple Sign-In failed: missing nonce")
                return
            }
            guard let tokenData = credential.identityToken,
                  let tokenString = String(data: tokenData, encoding: .utf8) else {
                debugLog("Apple Sign-In failed: invalid identity token")
                return
            }

            let oauth = OAuthProvider.credential(providerID: .apple, idToken: tokenString, rawNonce: nonce)
            Auth.auth().signIn(with: oauth) { authResult, error in
                if let error = error {
                    debugLog("Firebase Apple Sign-In failed: \(error.localizedDescription)")
                    return
                }

                guard let firebaseUser = authResult?.user else { return }
                self.user = firebaseUser
                self.isSignedIn = true
                self.refreshRetailAdminStatus(for: firebaseUser)
                self.upsertUserDocument(for: firebaseUser)
            }
        }
    }

    func sendEmailSignInLink(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Auth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Email required."])))
            return
        }

        let actionCodeSettings = ActionCodeSettings()
        actionCodeSettings.url = URL(string: "https://pitchmark-fb9f8.web.app/signin")
        actionCodeSettings.handleCodeInApp = true
        actionCodeSettings.setIOSBundleID(Bundle.main.bundleIdentifier ?? "com.pitchmark.app")

        Auth.auth().sendSignInLink(toEmail: trimmed, actionCodeSettings: actionCodeSettings) { error in
            if let error {
                debugLog("Email link sign-in request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            UserDefaults.standard.set(trimmed, forKey: self.pendingEmailLinkKey)
            completion(.success(()))
        }
    }

    func handleEmailSignInLink(_ url: URL) -> Bool {
        let link = url.absoluteString
        guard Auth.auth().isSignIn(withEmailLink: link) else { return false }
        guard let email = UserDefaults.standard.string(forKey: pendingEmailLinkKey),
              !email.isEmpty else {
            debugLog("Email link sign-in failed: missing stored email")
            return true
        }

        Auth.auth().signIn(withEmail: email, link: link) { authResult, error in
            if let error {
                debugLog("Email link sign-in failed: \(error.localizedDescription)")
                return
            }

            guard let firebaseUser = authResult?.user else { return }
            self.user = firebaseUser
            self.isSignedIn = true
            self.refreshRetailAdminStatus(for: firebaseUser)
            UserDefaults.standard.removeObject(forKey: self.pendingEmailLinkKey)
            self.upsertUserDocument(for: firebaseUser)
        }

        return true
    }
    
    func restoreSignIn() {
        isCheckingAuth = true
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            guard let restoredUser = user,
                  let idToken = restoredUser.idToken?.tokenString else {
                debugLog("No previous Google sign-in found.")
                self.isCheckingAuth = false
                return
            }

            let accessToken = restoredUser.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    debugLog("Firebase Sign-In failed: \(error.localizedDescription)")
                    self.isCheckingAuth = false
                } else if let firebaseUser = authResult?.user {
                    self.user = firebaseUser
                    self.isSignedIn = true
                    self.isCheckingAuth = false
                    self.refreshRetailAdminStatus(for: firebaseUser)
                    debugLog("Restored Firebase session for: \(firebaseUser.email ?? "Unknown")")
                }
            }
        }
    }

    private func upsertUserDocument(for firebaseUser: FirebaseAuth.User) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(firebaseUser.uid)
        userRef.setData([
            "email": firebaseUser.email ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error {
                debugLog("Error creating user document: \(error.localizedDescription)")
            } else {
                debugLog("User document created/updated successfully.")
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func changeEmail(to newEmail: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(ChangeEmailError.emptyEmail))
            return
        }
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(ChangeEmailError.notSignedIn))
            return
        }

        currentUser.sendEmailVerification(beforeUpdatingEmail: trimmed) { error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == AuthErrorDomain,
                   let authCode = AuthErrorCode(rawValue: nsError.code) {
                    switch authCode {
                    case .invalidEmail:
                        completion(.failure(ChangeEmailError.invalidEmail))
                        return
                    case .emailAlreadyInUse:
                        completion(.failure(ChangeEmailError.emailAlreadyInUse))
                        return
                    case .requiresRecentLogin:
                        completion(.failure(ChangeEmailError.requiresRecentLogin))
                        return
                    default:
                        break
                    }
                }
                completion(.failure(ChangeEmailError.unknown(error.localizedDescription)))
                return
            }
            completion(.success(()))
        }
    }

    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion(.failure(DeleteAccountError.notSignedIn))
            return
        }

        let callable = Functions.functions().httpsCallable("deleteAccount")
        callable.call { _, error in
            if let error {
                let nsError = error as NSError
                if nsError.domain == FunctionsErrorDomain,
                   let code = FunctionsErrorCode(rawValue: nsError.code) {
                    switch code {
                    case .unauthenticated:
                        completion(.failure(DeleteAccountError.requiresRecentLogin))
                        return
                    default:
                        break
                    }
                }
                completion(.failure(DeleteAccountError.unknown(error.localizedDescription)))
                return
            }

            self.signOut()
            completion(.success(()))
        }
    }

    func signOut() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let defaults = UserDefaults.standard
        let localDeviceId = defaults.string(forKey: "deviceSessionId") ?? ""

        if !uid.isEmpty {
            let ref = Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("meta")
                .document("activeSession")

            ref.getDocument { snapshot, error in
                if let error {
                    debugLog("⚠️ Failed to read activeSession on sign out: \(error.localizedDescription)")
                    return
                }

                let existingDevice = snapshot?.data()?["deviceId"] as? String
                guard !localDeviceId.isEmpty, existingDevice == localDeviceId else { return }

                ref.delete { error in
                    if let error {
                        debugLog("⚠️ Failed to clear activeSession on sign out: \(error.localizedDescription)")
                    }
                }
            }
        }

        defaults.removeObject(forKey: "displayOnlyMode")
        defaults.removeObject(forKey: "displayOnlyLiveId")
        defaults.removeObject(forKey: "activeLiveId")

        do {
            try Auth.auth().signOut()
            debugLog("Signed out from Firebase")
        } catch {
            debugLog("Firebase sign-out failed: \(error.localizedDescription)")
        }

        GIDSignIn.sharedInstance.signOut()
        debugLog("Signed out from Google")

        self.user = nil
        self.isSignedIn = false
    }
    
    func saveTemplate(_ template: PitchTemplate) {
        guard let user = user else {
            debugLog("No signed-in user to save template for.")
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
        
        let ownerUid = user.uid
        let data: [String: Any] = [
            "name": template.name,
            "pitches": template.pitches,
            "codeAssignments": codeAssignmentsArray,
            "isEncrypted": template.isEncrypted,
            "pitchFirstColors": template.pitchFirstColors,
            "locationFirstColors": template.locationFirstColors,
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
            "ownerUid": ownerUid,
            "sharedWith": template.sharedWith,
            "sharedWithEmails": template.sharedWithEmails,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        templateRef.setData(data) { error in
            if let error = error {
                debugLog("Error saving template: \(error.localizedDescription)")
            } else {
                debugLog("Template saved successfully for user: \(user.email ?? "Unknown")")
            }
        }

        let sharedRef = db.collection("templates").document(template.id.uuidString)
        sharedRef.setData(data, merge: true) { error in
            if let error = error {
                debugLog("❌ save shared template failed:", error.localizedDescription)
            }
        }
    }

    func hasRetailOrders(forTemplateId templateId: String) async -> Bool {
        guard let user = user, !templateId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("retailOrders")
                .whereField("firebaseUid", isEqualTo: user.uid)
                .whereField("templateId", isEqualTo: templateId)
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            debugLog("⚠️ hasRetailOrders(forTemplateId:) failed:", error.localizedDescription)
            return false
        }
    }

    func shareTemplateByEmail(_ template: PitchTemplate, email: String, completion: ((Error?) -> Void)? = nil) {
        guard let user = user else {
            completion?(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else {
            completion?(NSError(domain: "Share", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid email"]))
            return
        }

        let db = Firestore.firestore()
        let ownerTemplateRef = db.collection("users")
            .document(user.uid)
            .collection("templates")
            .document(template.id.uuidString)

        let sharedRef = db.collection("templates").document(template.id.uuidString)

        let batch = db.batch()
        batch.updateData(["sharedWithEmails": FieldValue.arrayUnion([trimmed])], forDocument: ownerTemplateRef)
        batch.setData(["sharedWithEmails": FieldValue.arrayUnion([trimmed])], forDocument: sharedRef, merge: true)

        batch.commit { error in
            if let error {
                debugLog("❌ shareTemplateByEmail failed:", error.localizedDescription)
            }
            completion?(error)
        }
    }
    
    func deleteTemplate(_ template: PitchTemplate) {
        guard let user = user else {
            debugLog("No signed-in user to delete template for.")
            return
        }
        
        let db = Firestore.firestore()
        let templateRef = db.collection("users")
            .document(user.uid)
            .collection("templates")
            .document(template.id.uuidString)
        
        templateRef.delete { error in
            if let error = error {
                debugLog("Error deleting template: \(error.localizedDescription)")
            } else {
                debugLog("Template deleted successfully for user: \(user.email ?? "Unknown")")
            }
        }

        db.collection("templates")
            .document(template.id.uuidString)
            .delete { error in
                if let error = error {
                    debugLog("❌ delete shared template failed:", error.localizedDescription)
                }
            }
    }

    func loadTemplates(completion: @escaping ([PitchTemplate]) -> Void) {
        guard let user = user else {
            debugLog("⚠️ loadTemplates: user=nil")
            DispatchQueue.main.async { completion([]) }
            return
        }

        debugLog("📥 loadTemplates uid=\(user.uid)")

        let db = Firestore.firestore()
        let group = DispatchGroup()
        var templateDocs: [QueryDocumentSnapshot] = []

        group.enter()
        db.collection("users").document(user.uid)
            .collection("templates")
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadTemplates (legacy) error:", error.localizedDescription)
                } else {
                    templateDocs.append(contentsOf: snapshot?.documents ?? [])
                }
                group.leave()
            }

        group.enter()
        db.collection("templates")
            .whereField("ownerUid", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadTemplates (owner) error:", error.localizedDescription)
                } else {
                    templateDocs.append(contentsOf: snapshot?.documents ?? [])
                }
                group.leave()
            }

        group.enter()
        db.collection("templates")
            .whereField("sharedWith", arrayContains: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadTemplates (shared uid) error:", error.localizedDescription)
                } else {
                    templateDocs.append(contentsOf: snapshot?.documents ?? [])
                }
                group.leave()
            }

        if let email = user.email?.lowercased(), !email.isEmpty {
            group.enter()
            db.collection("templates")
                .whereField("sharedWithEmails", arrayContains: email)
                .getDocuments { snapshot, error in
                    if let error = error {
                        debugLog("❌ loadTemplates (shared email) error:", error.localizedDescription)
                    } else {
                        templateDocs.append(contentsOf: snapshot?.documents ?? [])
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            let docs = templateDocs
            debugLog("📥 loadTemplates raw docs:", docs.count)

            Task { @MainActor in
                var templatesById: [UUID: PitchTemplate] = [:]

                for doc in docs {
                    let data = doc.data()
                    let keys = Array(data.keys).sorted()
                    debugLog("🧩 Template docId=\(doc.documentID) keys=\(keys)")

                    let name = (data["name"] as? String) ?? (data["templateName"] as? String) ?? ""
                    if name.isEmpty {
                        debugLog("❌ Template missing name (name/templateName) docId=\(doc.documentID)")
                        continue
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
                        debugLog("⚠️ codeAssignments was MAP form docId=\(doc.documentID) count=\(codeAssignments.count)")
                    } else {
                        debugLog("⚠️ codeAssignments missing docId=\(doc.documentID) (default empty)")
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

                    let pitchFirstColors = data["pitchFirstColors"] as? [String] ?? []
                    let locationFirstColors = data["locationFirstColors"] as? [String] ?? []

                    let isEncrypted = data["isEncrypted"] as? Bool ?? false
                    let templateId = UUID(uuidString: doc.documentID) ?? UUID()

                    let ownerUid = data["ownerUid"] as? String
                    let sharedWith = data["sharedWith"] as? [String] ?? []
                    let sharedWithEmails = data["sharedWithEmails"] as? [String] ?? []

                    let template = PitchTemplate(
                        id: templateId,
                        name: name,
                        pitches: pitches,
                        codeAssignments: codeAssignments,
                        isEncrypted: isEncrypted,
                        ownerUid: ownerUid,
                        sharedWith: sharedWith,
                        sharedWithEmails: sharedWithEmails,
                        pitchGridHeaders: headers,
                        pitchGridValues: gridValues,
                        strikeTopRow: strikeTop,
                        strikeRows: strikeRows,
                        ballsTopRow: ballsTop,
                        ballsRows: ballsRows,
                        pitchFirstColors: pitchFirstColors,
                        locationFirstColors: locationFirstColors
                    )

                    templatesById[templateId] = template
                }

                let templates = Array(templatesById.values)
                debugLog("✅ loadTemplates decoded:", templates.count)
                completion(templates)
            }
        }
    }

    func loadPitchers(completion: @escaping ([Pitcher]) -> Void) {
        guard let user = user else {
            debugLog("⚠️ loadPitchers: user=nil")
            DispatchQueue.main.async { completion([]) }
            return
        }

        let db = Firestore.firestore()
        let group = DispatchGroup()
        var docs: [QueryDocumentSnapshot] = []

        group.enter()
        db.collection("pitchers")
            .whereField("ownerUid", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadPitchers (owner) error:", error.localizedDescription)
                } else {
                    docs.append(contentsOf: snapshot?.documents ?? [])
                }
                group.leave()
            }

        group.enter()
        db.collection("pitchers")
            .whereField("sharedWith", arrayContains: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadPitchers (shared) error:", error.localizedDescription)
                } else {
                    docs.append(contentsOf: snapshot?.documents ?? [])
                }
                group.leave()
            }

        group.notify(queue: .main) {
            Task { @MainActor in
                var pitchersById: [String: Pitcher] = [:]

                for doc in docs {
                    do {
                        let pitcher = try doc.data(as: Pitcher.self)
                        if let id = pitcher.id {
                            pitchersById[id] = pitcher
                        }
                    } catch {
                        debugLog("❌ Pitcher decode failed docId=\(doc.documentID) error=\(error)")
                    }
                }

                let pitchers = Array(pitchersById.values)
                completion(pitchers)
            }
        }
    }

    func createPitcher(name: String, templateId: String?, completion: ((Pitcher?) -> Void)? = nil) {
        guard let user = user else {
            debugLog("⚠️ createPitcher: user=nil")
            completion?(nil)
            return
        }

        let ref = Firestore.firestore().collection("pitchers").document()
        let pitcher = Pitcher(
            id: ref.documentID,
            name: name,
            templateId: templateId,
            ownerUid: user.uid,
            sharedWith: [user.uid],
            claimedByUid: user.uid,
            createdAt: Date()
        )

        do {
            try ref.setData(from: pitcher) { err in
                if let err {
                    debugLog("❌ createPitcher failed:", err.localizedDescription)
                    completion?(nil)
                } else {
                    completion?(pitcher)
                }
            }
        } catch {
            debugLog("❌ createPitcher encode failed:", error.localizedDescription)
            completion?(nil)
        }
    }

    func updatePitcher(id: String, name: String, templateId: String?, completion: ((Pitcher?) -> Void)? = nil) {
        guard user != nil else {
            completion?(nil)
            return
        }
        let ref = Firestore.firestore().collection("pitchers").document(id)
        let data: [String: Any] = [
            "name": name,
            "templateId": templateId as Any
        ]
        ref.setData(data, merge: true) { err in
            if let err {
                debugLog("❌ updatePitcher failed:", err.localizedDescription)
                completion?(nil)
                return
            }
            ref.getDocument { snap, readErr in
                if let readErr {
                    debugLog("⚠️ updatePitcher: fetch updated doc failed:", readErr.localizedDescription)
                    completion?(nil)
                    return
                }
                guard let snap, snap.exists else {
                    completion?(nil)
                    return
                }
                Task { @MainActor in
                    do {
                        let updated = try snap.data(as: Pitcher.self)
                        completion?(updated)
                    } catch {
                        debugLog("⚠️ updatePitcher: decode updated doc failed:", error)
                        completion?(nil)
                    }
                }
            }
        }
    }

    private func randomToken(length: Int = 10) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var output = ""
        output.reserveCapacity(length)
        for _ in 0..<length {
            if let ch = alphabet.randomElement() {
                output.append(ch)
            }
        }
        return output
    }

    func createPitcherInviteToken(pitcherId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let token = randomToken(length: 12)
        let ref = Firestore.firestore().collection("pitcherInviteTokens").document(token)
        let data: [String: Any] = [
            "pitcherId": pitcherId,
            "ownerUid": user.uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        ref.setData(data) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(token))
            }
        }
    }

    func joinPitcherByInviteToken(token: String, completion: @escaping (Result<Pitcher, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let db = Firestore.firestore()
        let tokenRef = db.collection("pitcherInviteTokens").document(token)
        tokenRef.getDocument { snap, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let snap, snap.exists,
                  let data = snap.data(),
                  let pitcherId = data["pitcherId"] as? String,
                  !pitcherId.isEmpty
            else {
                completion(.failure(NSError(domain: "Invite", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invite not found."])))
                return
            }

            let pitcherRef = db.collection("pitchers").document(pitcherId)
            let updates: [String: Any] = [
                "sharedWith": FieldValue.arrayUnion([user.uid])
            ]

            pitcherRef.setData(updates, merge: true) { err in
                if let err {
                    completion(.failure(err))
                    return
                }
                pitcherRef.getDocument { updatedSnap, readErr in
                    if let readErr {
                        completion(.failure(readErr))
                        return
                    }
                    guard let updatedSnap, updatedSnap.exists else {
                        completion(.failure(NSError(domain: "Invite", code: 404, userInfo: [NSLocalizedDescriptionKey: "Pitcher not found."])))
                        return
                    }
                    Task { @MainActor in
                        do {
                            let pitcher = try updatedSnap.data(as: Pitcher.self)
                            completion(.success(pitcher))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    func reclaimPitcher(pitcherId: String, completion: @escaping (Result<Pitcher, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        let ref = Firestore.firestore().collection("pitchers").document(pitcherId)
        ref.setData(["claimedByUid": user.uid], merge: true) { error in
            if let error {
                completion(.failure(error))
                return
            }
            ref.getDocument { snap, readErr in
                if let readErr {
                    completion(.failure(readErr))
                    return
                }
                guard let snap, snap.exists else {
                    completion(.failure(NSError(domain: "Pitcher", code: 404, userInfo: [NSLocalizedDescriptionKey: "Pitcher not found."])))
                    return
                }
                Task { @MainActor in
                    do {
                        let updated = try snap.data(as: Pitcher.self)
                        completion(.success(updated))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func loadPitcherEvents(pitcherId: String, completion: @escaping ([PitchEvent]) -> Void) {
        let ref = Firestore.firestore()
            .collection("pitchers")
            .document(pitcherId)
            .collection("pitchEvents")

        ref.order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadPitcherEvents error:", error.localizedDescription)
                    completion([])
                    return
                }
                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                } ?? []
                completion(events)
            }
    }

    func saveSharedPitcherEvent(pitcherId: String, event: PitchEvent) {
        let docId: String? = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }()

        let ref = Firestore.firestore()
            .collection("pitchers")
            .document(pitcherId)
            .collection("pitchEvents")
            .document(docId ?? UUID().uuidString)

        do {
            var enriched = event
            enriched.pitcherId = pitcherId
            enriched.createdByUid = Auth.auth().currentUser?.uid
            try ref.setData(from: enriched) { err in
                if let err {
                    debugLog("❌ saveSharedPitcherEvent failed:", err.localizedDescription)
                } else {
                    debugLog("✅ Shared pitcher event saved.")
                }
            }
        } catch {
            debugLog("❌ saveSharedPitcherEvent encode failed:", error.localizedDescription)
        }
    }

    func copyPitcherWithEvents(sourcePitcher: Pitcher, completion: @escaping (Result<Pitcher, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        guard let sourceId = sourcePitcher.id, !sourceId.isEmpty else {
            completion(.failure(NSError(domain: "Pitcher", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing pitcher id."])))
            return
        }

        let db = Firestore.firestore()
        let newRef = db.collection("pitchers").document()
        let copyName = "\(sourcePitcher.name) (Copy)"
        let newPitcher = Pitcher(
            id: newRef.documentID,
            name: copyName,
            templateId: sourcePitcher.templateId,
            ownerUid: user.uid,
            sharedWith: [user.uid],
            claimedByUid: user.uid,
            createdAt: Date()
        )

        do {
            try newRef.setData(from: newPitcher) { err in
                if let err {
                    completion(.failure(err))
                    return
                }

                self.loadPitcherEvents(pitcherId: sourceId) { events in
                    guard !events.isEmpty else {
                        completion(.success(newPitcher))
                        return
                    }

                    let batch = db.batch()
                    for event in events {
                        let targetRef = newRef.collection("pitchEvents").document()
                        var copied = event
                        copied.pitcherId = newRef.documentID
                        copied.createdByUid = user.uid
                        do {
                            let data = try Firestore.Encoder().encode(copied)
                            batch.setData(data, forDocument: targetRef)
                        } catch {
                            debugLog("❌ copyPitcherWithEvents encode failed:", error.localizedDescription)
                        }
                    }
                    batch.commit { batchError in
                        if let batchError {
                            completion(.failure(batchError))
                        } else {
                            completion(.success(newPitcher))
                        }
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    func loadTemplate(id: String) async -> PitchTemplate? {
        guard let user = user else {
            debugLog("⚠️ loadTemplate(async): user=nil")
            return nil
        }

        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("templates").document(id)
                .getDocument()

            guard snap.exists else {
                debugLog("⚠️ loadTemplate(async): doc not found id=\(id)")
                return nil
            }

            let data = snap.data() ?? [:]
            let keys = Array(data.keys).sorted()
            debugLog("🧩 loadTemplate(async) id=\(id) keys=\(keys)")

            // ✅ Map on MainActor in case PitchTemplate is @MainActor-isolated
            return await MainActor.run {
                let name = (data["name"] as? String) ?? (data["templateName"] as? String) ?? ""
                if name.isEmpty {
                    debugLog("❌ loadTemplate(async) missing name fields id=\(id)")
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

                let pitchFirstColors = data["pitchFirstColors"] as? [String] ?? []
                let locationFirstColors = data["locationFirstColors"] as? [String] ?? []

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
                    ballsRows: ballsRows,
                    pitchFirstColors: pitchFirstColors,
                    locationFirstColors: locationFirstColors
                )
            }
        } catch {
            debugLog("❌ loadTemplate(async) error:", error.localizedDescription)
            return nil
        }
    }

    
    func savePitchEvent(_ event: PitchEvent) {
        guard let user = user else {
            debugLog("No signed-in user to save pitch event for.")
            return
        }
        
        let db = Firestore.firestore()
        let resolvedDocumentId = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : UUID().uuidString
        }()
        let eventRef = db.collection("users")
            .document(user.uid)
            .collection("pitchEvents")
            .document(resolvedDocumentId)
        
        do {
            try eventRef.setData(from: event) { error in
                if let error = error {
                    debugLog("Error saving pitch event: \(error.localizedDescription)")
                } else {
                    debugLog("Pitch event saved successfully.")
                }
            }
        } catch {
            debugLog("Encoding error: \(error.localizedDescription)")
        }
    }
    
    func loadPitchEvents(completion: @escaping ([PitchEvent]) -> Void) {
        guard let user = user else {
            debugLog("❌ No signed-in user.")
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
                    debugLog("❌ Firestore error: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                } ?? []
                completion(events)
            }
    }

    func loadGamePitchEvents(ownerUserId: String, gameId: String, completion: @escaping ([PitchEvent]) -> Void) {
        let db = Firestore.firestore()
        db.collection("users")
            .document(ownerUserId)
            .collection("games")
            .document(gameId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    debugLog("❌ loadGamePitchEvents error: \(error.localizedDescription)")
                    completion([])
                    return
                }

                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                } ?? []
                completion(events)
            }
    }
    
    func updateGameSelectedBatter(ownerUserId: String?, gameId: String, selectedBatterId: String?) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId, debugTag: "updateGameSelectedBatter") else { return }
        
        ref.updateData([
            "selectedBatterId": selectedBatterId as Any
        ]) { error in
            if let error = error {
                debugLog("❌ Error updating selectedBatterId:", error)
            }
        }
    }
    
    func migrateBatterIdsIfMissing(ownerUserId: String?, gameId: String) {
        guard let currentUid = user?.uid else { return }
        
        // ✅ Only the OWNER should ever run this migration write.
        if let ownerUserId, ownerUserId != currentUid {
            debugLog("⏭️ migrateBatterIdsIfMissing skipped (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
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
                debugLog("❌ migrateBatterIdsIfMissing failed:", error)
            } else {
                debugLog("✅ migrateBatterIdsIfMissing complete (or already migrated)")
            }
        }
    }
    
    func updateGameTemplateName(ownerUserId: String, gameId: String, templateName: String) {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
        guard let currentUid = user?.uid else { return }
        if ownerUserId != currentUid {
            debugLog("⏭️ Skipping <functionName> (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        ref.updateData([
            "templateName": templateName
        ]) { err in
            if let err = err {
                debugLog("❌ updateGameTemplateName:", err.localizedDescription)
            } else {
                debugLog("✅ Game.templateName updated:", templateName)
            }
        }
    }

    func updateGameLastSelections(ownerUserId: String, gameId: String, templateId: String?, pitcherId: String?) {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
        guard let currentUid = user?.uid else { return }
        if ownerUserId != currentUid {
            debugLog("⏭️ Skipping updateGameLastSelections (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        var updates: [String: Any] = [:]
        if let templateId {
            updates["lastTemplateId"] = templateId
        } else {
            updates["lastTemplateId"] = FieldValue.delete()
        }
        if let pitcherId {
            updates["lastPitcherId"] = pitcherId
        } else {
            updates["lastPitcherId"] = FieldValue.delete()
        }
        ref.updateData(updates) { err in
            if let err {
                debugLog("❌ updateGameLastSelections:", err.localizedDescription)
            }
        }
    }
    
    func saveGamePitchEvent(ownerUserId: String, gameId: String, event: PitchEvent) {
        let db = Firestore.firestore()
        let resolvedDocumentId = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : UUID().uuidString
        }()
        let ref = db.collection("users")
            .document(ownerUserId)
            .collection("games")
            .document(gameId)
            .collection("pitchEvents")
            .document(resolvedDocumentId)
        
        do {
            // Ensure required fields exist for rules
            var enriched = event
            enriched.gameId = gameId
            enriched.createdByUid = Auth.auth().currentUser?.uid
            
            try ref.setData(from: enriched) { err in
                if let err = err {
                    debugLog("❌ saveGamePitchEvent failed:", err.localizedDescription)
                } else {
                    debugLog("✅ Game pitch event saved.")
                }
            }
        } catch {
            debugLog("❌ saveGamePitchEvent encode failed:", error.localizedDescription)
        }
    }
    
    // MARK: - Pitch Events (Realtime Listeners)
    @discardableResult
    func listenGamePitchEvents(
        ownerUserId: String,
        gameId: String,
        onChange: @escaping ([PitchEvent]) -> Void
    ) -> ListenerRegistration {
        let ref = Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
            .collection("pitchEvents")

        debugLog("👂 listenGamePitchEvents path=\(ref.path)")

        let listener = ref
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    debugLog("❌ listenGamePitchEvents error:", error.localizedDescription)
                    DispatchQueue.main.async { onChange([]) }
                    return
                }

                let docs = snapshot?.documents ?? []
                var events: [PitchEvent] = []
                events.reserveCapacity(docs.count)

                for d in docs {
                    if let evt = PitchEvent.decodeFirestoreDocument(d) {
                        events.append(evt)
                    }
                }

                DispatchQueue.main.async {
                    onChange(events)
                }
            }

        return listener
    }

    @discardableResult
    func listenUserPitchEvents(
        userId: String,
        onChange: @escaping ([PitchEvent]) -> Void
    ) -> ListenerRegistration {
        let ref = Firestore.firestore()
            .collection("users").document(userId)
            .collection("pitchEvents")

        debugLog("👂 listenUserPitchEvents path=\(ref.path)")

        let listener = ref
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    debugLog("❌ listenUserPitchEvents error:", error.localizedDescription)
                    DispatchQueue.main.async { onChange([]) }
                    return
                }

                let docs = snapshot?.documents ?? []
                var events: [PitchEvent] = []
                events.reserveCapacity(docs.count)

                for d in docs {
                    if let evt = PitchEvent.decodeFirestoreDocument(d) {
                        events.append(evt)
                    }
                }

                DispatchQueue.main.async {
                    onChange(events)
                }
            }

        return listener
    }

    /// Convenience to remove a Firestore listener safely.
    func stopListening(_ listener: ListenerRegistration?) {
        listener?.remove()
    }
    

    func probeUserPrivateCollections(tag: String) {
        guard let u = user else {
            debugLog("🧪 \(tag) probe: user=nil")
            return
        }

        let db = Firestore.firestore()
        debugLog("🧪 \(tag) probe uid=\(u.uid) email=\(u.email ?? "")")

        db.collection("users").document(u.uid).collection("templates")
            .getDocuments { snap, err in
                if let err = err {
                    debugLog("🧪 \(tag) templates ERROR:", err.localizedDescription)
                } else {
                    debugLog("🧪 \(tag) templates count:", snap?.documents.count ?? 0)
                }
            }

        db.collection("users").document(u.uid).collection("games")
            .getDocuments { snap, err in
                if let err = err {
                    debugLog("🧪 \(tag) games ERROR:", err.localizedDescription)
                } else {
                    debugLog("🧪 \(tag) games count:", snap?.documents.count ?? 0)
                }
            }
    }


}

extension AuthManager {
    func saveGame(_ game: Game) {
        guard let user = user else {
            debugLog("No signed-in user to save game for.")
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
                    debugLog("Error saving game: \(error)")
                } else {
                    debugLog("✅ Game saved: \(docRef.documentID)")
                }
            }
            
        } catch {
            debugLog("Encoding error saving game: \(error)")
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
            debugLog("🧭 \(debugTag) | currentUid=\(currentUid) ownerUserId=\(ownerUserId ?? "nil") -> path=\(ref.path)")
        }
        return ref
    }
    
    
    func loadGames(completion: @escaping ([Game]) -> Void) {
        guard let user = user else {
            debugLog("⚠️ loadGames: user=nil")
            DispatchQueue.main.async { completion([]) }
            return
        }

        debugLog("📥 loadGames uid=\(user.uid)")

        let query = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games")
            .order(by: "date", descending: true)

        // 1) Cache
        query.getDocuments(source: .cache) { snapshot, error in
            if let error = error {
                debugLog("❌ loadGames(cache) error:", error.localizedDescription)
                return
            }

            let docs = snapshot?.documents ?? []
            Task { @MainActor in
                var decoded: [Game] = []

                for d in docs {
                    do {
                        decoded.append(try d.data(as: Game.self))
                    } catch {
                        debugLog("❌ Game decode failed (cache) docId=\(d.documentID) error=\(error)")
                        debugLog("   keys:", Array(d.data().keys).sorted())
                    }
                }

                completion(decoded)
            }
        }

        // 2) Server
        query.getDocuments { snapshot, error in
            if let error = error {
                debugLog("❌ loadGames(server) error:", error.localizedDescription)
                return
            }

            let docs = snapshot?.documents ?? []
            Task { @MainActor in
                var decoded: [Game] = []
                for d in docs {
                    do {
                        decoded.append(try d.data(as: Game.self))
                    } catch {
                        debugLog("❌ Game decode failed (server) docId=\(d.documentID) error=\(error)")
                        debugLog("   keys:", Array(d.data().keys).sorted())
                    }
                }

                completion(decoded)
            }
        }
    }

    
    func loadGame(ownerUserId: String, gameId: String, completion: @escaping (Game?) -> Void) {
        Firestore.firestore()
            .collection("users").document(ownerUserId)
            .collection("games").document(gameId)
            .getDocument { snapshot, error in
                if let error = error {
                    debugLog("Error loading game \(gameId) for owner \(ownerUserId): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    debugLog("Game not found. owner=\(ownerUserId) gameId=\(gameId)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                Task { @MainActor in
                    do {
                        let game = try snapshot.data(as: Game.self)
                        completion(game)
                    } catch {
                        debugLog("Error decoding game \(gameId): \(error)")
                        completion(nil)
                    }
                }
            }
    }
    
    func updateGameLineup(ownerUserId: String?, gameId: String, jerseyNumbers: [String], batterIds: [String]) {
        guard let currentUid = user?.uid else { return }
        if let ownerUserId, ownerUserId != currentUid {
            debugLog("⏭️ Skipping updateGameLineup (not owner). currentUid=\(currentUid) ownerUserId=\(ownerUserId)")
            return
        }
        
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        guard jerseyNumbers.count == batterIds.count else {
            debugLog("❌ Lineup mismatch: jerseyNumbers=\(jerseyNumbers.count) batterIds=\(batterIds.count)")
            return
        }
        
        ref.updateData([
            "jerseyNumbers": jerseyNumbers,
            "batterIds": batterIds
        ]) { error in
            if let error = error { debugLog("Error updating lineup: \(error)") }
        }
    }
    
    
    private func deleteDocumentsInBatches(
        _ docs: [QueryDocumentSnapshot],
        db: Firestore,
        completion: @escaping (Error?) -> Void
    ) {
        guard !docs.isEmpty else {
            completion(nil)
            return
        }

        let chunk = Array(docs.prefix(450))
        let batch = db.batch()
        for doc in chunk {
            batch.deleteDocument(doc.reference)
        }

        batch.commit { error in
            if let error {
                completion(error)
                return
            }
            let remaining = Array(docs.dropFirst(chunk.count))
            self.deleteDocumentsInBatches(remaining, db: db, completion: completion)
        }
    }

    func deleteGame(gameId: String) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)
        ref.delete { error in
            if let error = error {
                debugLog("Error deleting game: \(error)")
            } else {
                debugLog("Game \(gameId) deleted successfully")
            }
        }
    }

    func archiveGame(gameId: String) {
        setGameArchivedState(gameId: gameId, isArchived: true)
    }

    func unarchiveGame(gameId: String) {
        setGameArchivedState(gameId: gameId, isArchived: false)
    }

    private func setGameArchivedState(gameId: String, isArchived: Bool) {
        guard let user = user else { return }
        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("games").document(gameId)

        let updates: [String: Any] = isArchived
            ? ["archivedAt": FieldValue.serverTimestamp()]
            : ["archivedAt": FieldValue.delete()]

        ref.updateData(updates) { error in
            if let error = error {
                debugLog("Error updating game archive state: \(error)")
            } else {
                debugLog("Game \(gameId) archive state updated. archived=\(isArchived)")
            }
        }
    }

    func deleteGameCascade(gameId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let db = Firestore.firestore()
        let ownerUid = user.uid
        let gameRef = db.collection("users").document(ownerUid)
            .collection("games").document(gameId)

        let gameEventsRef = gameRef.collection("pitchEvents")
        gameEventsRef.getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let gameDocs = snapshot?.documents ?? []
            self.deleteDocumentsInBatches(gameDocs, db: db) { deleteError in
                if let deleteError {
                    completion(.failure(deleteError))
                    return
                }

                gameRef.delete { deleteGameError in
                    if let deleteGameError {
                        completion(.failure(deleteGameError))
                        return
                    }

                    db.collectionGroup("pitchEvents")
                        .whereField("gameId", isEqualTo: gameId)
                        .getDocuments { pitchSnapshot, pitchError in
                            if let pitchError {
                                completion(.failure(pitchError))
                                return
                            }

                            let allDocs = pitchSnapshot?.documents ?? []
                            let pitcherDocs = allDocs.filter { doc in
                                doc.reference.path.contains("/pitchers/")
                            }

                            self.deleteDocumentsInBatches(pitcherDocs, db: db) { pitcherDeleteError in
                                if let pitcherDeleteError {
                                    completion(.failure(pitcherDeleteError))
                                    return
                                }
                                completion(.success(()))
                            }
                        }
                }
            }
        }
    }
    
    // MARK: - Game field updates
    func updateGameInning(ownerUserId: String?, gameId: String, inning: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["inning": inning]) { error in
            if let error = error { debugLog("Error updating inning: \(error)") }
        }
    }
    
    func updateGameHits(ownerUserId: String?, gameId: String, hits: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["hits": hits]) { error in
            if let error = error { debugLog("Error updating hits: \(error)") }
        }
    }
    
    func updateGameWalks(ownerUserId: String?, gameId: String, walks: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["walks": walks]) { error in
            if let error = error { debugLog("Error updating walks: \(error)") }
        }
    }
    
    func updateGameBalls(ownerUserId: String?, gameId: String, balls: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["balls": balls]) { error in
            if let error = error { debugLog("Error updating balls: \(error)") }
        }
    }
    
    func updateGameStrikes(ownerUserId: String?, gameId: String, strikes: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["strikes": strikes]) { error in
            if let error = error { debugLog("Error updating strikes: \(error)") }
        }
    }
    
    func updateGameUs(ownerUserId: String?, gameId: String, us: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["us": us]) { error in
            if let error = error { debugLog("Error updating us score: \(error)") }
        }
    }
    
    func updateGameThem(ownerUserId: String?, gameId: String, them: Int) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["them": them]) { error in
            if let error = error { debugLog("Error updating them score: \(error)") }
        }
    }

    func updateGameProgressTimestamp(ownerUserId: String?, gameId: String) {
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(["progressUpdatedAt": FieldValue.serverTimestamp()]) { error in
            if let error = error { debugLog("Error updating progress timestamp: \(error)") }
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
        data["progressUpdatedAt"] = FieldValue.serverTimestamp()
        guard !data.isEmpty else { return }
        
        guard let ref = gameDocRef(ownerUserId: ownerUserId, gameId: gameId) else { return }
        ref.updateData(data) { error in
            if let error = error { debugLog("Error updating game counts: \(error)") }
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
                if let err { debugLog("❌ setPendingPitch failed:", err) }
            }
        } catch {
            debugLog("❌ setPendingPitch encode failed:", error)
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
            if let err { debugLog("❌ clearPendingPitch failed:", err) }
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
                debugLog("❌ Failed to update selected batter: \(error)")
            }
        }
    }
    
}

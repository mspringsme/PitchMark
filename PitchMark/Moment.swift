//
//  Moment.swift
//  PitchMark
//
//  Phase 6 of the 2026-09-24 Coach/Parent/Family direction: Moments V1.
//  "Capture now, create later" - this file is deliberately minimal: a
//  Moment is just enough metadata to find a clip again later. Video files
//  stay on-device (mirrors Utilities.swift's local-portrait-storage
//  pattern exactly); only this small metadata record syncs to Firestore.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct Moment: Identifiable, Codable {
    @DocumentID var id: String?
    var createdAt: Date = Date()
    var teamId: String? = nil
    var playerId: String? = nil
    var playerName: String? = nil
    var durationSeconds: Double? = nil
}

// MARK: - Local video storage (mirrors Utilities.swift's portrait pattern)

private func momentsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/Moments", isDirectory: true)
}

func localMomentVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId).mov")
}

/// Copies a picker's temp file into the app's own sandbox - the temp URL
/// `UIImagePickerController` hands back does not survive past the current
/// launch.
@discardableResult
func saveLocalMomentVideo(from sourceURL: URL, momentId: String) -> Bool {
    guard let destinationURL = localMomentVideoURL(for: momentId) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return true
    } catch {
        debugLog("❌ saveLocalMomentVideo failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalMomentVideo(momentId: String) {
    guard let url = localMomentVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

// MARK: - AuthManager persistence

extension AuthManager {
    func saveMoment(_ moment: Moment, completion: @escaping (Result<Moment, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document()

        var moment = moment
        moment.id = ref.documentID

        do {
            try ref.setData(from: moment) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(moment))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func loadMoments(completion: @escaping ([Moment]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                let moments: [Moment] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Moment.self)
                } ?? []
                completion(moments)
            }
    }
}

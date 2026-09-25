//
//  FamilyContact.swift
//  PitchMark
//
//  Phase 9 of the 2026-09-24 Coach/Parent/Family direction: Family V1.
//  Deliberately not a second account type - family members never install
//  or sign into PitchMark. Just enough to drive one-tap share-sheet
//  updates. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FamilyContact: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date = Date()
}

extension AuthManager {
    func saveFamilyContact(name: String, completion: @escaping (Result<FamilyContact, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("familyContacts").document()

        var contact = FamilyContact(name: name)
        contact.id = ref.documentID

        do {
            try ref.setData(from: contact) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(contact))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func loadFamilyContacts(completion: @escaping ([FamilyContact]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("familyContacts")
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                let contacts: [FamilyContact] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: FamilyContact.self)
                } ?? []
                completion(contacts)
            }
    }

    func deleteFamilyContact(_ contact: FamilyContact, completion: @escaping (Error?) -> Void) {
        guard let user = user, let id = contact.id else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("familyContacts").document(id)
            .delete { error in
                completion(error)
            }
    }
}

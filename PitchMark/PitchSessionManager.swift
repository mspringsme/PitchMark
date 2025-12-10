//
//  PitchSessionManager.swift
//  PitchMark
//
//  Created by Mark Springer on 10/14/25.
//
import SwiftUI

class PitchSessionManager: ObservableObject {
    @Published var pitchCount: Int = 0
    @Published var currentMode: PitchMode = .practice
    @Published var activePracticeId: String? = nil
    @Published var activePracticeName: String? = nil

    init() {
        ensureActivePracticeSessionExists()
    }

    init(observeResetNotification: Bool = false) {
        if observeResetNotification {
            NotificationCenter.default.addObserver(forName: Notification.Name("resetPracticeSession"), object: nil, queue: .main) { [weak self] _ in
                self?.resetPracticeSession()
            }
        }
    }

    func switchMode(to newMode: PitchMode) {
        currentMode = newMode
        pitchCount = 0
        if newMode == .practice {
            ensureActivePracticeSessionExists()
        }
    }

    func incrementCount() {
        pitchCount += 1
    }

    func resetPracticeSession() {
        // Only meaningful in practice mode
        guard currentMode == .practice else { return }
        let newId = UUID().uuidString
        let name = self.activePracticeName ?? ""
        var sessions = loadStoredPracticeSessions()
        sessions.append(["id": newId, "name": name, "date": Date().timeIntervalSince1970])
        saveStoredPracticeSessions(sessions)
        setActivePractice(id: newId, name: name)
        pitchCount = 0
        // Notify interested views to refresh
        NotificationCenter.default.post(name: .gameOrSessionChosen, object: nil, userInfo: [
            "type": "practice",
            "practiceId": newId,
            "practiceName": name
        ])
    }

    private func loadStoredPracticeSessions() -> [[String: Any]] {
        if let data = UserDefaults.standard.data(forKey: "storedPracticeSessions"),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }
        return []
    }

    private func saveStoredPracticeSessions(_ sessions: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: sessions, options: []) {
            UserDefaults.standard.set(data, forKey: "storedPracticeSessions")
        }
    }

    private func setActivePractice(id: String, name: String) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "activeIsPractice")
        defaults.removeObject(forKey: "activeGameId")
        defaults.set(id, forKey: "activePracticeId")
        defaults.set("tracker", forKey: "lastView")
        self.activePracticeId = id
        self.activePracticeName = name
    }

    private func ensureActivePracticeSessionExists() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "activePracticeId"), !existing.isEmpty {
            self.activePracticeId = existing
            // Try to find its name in stored sessions
            let sessions = loadStoredPracticeSessions()
            let name = sessions.first(where: { ($0["id"] as? String) == existing })?["name"] as? String
            self.activePracticeName = name ?? self.activePracticeName
            return
        }
        // Do not auto-create a default practice session
        self.activePracticeId = nil
        self.activePracticeName = nil
    }
}


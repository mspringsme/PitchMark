//
//  HangReporter.swift
//  PitchMark
//
//  Catches the app's freezes (2026-11-26: a scorer froze twice on the
//  result sheet in a signed-in live game, and the demo used by UI tests
//  can't reproduce it). iOS's MetricKit records the main thread's stack
//  when the app hangs or crashes and hands the report over on a later
//  launch. Each report is kept on this phone (Documents/Diagnostics) and
//  saved to the account at users/{uid}/diagnostics (the users/** rule, no
//  rules change), where `functions/scripts/readDiagnostics.js` reads it.
//
//  PitchMark only.
//

import Foundation
import MetricKit
import FirebaseAuth
import FirebaseFirestore

final class HangReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = HangReporter()
    private var started = false

    /// Firestore holds 1 MB per document; a hang report is usually far less.
    static let maxReportCharacters = 800_000

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        // Reports that arrived before sign-in finished are still waiting.
        handle(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        handle(payloads)
    }

    private func handle(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let hangs = payload.hangDiagnostics?.count ?? 0
            let crashes = payload.crashDiagnostics?.count ?? 0
            guard hangs + crashes > 0 else { continue }
            let json = String(data: payload.jsonRepresentation(), encoding: .utf8) ?? ""
            let kind = hangs > 0 ? "hang" : "crash"
            saveLocally(json, kind: kind, at: payload.timeStampEnd)
            upload(json, kind: kind, at: payload.timeStampEnd)
        }
    }

    private func saveLocally(_ json: String, kind: String, at date: Date) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = docs.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(kind)-\(Int(date.timeIntervalSince1970)).json"
        try? json.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func upload(_ json: String, kind: String, at date: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        Firestore.firestore().collection("users").document(uid).collection("diagnostics").addDocument(data: [
            "kind": kind,
            "endedAt": Timestamp(date: date),
            "receivedAt": FieldValue.serverTimestamp(),
            "appVersion": "\(version) (\(build))",
            "report": String(json.prefix(Self.maxReportCharacters))
        ]) { error in
            if let error { debugLog("⚠️ diagnostics upload:", error.localizedDescription) }
        }
    }
}

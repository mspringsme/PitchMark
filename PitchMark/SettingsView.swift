//
//  SettingsView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//

import SwiftUI
import FirebaseAuth
import UIKit
import CoreImage
import FirebaseFirestore
import AVFoundation

struct PitcherPitchStats: Codable {
    var count: Int
    var hitSpotCount: Int
}

private struct SettingsGameSummarySheetView: View {
    let pitcherName: String
    let game: Game
    let events: [PitchEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    private var totalPitches: Int { events.count }
    private var strikes: Int {
        events.filter { $0.isStrike || $0.strikeLooking || $0.strikeSwinging }.count
    }
    private var balls: Int {
        events.filter { event in
            if let isBall = event.isBall { return isBall }
            return !(event.isStrike || event.strikeLooking || event.strikeSwinging)
        }.count
    }
    private var hitSpots: Int {
        events.filter { isLocationMatch($0) }.count
    }
    private var strikeLooking: Int { events.filter { $0.strikeLooking }.count }
    private var strikeSwinging: Int { events.filter { $0.strikeSwinging }.count }
    private var walks: Int {
        events.filter { event in
            guard let outcome = event.outcome?.lowercased() else { return false }
            return outcome.contains("walk") || outcome == "bb"
        }.count
    }
    private var wildPitches: Int { events.filter { $0.wildPitch }.count }
    private var passedBalls: Int { events.filter { $0.passedBall }.count }
    private var pitchBreakdown: [(name: String, count: Int)] {
        Dictionary(grouping: events, by: { $0.pitch.isEmpty ? "-" : $0.pitch })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
    }

    private var outcomeBreakdown: [(name: String, count: Int)] {
        Dictionary(grouping: events, by: { event in
            let outcome = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return outcome.isEmpty ? "No outcome" : outcome
        })
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }
    }

    private func percent(_ part: Int, _ total: Int) -> String {
        guard total > 0 else { return "0%" }
        let value = (Double(part) / Double(total)) * 100.0
        return String(format: "%.0f%%", value.rounded())
    }

    private var shareText: String {
        let pitchLines = pitchBreakdown.isEmpty ? "None" : pitchBreakdown.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        let outcomeLines = outcomeBreakdown.isEmpty ? "None" : outcomeBreakdown.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        return """
        PitchMark Game Summary
        Pitcher: \(pitcherName)
        Opponent: \(game.opponent)
        Date: \(game.date.formatted(date: .abbreviated, time: .omitted))

        Pitches: \(totalPitches)
        Strikes: \(strikes) of \(totalPitches) (\(percent(strikes, totalPitches)))
        Balls: \(balls) of \(totalPitches) (\(percent(balls, totalPitches)))
        Hit Spot: \(hitSpots) of \(totalPitches) (\(percent(hitSpots, totalPitches)))

        Strike Looking: \(strikeLooking)
        Strike Swinging: \(strikeSwinging)
        Walks: \(walks)
        Wild Pitches: \(wildPitches)
        Passed Balls: \(passedBalls)

        Metric Definitions:
        Strike % = Strikes / Total Pitches
        Ball % = Balls / Total Pitches
        Hit Spot % = Location matches / Total Pitches

        Pitch Breakdown: \(pitchLines)
        Outcome Breakdown: \(outcomeLines)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pitcherName)
                            .font(.title3.weight(.semibold))
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Group {
                        summaryRow("Total Pitches", "\(totalPitches)")
                        summaryRow("Strike %", "\(percent(strikes, totalPitches)) (\(strikes)/\(totalPitches))")
                        summaryRow("Ball %", "\(percent(balls, totalPitches)) (\(balls)/\(totalPitches))")
                        summaryRow("Hit Spot %", "\(percent(hitSpots, totalPitches)) (\(hitSpots)/\(totalPitches))")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Metric Definitions")
                            .font(.subheadline.weight(.semibold))
                        Text("Strike % = Strikes / Total Pitches")
                        Text("Ball % = Balls / Total Pitches")
                        Text("Hit Spot % = Location matches / Total Pitches")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Group {
                        summaryRow("Strike Looking", "\(strikeLooking)")
                        summaryRow("Strike Swinging", "\(strikeSwinging)")
                        summaryRow("Walks", "\(walks)")
                        summaryRow("Wild Pitches", "\(wildPitches)")
                        summaryRow("Passed Balls", "\(passedBalls)")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pitch Breakdown")
                            .font(.headline)
                        if pitchBreakdown.isEmpty {
                            Text("No pitches recorded.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(pitchBreakdown.enumerated()), id: \.offset) { _, item in
                                summaryRow(item.name, "\(item.count)")
                            }
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Outcome Breakdown")
                            .font(.headline)
                        if outcomeBreakdown.isEmpty {
                            Text("No outcomes recorded.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(outcomeBreakdown.enumerated()), id: \.offset) { _, item in
                                summaryRow(item.name, "\(item.count)")
                            }
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("Game Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(totalPitches == 0)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareText])
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}

struct PitcherOutcomeStats: Codable {
    var count: Int
    var jerseys: [String]
}

struct PitcherLocationStats: Codable {
    var count: Int
    var hitCount: Int
    var missCount: Int
    var jerseys: [String]
}

struct PitcherStatsDoc: Codable {
    var pitcherId: String
    var scope: String
    var scopeId: String
    var updatedAt: Date?
    var totalCount: Int
    var strikeCount: Int
    var ballCount: Int
    var swingingStrikeCount: Int
    var lookingStrikeCount: Int
    var wildPitchCount: Int
    var passedBallCount: Int
    var walkCount: Int
    var hitSpotCount: Int
    var pitchStats: [String: PitcherPitchStats]
    var outcomeStats: [String: PitcherOutcomeStats]
    var pitchLocationStats: [String: PitcherLocationStats]
}

struct SettingsView: View {
    @Binding var templates: [PitchTemplate]
    @Binding var games: [Game]
    @Binding var pitchers: [Pitcher]
    let allPitches: [String]
    @Binding var selectedTemplate: PitchTemplate? // ✅ Add this line
    @Binding var codeShareInitialTab: Int
    @Binding var showCodeShareSheet: Bool
    @Binding var shareCode: String
    @Binding var codeShareSheetID: UUID
    @Binding var showCodeShareModePicker: Bool
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showSignOutConfirmation = false
    @State private var showChangeEmailSheet = false
    @State private var changeEmailText: String = ""
    @State private var changeEmailError: String? = nil
    @State private var changeEmailStatus: String? = nil
    @State private var isChangingEmail = false
    @State private var requiresRecentLogin = false
    @State private var showDeleteAccountSheet = false
    @State private var deleteAccountText: String = ""
    @State private var deleteAccountError: String? = nil
    @State private var isDeletingAccount = false
    @State private var requiresDeleteRecentLogin = false
    @State private var showAccountActionsSheet = false
    @State private var templatePendingDeletion: PitchTemplate?
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var showGameChooser = false
    @State private var showPracticeChooser = false
    @State private var editorTemplate: PitchTemplate? = nil
    @State private var showAddPitcher = false
    @State private var newPitcherName: String = ""
    @State private var editingPitcher: Pitcher? = nil

    @State private var templatePendingShare: PitchTemplate? = nil
    @State private var showShareTemplateSheet = false
    @State private var shareTargetEmail: String = ""
    @State private var shareTemplateError: String = ""
    @State private var isSharingTemplate = false
    @State private var isRefreshingTemplates = false
    @State private var hiddenTemplateIds: Set<String> = []
    @State private var hiddenPitcherIds: Set<String> = []
    @State private var templateActionTargetId: UUID? = nil
    @State private var pitcherActionTargetId: String? = nil
    @State private var showHiddenTemplates = false
    @State private var showHiddenPitchers = false
    @State private var statsPitcher: Pitcher? = nil

    @State private var showInviteJoinSheet = false
    @State private var inviteJoinText: String = ""
    @State private var inviteJoinError: String? = nil
    @State private var showProPaywall = false
    @State private var showProGateAlert = false
    @State private var proGateMessage: String = ""
    @State private var isJoiningInvite = false
    @State private var showQRScanner = false
    @State private var showCameraUnavailableAlert = false
    @State private var showCameraPermissionAlert = false

    private static let quickLaunchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal)
    }

    @State private var copyPitcherTarget: Pitcher? = nil
    @State private var showCopyPitcherConfirm = false

    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    @State private var encryptedSelectionByPracticeId: [String: Bool] = [:]

    @State private var showPitcherShareSheet = false
    @State private var showPitcherShareActivity = false
    @State private var sharePitcherLink: String = ""
    @State private var sharePitcherQR: UIImage? = nil
    @State private var isGeneratingPitcherShare = false
    @State private var pitcherShareError: String? = nil
    @State private var showPitcherShareError = false
    @State private var isCopyingPitcher = false
    @State private var ownedPitchersListener: ListenerRegistration? = nil
    @State private var sharedPitchersListener: ListenerRegistration? = nil
    @State private var livePitchersById: [String: Pitcher] = [:]
    @State private var storeGlowAngle: Double = 0
    @State private var storeGlowPulse = false
    
    private var sortedTemplates: [PitchTemplate] {
        templates.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var sortedPitchers: [Pitcher] {
        pitchers.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func isTemplateEditable(_ template: PitchTemplate) -> Bool {
        guard let currentUid = authManager.user?.uid else { return false }
        if let owner = template.ownerUid {
            return owner == currentUid
        }
        return true
    }
    
    private func showDeleteConfirmation(for template: PitchTemplate) {
        templatePendingDeletion = template
        showDeleteAlert = true
    }

    private func confirmDeleteTemplate() {
        guard let template = templatePendingDeletion else { return }
        authManager.deleteTemplate(template)
        templates.removeAll { $0.id == template.id }
        templatePendingDeletion = nil
    }

    private func beginShareTemplate(_ template: PitchTemplate) {
        templatePendingShare = template
        shareTargetEmail = ""
        shareTemplateError = ""
        showShareTemplateSheet = true
    }

    private func loadHiddenIds() {
        hiddenTemplateIds = Set(UserDefaults.standard.stringArray(forKey: PitchTrackerView.DefaultsKeys.hiddenTemplateIds) ?? [])
        hiddenPitcherIds = Set(UserDefaults.standard.stringArray(forKey: PitchTrackerView.DefaultsKeys.hiddenPitcherIds) ?? [])
    }

    private func saveHiddenTemplateIds() {
        UserDefaults.standard.set(Array(hiddenTemplateIds), forKey: PitchTrackerView.DefaultsKeys.hiddenTemplateIds)
    }

    private func saveHiddenPitcherIds() {
        UserDefaults.standard.set(Array(hiddenPitcherIds), forKey: PitchTrackerView.DefaultsKeys.hiddenPitcherIds)
    }

    private var visibleTemplates: [PitchTemplate] {
        sortedTemplates.filter { !hiddenTemplateIds.contains($0.id.uuidString) }
    }

    private var hiddenTemplates: [PitchTemplate] {
        sortedTemplates.filter { hiddenTemplateIds.contains($0.id.uuidString) }
    }

    private var visiblePitchers: [Pitcher] {
        sortedPitchers.filter { !hiddenPitcherIds.contains($0.id ?? "") }
    }

    private var hiddenPitchers: [Pitcher] {
        sortedPitchers.filter { hiddenPitcherIds.contains($0.id ?? "") }
    }
    
    private func savePracticeSessions(_ sessions: [PracticeSession]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: "storedPracticeSessions")
        }
    }
    private func loadPracticeSessions() -> [PracticeSession] {
        guard let data = UserDefaults.standard.data(forKey: "storedPracticeSessions") else {
            return []
        }
        let decoder = JSONDecoder()
        do {
            let sessions = try decoder.decode([PracticeSession].self, from: data)
            return sessions
        } catch {
            // Optionally log the error in debug builds
            // print("Failed to decode PracticeSession array: \(error)")
            return []
        }
    }
    
    private func joinByCodeFromSettings() {
        // set the tab first
        showCodeShareModePicker = false
        codeShareInitialTab = 1
        shareCode = ""
        codeShareSheetID = UUID()

        // dismiss settings, then present after a small delay
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showCodeShareSheet = true
        }
    }

    private func inviteToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }

        if trimmed.contains("://") { return nil }
        return trimmed
    }

    private func joinLiveGameFromInvite() {
        inviteJoinError = nil

        if !subscriptionManager.isPro {
            showProPaywall = true
            return
        }

        guard let token = inviteToken(from: inviteJoinText) else {
            inviteJoinError = "Paste a valid invite link."
            return
        }

        isJoiningInvite = true
        LiveGameService.shared.joinLiveGameByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                self.isJoiningInvite = false

                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "type": "liveGame",
                            "liveId": liveId
                        ]
                    )
                    self.inviteJoinText = ""
                    self.showInviteJoinSheet = false
                    dismiss()

                case .failure(let err):
                    self.inviteJoinError = err.localizedDescription
                }
            }
        }
    }

    private func openCameraForJoin() {
        if showInviteJoinSheet {
            showInviteJoinSheet = false
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraUnavailableAlert = true
            }
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            presentCameraFromJoin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        presentCameraFromJoin()
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        @unknown default:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        }
    }

    private func presentCameraFromJoin() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showQRScanner = true
        }
    }

    private func launchGame(_ game: Game) {
        guard let gameId = game.id else { return }
        let ownerUid = authManager.user?.uid ?? ""

        let defaults = UserDefaults.standard
        defaults.set(gameId, forKey: PitchTrackerView.DefaultsKeys.activeGameId)
        defaults.set(ownerUid, forKey: PitchTrackerView.DefaultsKeys.activeGameOwnerUserId)
        defaults.set(false, forKey: PitchTrackerView.DefaultsKeys.activeIsPractice)
        defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activePracticeId)
        defaults.set("tracker", forKey: PitchTrackerView.DefaultsKeys.lastView)

        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "game",
                    "gameId": gameId,
                    "ownerUserId": ownerUid
                ]
            )
        }
    }

    private func quickLaunchDateCaption(for game: Game) -> String {
        Self.quickLaunchDateFormatter.string(from: game.date)
    }

    private func quickLaunchId(for game: Game) -> String {
        if let id = game.id, !id.isEmpty { return id }
        return "\(game.opponent)|\(game.date.timeIntervalSince1970)"
    }

    private struct QuickLaunchGame: Identifiable {
        let id: String
        let game: Game
    }

    private struct QuickLaunchPractice: Identifiable {
        let id: String
        let session: PracticeSession?
    }

    private func practiceQuickLaunchItems() -> [QuickLaunchPractice] {
        let sessions = loadPracticeSessions().sorted { $0.date > $1.date }
        return sessions.map { QuickLaunchPractice(id: $0.id ?? UUID().uuidString, session: $0) }
    }

    private func launchPractice(_ session: PracticeSession?) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PitchTrackerView.DefaultsKeys.activeIsPractice)
        defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameOwnerUserId)
        defaults.set("tracker", forKey: PitchTrackerView.DefaultsKeys.lastView)

        if let session, let pid = session.id {
            defaults.set(pid, forKey: PitchTrackerView.DefaultsKeys.activePracticeId)
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "practice",
                    "practiceId": pid,
                    "practiceName": session.name
                ]
            )
        } else {
            defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activePracticeId)
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "practice",
                    "practiceId": "__GENERAL__",
                    "practiceName": "General"
                ]
            )
        }
        dismiss()
    }

    private func qrImage(for text: String) -> UIImage? {
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func beginPitcherShare(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        isGeneratingPitcherShare = true
        authManager.createPitcherInviteToken(pitcherId: pitcherId) { result in
            DispatchQueue.main.async {
                self.isGeneratingPitcherShare = false
                switch result {
                case .success(let token):
                    let link = "pitchmark://pitcher?token=\(token)"
                    self.sharePitcherLink = link
                    self.sharePitcherQR = self.qrImage(for: link)
                    self.showPitcherShareSheet = true
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func reclaimPitcher(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        authManager.reclaimPitcher(pitcherId: pitcherId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    if let id = updated.id, let idx = pitchers.firstIndex(where: { $0.id == id }) {
                        pitchers[idx] = updated
                    } else {
                        authManager.loadPitchers { loaded in
                            pitchers = loaded
                        }
                    }
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func copyPitcher(_ pitcher: Pitcher) {
        guard !isCopyingPitcher else { return }
        isCopyingPitcher = true
        authManager.copyPitcherWithEvents(sourcePitcher: pitcher) { result in
            DispatchQueue.main.async {
                self.isCopyingPitcher = false
                switch result {
                case .success(let newPitcher):
                    pitchers.append(newPitcher)
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func startPitchersListenerIfNeeded() {
        guard ownedPitchersListener == nil && sharedPitchersListener == nil else { return }
        guard let uid = authManager.user?.uid else { return }

        let db = Firestore.firestore()
        let ownedRef = db.collection("pitchers").whereField("ownerUid", isEqualTo: uid)
        let sharedRef = db.collection("pitchers").whereField("sharedWith", arrayContains: uid)

        func mergeDocs(_ docs: [QueryDocumentSnapshot]) {
            Task { @MainActor in
                var map = livePitchersById
                for doc in docs {
                    do {
                        let pitcher = try doc.data(as: Pitcher.self)
                        if let id = pitcher.id {
                            map[id] = pitcher
                        }
                    } catch {
                        print("❌ Pitcher decode failed (listener) docId=\(doc.documentID) error=\(error)")
                    }
                }
                livePitchersById = map
                pitchers = Array(map.values)
            }
        }

        ownedPitchersListener = ownedRef.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ owned pitchers listener error:", error.localizedDescription)
                return
            }
            let docs = snapshot?.documents ?? []
            mergeDocs(docs)
        }

        sharedPitchersListener = sharedRef.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ shared pitchers listener error:", error.localizedDescription)
                return
            }
            let docs = snapshot?.documents ?? []
            mergeDocs(docs)
        }
    }

    @ViewBuilder
    private var inviteJoinSheetView: some View {
        VStack(spacing: 16) {
            Text("Join a Live Game")
                .font(.headline)

            VStack(spacing: 6) {
                Text("You'll join as a participant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Tip: scan the primary user's code to open quickly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Paste invite link", text: $inviteJoinText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let error = inviteJoinError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(isJoiningInvite ? "Joining..." : "Join") {
                joinLiveGameFromInvite()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviteJoinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningInvite)

            Button("Scan QR Code") {
                openCameraForJoin()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var templatesHeader: some View {
        HStack {
            Text("Code Grid Keys")
                .font(.headline)
                .bold()
            Spacer()
            Button {
                guard !isRefreshingTemplates else { return }
                isRefreshingTemplates = true
                authManager.loadTemplates { loaded in
                    templates = loaded
                    if selectedTemplate == nil {
                        selectedTemplate = loaded.first
                    }
                    isRefreshingTemplates = false
                }
            } label: {
                Image(systemName: isRefreshingTemplates ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingTemplates)
            Button {
                editorTemplate = PitchTemplate(
                    id: UUID(),
                    name: "",
                    pitches: [],
                    codeAssignments: []
                )
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var pitchersHeader: some View {
        HStack {
            Text("Pitchers")
                .font(.headline)
                .bold()
            Spacer()
            Button {
                editingPitcher = nil
                newPitcherName = ""
                showAddPitcher = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            templatesHeader
                .padding(.horizontal, 4)
            templatesListView

            if showHiddenTemplates {
                if !hiddenTemplates.isEmpty {
                    hiddenTemplatesSection
                }
            }
        }
    }

    private var pitchersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            pitchersHeader
                .padding(.horizontal, 4)
            pitchersListView

            if showHiddenPitchers {
                if !hiddenPitchers.isEmpty {
                    hiddenPitchersSection
                }
            }
        }
    }

    @ViewBuilder
    private var pitchersListView: some View {
        if pitchers.isEmpty {
            Text("No pitchers saved")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if visiblePitchers.isEmpty {
            Text("No visible pitchers")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            let selected = visiblePitchers.first(where: { $0.id == pitcherActionTargetId })

            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visiblePitchers) { pitcher in
                            let isActive = pitcher.id == pitcherActionTargetId
                            let isOwned = pitcher.isActiveOwner(currentUid: authManager.user?.uid)
                            Button(pitcher.name) {
                                pitcherActionTargetId = (pitcherActionTargetId == pitcher.id) ? nil : pitcher.id
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(isOwned ? .black : Color.gray.opacity(0.45))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isActive ? Color.black.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(Color.black, lineWidth: 1)
                            )
                        }

                        if !hiddenPitchers.isEmpty {
                            Button(showHiddenPitchers ? "Hide Archived" : "Show Archived") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showHiddenPitchers.toggle()
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                    }
                    .padding(.horizontal)
                }

                if let pitcher = selected {
                    let isActiveOwner = pitcher.isActiveOwner(currentUid: authManager.user?.uid)
                    HStack(spacing: 8) {
                        Button("Edit") {
                            editingPitcher = pitcher
                            newPitcherName = pitcher.name
                            showAddPitcher = true
                        }
                        .buttonStyle(.bordered)

                        Button("Stats") {
                            statsPitcher = pitcher
                        }
                        .buttonStyle(.bordered)

                        if isActiveOwner {
                            Button(isGeneratingPitcherShare ? "Sharing..." : "Owned") {
                                beginPitcherShare(pitcher)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isGeneratingPitcherShare)
                        } else {
                            Button("Reclaim") {
                                reclaimPitcher(pitcher)
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Button("Archive") {
                                if let id = pitcher.id {
                                    hiddenPitcherIds.insert(id)
                                    saveHiddenPitcherIds()
                                    if pitcherActionTargetId == id {
                                        pitcherActionTargetId = nil
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Button(isCopyingPitcher ? "Copying..." : "Copy") {
                                copyPitcherTarget = pitcher
                                showCopyPitcherConfirm = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .disabled(isCopyingPitcher)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer().frame(height: 8)
            }
        }
    }
    
    @ViewBuilder
    private var templatesListView: some View {
        if templates.isEmpty {
            Text("No templates saved")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if visibleTemplates.isEmpty {
            Text("No visible templates")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            let selected = visibleTemplates.first(where: { $0.id == templateActionTargetId })

            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            let isActive = template.id == templateActionTargetId
                            Button(template.name) {
                                templateActionTargetId = (templateActionTargetId == template.id) ? nil : template.id
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isActive ? Color.black.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(Color.black, lineWidth: 1)
                            )
                        }

                        if !hiddenTemplates.isEmpty {
                            Button(showHiddenTemplates ? "Hide Archived" : "Show Archived") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showHiddenTemplates.toggle()
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                    }
                    .padding(.horizontal)
                }

                if let template = selected {
                    HStack(spacing: 8) {
                        Button("Share") {
                            beginShareTemplate(template)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isTemplateEditable(template))

                        Button("Edit") {
                            editorTemplate = template
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isTemplateEditable(template))

                        Spacer()

                        Button("Archive") {
                            hiddenTemplateIds.insert(template.id.uuidString)
                            saveHiddenTemplateIds()
                            if templateActionTargetId == template.id {
                                templateActionTargetId = nil
                            }
                            if selectedTemplate?.id == template.id {
                                selectedTemplate = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.horizontal)
                }

                Spacer().frame(height: 8)
            }
        }
    }
    
    @ViewBuilder
    private var hiddenTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden Templates")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(hiddenTemplates) { template in
                    HStack {
                        Text(template.name)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Unhide") {
                            hiddenTemplateIds.remove(template.id.uuidString)
                            saveHiddenTemplateIds()
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                    .padding(.vertical, 6)
                    Divider().padding(.leading)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var hiddenPitchersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden Pitchers")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(hiddenPitchers) { pitcher in
                    HStack {
                        Text(pitcher.name)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Unhide") {
                            if let id = pitcher.id {
                                hiddenPitcherIds.remove(id)
                                saveHiddenPitcherIds()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                    .padding(.vertical, 6)
                    Divider().padding(.leading)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var storeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                Storefront
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart")
                        .font(.subheadline.weight(.semibold))
                    Text("store")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.black.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(Color.black, lineWidth: 1)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.cyan, .magenta, .yellow, .lime, .orange]),
                                center: .center,
                                angle: .degrees(storeGlowAngle)
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 2)
                        .opacity(0.9)
                )
                .shadow(color: Color.cyan.opacity(storeGlowPulse ? 0.6 : 0.3), radius: storeGlowPulse ? 10 : 4)
                .padding(.horizontal)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        storeGlowAngle = 360
                    }
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        storeGlowPulse = true
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var accountActionsSheetView: some View {
        VStack(spacing: 16) {
            Text("Account")
                .font(.headline)

            Text("Signed in as \(authManager.userEmail)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                let current = authManager.userEmail
                changeEmailText = (current == "Unknown") ? "" : current
                changeEmailError = nil
                changeEmailStatus = nil
                requiresRecentLogin = false
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showChangeEmailSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundStyle(.blue)
                    Text("Change Email")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }

            Button(role: .destructive) {
                showSignOutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.red)
                    Text("Sign Out")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }
            .confirmationDialog(
                "Are you sure you want to sign out of \(authManager.userEmail)?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    showAccountActionsSheet = false
                    authManager.signOut()
                }
                Button("Cancel", role: .cancel) { }
            }

            Button(role: .destructive) {
                deleteAccountText = ""
                deleteAccountError = nil
                requiresDeleteRecentLogin = false
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showDeleteAccountSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                    Text("Delete Account")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }

        }
        .padding()
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var changeEmailSheetView: some View {
        VStack(spacing: 16) {
            Text("Change Email")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("New Email")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("name@example.com", text: $changeEmailText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let error = changeEmailError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = changeEmailStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if requiresRecentLogin {
                Button("Sign Out to Re-Authenticate", role: .destructive) {
                    showChangeEmailSheet = false
                    authManager.signOut()
                }
                .buttonStyle(.bordered)
            }

            Button(isChangingEmail ? "Sending..." : "Send Verification") {
                let trimmed = changeEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    changeEmailError = "Email required."
                    changeEmailStatus = nil
                    requiresRecentLogin = false
                    return
                }

                isChangingEmail = true
                changeEmailError = nil
                changeEmailStatus = nil
                requiresRecentLogin = false
                authManager.changeEmail(to: trimmed) { result in
                    DispatchQueue.main.async {
                        isChangingEmail = false
                        switch result {
                        case .success:
                            changeEmailError = nil
                            changeEmailStatus = "Verification email sent. Confirm it to finish updating your account email."
                            requiresRecentLogin = false
                        case .failure(let error):
                            changeEmailError = error.localizedDescription
                            changeEmailStatus = nil
                            if let changeError = error as? ChangeEmailError {
                                if case .requiresRecentLogin = changeError {
                                    requiresRecentLogin = true
                                } else {
                                    requiresRecentLogin = false
                                }
                            } else {
                                requiresRecentLogin = false
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChangingEmail)

            Button("Cancel", role: .cancel) {
                showChangeEmailSheet = false
            }
        }
        .padding()
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var deleteAccountSheetView: some View {
        VStack(spacing: 16) {
            Text("Delete Account")
                .font(.headline)

            Text("This permanently deletes your account and all data. Type DELETE to confirm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Type DELETE", text: $deleteAccountText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            if let error = deleteAccountError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if requiresDeleteRecentLogin {
                Button("Sign Out to Re-Authenticate", role: .destructive) {
                    showDeleteAccountSheet = false
                    authManager.signOut()
                }
                .buttonStyle(.bordered)
            }

            Button(isDeletingAccount ? "Deleting..." : "Delete Account") {
                isDeletingAccount = true
                deleteAccountError = nil
                requiresDeleteRecentLogin = false
                authManager.deleteAccount { result in
                    DispatchQueue.main.async {
                        isDeletingAccount = false
                        switch result {
                        case .success:
                            deleteAccountText = ""
                            deleteAccountError = nil
                            requiresDeleteRecentLogin = false
                            showDeleteAccountSheet = false
                        case .failure(let error):
                            deleteAccountError = error.localizedDescription
                            if let deleteError = error as? DeleteAccountError {
                                if case .requiresRecentLogin = deleteError {
                                    requiresDeleteRecentLogin = true
                                } else {
                                    requiresDeleteRecentLogin = false
                                }
                            } else {
                                requiresDeleteRecentLogin = false
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeletingAccount || deleteAccountText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")

            Button("Cancel", role: .cancel) {
                showDeleteAccountSheet = false
            }
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0)

                        sectionCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Quick Launch – Games")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        showGameChooser = true
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)

                                if !games.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            let sorted = games.sorted(by: { $0.date > $1.date })
                                            let quickGames = sorted.map { QuickLaunchGame(id: quickLaunchId(for: $0), game: $0) }
                                            ForEach(quickGames) { item in
                                                Button {
                                                    launchGame(item.game)
                                                } label: {
                                                    VStack(spacing: 4) {
                                                        Text(item.game.opponent)
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        Text(quickLaunchDateCaption(for: item.game))
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 10)
                                                    .frame(minWidth: 120)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .fill(Color.black.opacity(0.06))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }

                        sectionCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Quick Launch – Practice")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        showPracticeChooser = true
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)

                                let quickPractice = practiceQuickLaunchItems()
                                if !quickPractice.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(quickPractice) { item in
                                                Button {
                                                    launchPractice(item.session)
                                                } label: {
                                                    VStack(spacing: 4) {
                                                        Text(item.session?.name ?? "Practice")
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        Text(item.session.map { Self.quickLaunchDateFormatter.string(from: $0.date) } ?? "")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 10)
                                                    .frame(minWidth: 120)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .fill(Color.black.opacity(0.06))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }

                        sectionCard {
                            templatesSection
                        }

                        sectionCard {
                            pitchersSection
                        }

                        sectionCard {
                            storeSection
                        }
                    }
                    .padding(.top, 4)
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        showAccountActionsSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .font(.footnote.weight(.semibold))
                            Text("Signed in as: \(authManager.userEmail)")
                                .font(.footnote.weight(.semibold))
                            Image(systemName: "chevron.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule().fill(Color.black.opacity(0.06))
                        )
                        .overlay(
                            Capsule().stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showInviteJoinSheet) { inviteJoinSheetView }
            .fullScreenCover(isPresented: $showQRScanner) {
                ZStack(alignment: .bottom) {
                    QRScannerView { scanned in
                        inviteJoinText = scanned
                        inviteJoinError = nil
                        showQRScanner = false
                        joinLiveGameFromInvite()
                    } onCancel: {
                        showQRScanner = false
                    }

                    Button("Paste invite link") {
                        showQRScanner = false
                        showInviteJoinSheet = true
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This device doesn’t have a camera available.")
            }
            .alert("Camera Access Needed", isPresented: $showCameraPermissionAlert) {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enable Camera access in Settings to scan the owner’s QR code.")
            }
            .sheet(isPresented: $showAccountActionsSheet) { accountActionsSheetView }
            .sheet(isPresented: $showChangeEmailSheet) { changeEmailSheetView }
            .sheet(isPresented: $showDeleteAccountSheet) { deleteAccountSheetView }
            .sheet(isPresented: $showProPaywall) {
                ProPaywallView(
                    title: "PitchMark Pro",
                    message: "Invite links and participant connections require PitchMark Pro.",
                    allowsClose: true
                )
            }
            .alert("Upgrade to Pro", isPresented: $showProGateAlert) {
                Button("Not Now", role: .cancel) { }
                Button("Upgrade") {
                    showProPaywall = true
                }
            } message: {
                Text(proGateMessage)
            }
            .onAppear {
                loadHiddenIds()
                startPitchersListenerIfNeeded()
            }
            .onDisappear {
                ownedPitchersListener?.remove()
                ownedPitchersListener = nil
                sharedPitchersListener?.remove()
                sharedPitchersListener = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .pitcherSharedUpdated)) { _ in
                authManager.loadPitchers { loaded in
                    pitchers = loaded
                }
            }
            .sheet(isPresented: $showShareTemplateSheet) {
                VStack(spacing: 16) {
                    Text("Share Template")
                        .font(.headline)

                    if let template = templatePendingShare {
                        Text(template.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    TextField("Recipient Email", text: $shareTargetEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)

                    if !shareTemplateError.isEmpty {
                        Text(shareTemplateError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Button("Cancel") {
                            showShareTemplateSheet = false
                        }
                        Spacer()
                        Button(isSharingTemplate ? "Sharing..." : "Share") {
                            guard let template = templatePendingShare else { return }

                            isSharingTemplate = true
                            shareTemplateError = ""

                            authManager.shareTemplateByEmail(template, email: shareTargetEmail) { err in
                                DispatchQueue.main.async {
                                    isSharingTemplate = false
                                    if let err {
                                        shareTemplateError = err.localizedDescription
                                    } else {
                                        showShareTemplateSheet = false
                                    }
                                }
                            }
                        }
                        .disabled(shareTargetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSharingTemplate)
                    }
                }
                .padding()
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showPitcherShareSheet) {
                VStack(spacing: 16) {
                    Text("Share Pitcher")
                        .font(.headline)

                    if !sharePitcherLink.isEmpty {
                        Text(sharePitcherLink)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal)
                    }

                    if let qr = sharePitcherQR {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack {
                        Button("Close") {
                            showPitcherShareSheet = false
                        }
                        Spacer()
                        Button("Share") {
                            showPitcherShareActivity = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sharePitcherLink.isEmpty)
                    }
                }
                .padding()
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showPitcherShareActivity) {
                let items: [Any] = {
                    if let qr = sharePitcherQR {
                        return [sharePitcherLink, qr]
                    }
                    return [sharePitcherLink]
                }()
                ShareSheet(items: items)
            }
            .alert("Are you sure you want to delete this template?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let template = templatePendingDeletion {
                        authManager.deleteTemplate(template)
                        templates.removeAll { $0.id == template.id }
                        templatePendingDeletion = nil
                    }
                }
            }
            .alert("Pitcher Share", isPresented: $showPitcherShareError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(pitcherShareError ?? "Something went wrong.")
            }
            .confirmationDialog(
                "Copy pitcher?",
                isPresented: $showCopyPitcherConfirm,
                titleVisibility: .visible
            ) {
                Button("Copy", role: .destructive) {
                    if let pitcher = copyPitcherTarget {
                        copyPitcher(pitcher)
                    }
                    copyPitcherTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    copyPitcherTarget = nil
                }
            } message: {
                Text("This creates a new pitcher profile you own, with the same stats. It won’t affect the shared pitcher.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if !subscriptionManager.isPro {
                            proGateMessage = "Joining games requires PitchMark Pro."
                            showProGateAlert = true
                            return
                        }
                        inviteJoinError = nil
                        inviteJoinText = ""
                        showQRScanner = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2")
                                .font(.subheadline.weight(.semibold))
                            Text("Join a Game")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.black.opacity(0.06))
                        )
                        .overlay(
                            Capsule().stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .animation(nil, value: storeGlowAngle)
                    .animation(nil, value: storeGlowPulse)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        // Notify listeners (e.g., PitchTrackerView) to reload with the latest selected template before dismissing
                        if let tmpl = selectedTemplate {
                            NotificationCenter.default.post(
                                name: .templateSelectionDidChange,
                                object: nil,
                                userInfo: [
                                    "templateId": tmpl.id.uuidString
                                ]
                            )
                        } else {
                            NotificationCenter.default.post(name: .templateSelectionDidChange, object: nil, userInfo: nil)
                        }

                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .animation(nil, value: storeGlowAngle)
                    .animation(nil, value: storeGlowPulse)
                    .accessibilityLabel("Close Settings")
                }
            }
            //.navigationTitle("Settings")
            .sheet(item: $editorTemplate) { template in
                TemplateEditorView(
                    template: template,
                    allPitches: allPitches,
                    onSave: { updatedTemplate in
                        if let index = templates.firstIndex(where: { $0.id == updatedTemplate.id }) {
                            templates[index] = updatedTemplate
                        } else {
                            templates.append(updatedTemplate)
                        }
                        
                        authManager.saveTemplate(updatedTemplate) // ✅ persist to Firestore
                    }
                )
            }
            .sheet(isPresented: $showAddPitcher) {
                VStack(spacing: 16) {
                    Text(editingPitcher == nil ? "New Pitcher" : "Edit Pitcher")
                        .font(.headline)

                    TextField("Name", text: $newPitcherName)
                        .textFieldStyle(.roundedBorder)


                    HStack {
                        Button("Cancel") {
                            showAddPitcher = false
                            editingPitcher = nil
                        }
                        Spacer()
                        Button("Save") {
                            let name = newPitcherName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }

                            if let editing = editingPitcher, let pid = editing.id {
                                authManager.updatePitcher(id: pid, name: name, templateId: editing.templateId) { updated in
                                    if let updated,
                                       let idx = pitchers.firstIndex(where: { $0.id == pid }) {
                                        pitchers[idx] = updated
                                    }
                                    showAddPitcher = false
                                    editingPitcher = nil
                                }
                            } else {
                                let templateId = selectedTemplate?.id.uuidString
                                authManager.createPitcher(name: name, templateId: templateId) { created in
                                    if let created {
                                        pitchers.append(created)
                                    }
                                    showAddPitcher = false
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.35)])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $statsPitcher) { pitcher in
                PitcherStatsSheetView(
                    pitcher: pitcher,
                    games: games
                )
                .environmentObject(authManager)
            }
            .sheet(isPresented: $showGameChooser) {
                GameSelectionSheet(
                    onCreate: { name, date in
                        let newGame = Game(id: nil, opponent: name, date: date, jerseyNumbers: [])
                        authManager.saveGame(newGame)
                    },
                    onChoose: { gameId in
                        let ownerUid = authManager.user?.uid ?? ""
                        NotificationCenter.default.post(
                            name: .gameOrSessionChosen,
                            object: nil,
                            userInfo: [
                                "type": "game",
                                "gameId": gameId,
                                "ownerUserId": ownerUid
                            ]
                        )
                        dismiss()
                    },
                    onCancel: {
                        showGameChooser = false
                    },
                    codeShareInitialTab: $codeShareInitialTab,
                    showCodeShareSheet: $showCodeShareSheet,
                    shareCode: $shareCode,
                    codeShareSheetID: $codeShareSheetID,
                    showCodeShareModePicker: $showCodeShareModePicker,
                    games: $games,
                )
            }
            .sheet(isPresented: $showPracticeChooser) {
                PracticeSelectionSheet(
                    onCreate: { name, date, templateId, templateName in
                        var sessions = loadPracticeSessions()
                        let new = PracticeSession(
                            id: UUID().uuidString,
                            name: name,
                            date: date,
                            templateId: templateId,
                            templateName: templateName
                        )
                        sessions.append(new)
                        savePracticeSessions(sessions)
                    },
                    onChoose: { practiceId in
                        if practiceId == "__GENERAL__" {
                            launchPractice(nil)
                            return
                        }
                        let sessions = loadPracticeSessions()
                        if let session = sessions.first(where: { $0.id == practiceId }) {
                            launchPractice(session)
                        }
                    },
                    onCancel: {
                        showPracticeChooser = false
                    },
                    currentTemplateId: selectedTemplate?.id.uuidString,
                    currentTemplateName: selectedTemplate?.name,
                    encryptedSelectionByPracticeId: $encryptedSelectionByPracticeId
                )
            }
        }
    }
}

struct PitcherStatsSheetView: View {
    enum DateRangeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case last7 = "Last 7"
        case last30 = "Last 30"
        case last90 = "Last 90"
        case custom = "Custom"

        var id: String { rawValue }
    }

    enum StatScope: String, CaseIterable, Identifiable {
        case games = "Games"
        case practice = "Practice"

        var id: String { rawValue }
    }


    enum SummaryDetail: String, Identifiable {
        case swingK = "Swing K"
        case lookK = "Look ꓘ"
        case hitSpot = "Hit-Spot %"

        var id: String { rawValue }
    }

    let pitcher: Pitcher
    let games: [Game]
    let lockToGameId: String?
    let liveId: String?

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    init(pitcher: Pitcher, games: [Game], lockToGameId: String? = nil, liveId: String? = nil) {
        self.pitcher = pitcher
        self.games = games
        self.lockToGameId = lockToGameId
        self.liveId = liveId
    }

    @State private var dateFilter: DateRangeFilter = .all
    @State private var scope: StatScope = .games

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    @State private var selectedGameIds: Set<String> = []
    @State private var selectedPracticeIds: Set<String> = []
    @State private var cachedGameIdsWithEvents: Set<String> = []

    @State private var practiceEvents: [PitchEvent] = []
    @State private var gameEvents: [PitchEvent] = []
    @State private var liveEvents: [PitchEvent] = []
    @State private var sharedGameEvents: [PitchEvent] = []
    @State private var sharedPracticeEvents: [PitchEvent] = []
    @State private var liveEventsListener: ListenerRegistration? = nil
    @State private var sharedPitcherEventsListener: ListenerRegistration? = nil
    @State private var cachedStats: PitcherStatsDoc? = nil
    @State private var isLoading = false
    @State private var hasLoadedEvents = false
    @State private var loadEventsToken = UUID()
    @State private var summaryDetail: SummaryDetail? = nil
    @State private var showGameSummarySheet = false

    private var sortedGames: [Game] {
        games.sorted { $0.date > $1.date }
    }

    private var practiceSessions: [PracticeSession] {
        guard let data = UserDefaults.standard.data(forKey: "storedPracticeSessions"),
              let sessions = try? JSONDecoder().decode([PracticeSession].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.date > $1.date }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private var gamesWithPitcherEvents: [Game] {
        let gameIdsWithEvents: Set<String> = {
            if !cachedGameIdsWithEvents.isEmpty {
                return cachedGameIdsWithEvents
            }
            return Set(combinedGameEvents.compactMap { $0.gameId })
        }()
        return sortedGames.filter { game in
            guard let id = game.id else { return false }
            return gameIdsWithEvents.contains(id)
        }
    }

    private var allGameIds: Set<String> {
        Set(gamesWithPitcherEvents.compactMap { $0.id })
    }

    private var allPracticeIds: Set<String> {
        Set(practiceSessions.compactMap { $0.id } + ["__GENERAL__"])
    }

    private var validGameIds: Set<String> {
        Set(sortedGames.compactMap { $0.id })
    }

    private var validPracticeIds: Set<String> {
        Set(practiceSessions.compactMap { $0.id })
    }

    private func formattedDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private var scopeSelectionLabel: String {
        switch scope {
        case .games:
            if selectedGameIds.count == 1,
               let id = selectedGameIds.first,
               let game = sortedGames.first(where: { $0.id == id }) {
                return "vs \(game.opponent) • \(formattedDate(game.date))"
            }
            if selectedGameIds.isEmpty || selectedGameIds == allGameIds {
                return "All Games"
            }
            return "Multiple Games"
        case .practice:
            if selectedPracticeIds == ["__GENERAL__"] {
                return "General"
            }
            if selectedPracticeIds.count == 1,
               let id = selectedPracticeIds.first,
               let session = practiceSessions.first(where: { $0.id == id }) {
                return "\(session.name) • \(formattedDate(session.date))"
            }
            if selectedPracticeIds.isEmpty || selectedPracticeIds == allPracticeIds {
                return "All Practices"
            }
            return "Multiple Practices"
        }
    }

    private var dateRange: ClosedRange<Date>? {
        switch dateFilter {
        case .all:
            return nil
        case .last7:
            return (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())...Date()
        case .last30:
            return (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())...Date()
        case .last90:
            return (Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())...Date()
        case .custom:
            return min(startDate, endDate)...max(startDate, endDate)
        }
    }

    private var filteredEvents: [PitchEvent] {
        if let lockedGameId = lockToGameId {
            let lockedEvents = combinedGameEvents.filter { event in
                if let gid = event.gameId, !gid.isEmpty { return gid == lockedGameId }
                return liveId != nil
            }
            guard let range = dateRange else { return lockedEvents }
            return lockedEvents.filter { range.contains($0.timestamp) }
        }

        let allForPitcher: [PitchEvent] = {
            switch scope {
            case .practice:
                return combinedPracticeEvents
            case .games:
                return combinedGameEvents
            }
        }()

        let byScopeSelection: [PitchEvent] = {
            switch scope {
            case .practice:
                if selectedPracticeIds.isEmpty { return allForPitcher }
                return allForPitcher.filter { event in
                    let pid = event.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalized = (pid == nil || pid == "") ? "__GENERAL__" : pid!
                    return selectedPracticeIds.contains(normalized)
                }
            case .games:
                let effectiveGameIds = selectedGameIds.isEmpty ? allGameIds : selectedGameIds
                if effectiveGameIds.isEmpty { return [] }
                return allForPitcher.filter { event in
                    if let gid = event.gameId { return effectiveGameIds.contains(gid) }
                    return false
                }
            }
        }()

        let byDate: [PitchEvent] = {
            guard let range = dateRange else { return byScopeSelection }
            return byScopeSelection.filter { range.contains($0.timestamp) }
        }()

        return byDate
    }

    private enum ResultType {
        case strike, ball
    }

    private func resultType(for event: PitchEvent) -> ResultType? {
        let raw = event.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("strike ") { return .strike }
        if raw.hasPrefix("ball ") { return .ball }
        return nil
    }

    private var activeStats: PitcherStatsDoc? {
        // Use cached aggregates only before events have loaded for this sheet session.
        // After loading completes, always render from filteredEvents so date/scope filters
        // immediately reflect user changes (including zero-result ranges).
        hasLoadedEvents ? nil : cachedStats
    }

    private var strikeCount: Int {
        activeStats?.strikeCount ?? filteredEvents.filter { resultType(for: $0) == .strike }.count
    }

    private var totalCount: Int {
        activeStats?.totalCount ?? filteredEvents.count
    }

    private var strikePercent: Int {
        totalCount == 0 ? 0 : Int(Double(strikeCount) / Double(totalCount) * 100)
    }

    private var ballCount: Int {
        activeStats?.ballCount ?? filteredEvents.filter { resultType(for: $0) == .ball }.count
    }

    private var ballPercent: Int {
        totalCount == 0 ? 0 : Int(Double(ballCount) / Double(totalCount) * 100)
    }

    private var swingingStrikeCount: Int {
        activeStats?.swingingStrikeCount ?? filteredEvents.filter { $0.strikeSwinging && $0.outcome == "K" }.count
    }

    private var lookingStrikeCount: Int {
        activeStats?.lookingStrikeCount ?? filteredEvents.filter { $0.strikeLooking && $0.outcome == "ꓘ" }.count
    }

    private var swingingStrikeEvents: [PitchEvent] {
        filteredEvents.filter { $0.strikeSwinging && $0.outcome == "K" }
    }

    private var lookingStrikeEvents: [PitchEvent] {
        filteredEvents.filter { $0.strikeLooking && $0.outcome == "ꓘ" }
    }

    private var wildPitchCount: Int {
        activeStats?.wildPitchCount ?? filteredEvents.filter { $0.wildPitch }.count
    }

    private var passedBallCount: Int {
        activeStats?.passedBallCount ?? filteredEvents.filter { $0.passedBall }.count
    }

    private var walkCount: Int {
        activeStats?.walkCount ?? filteredEvents.filter {
            guard let outcome = $0.outcome, !outcome.isEmpty else { return false }
            return outcome == "BB" || outcome == "Walk"
        }.count
    }

    private var hitSpotCount: Int {
        activeStats?.hitSpotCount ?? filteredEvents.filter { strictIsLocationMatch($0) }.count
    }

    private var hitSpotEvents: [PitchEvent] {
        filteredEvents.filter { strictIsLocationMatch($0) }
    }

    private var hitSpotPercent: Int {
        totalCount == 0 ? 0 : Int(Double(hitSpotCount) / Double(totalCount) * 100)
    }

    private var outcomesSummary: [(label: String, count: Int, jerseys: String)] {
        if let stats = activeStats {
            return stats.outcomeStats.map { key, value in
                let jerseys = value.jerseys.sorted().joined(separator: ", ")
                return (label: key, count: value.count, jerseys: jerseys)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
        }

        var counts: [String: Int] = [:]
        var jerseysByOutcome: [String: Set<String>] = [:]
        for event in filteredEvents {
            if let outcome = event.outcome, !outcome.isEmpty {
                counts[outcome, default: 0] += 1
                if let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
                    jerseysByOutcome[outcome, default: []].insert(jersey)
                }
            }
        }
        return counts.map { key, value in
            let jerseys = jerseysByOutcome[key, default: []].sorted().joined(separator: ", ")
            return (label: key, count: value, jerseys: jerseys)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private var selectedSingleGameIdForSummary: String? {
        if let locked = lockToGameId, !locked.isEmpty { return locked }
        guard scope == .games, selectedGameIds.count == 1 else { return nil }
        return selectedGameIds.first
    }

    private var selectedSingleGameForSummary: Game? {
        guard let gameId = selectedSingleGameIdForSummary else { return nil }
        return games.first(where: { $0.id == gameId })
    }

    private var selectedGameSummaryEvents: [PitchEvent] {
        guard let gameId = selectedSingleGameIdForSummary else { return [] }
        return combinedGameEvents
            .filter { ($0.gameId ?? "") == gameId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var pitchStats: [(name: String, count: Int, hitSpotPct: Int)] {
        if let stats = activeStats {
            let rows = stats.pitchStats.map { key, value in
                let total = value.count
                let hitSpotPct = total == 0 ? 0 : Int(Double(value.hitSpotCount) / Double(total) * 100)
                return (key, total, hitSpotPct)
            }
            return rows.sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
        }

        let grouped = Dictionary(grouping: filteredEvents, by: { $0.pitch })
        var rows: [(String, Int, Int)] = []
        for (pitch, events) in grouped {
            let total = events.count
            let hitSpots = events.filter { strictIsLocationMatch($0) }.count
            let hitSpotPct = total == 0 ? 0 : Int(Double(hitSpots) / Double(total) * 100)
            rows.append((pitch, total, hitSpotPct))
        }
        return rows.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }

    private func summaryDetailRows(
        for events: [PitchEvent],
        includeJerseyNumbers: Bool
    ) -> [(pitch: String, location: String, count: Int, jerseys: String)] {
        var counts: [String: Int] = [:]
        var jerseysByKey: [String: Set<String>] = [:]
        for event in events {
            let pitch = event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let safePitch = pitch.isEmpty ? "Unknown Pitch" : pitch
            let safeLocation = location.isEmpty ? "Unknown Location" : location
            let key = "\(safePitch)|\(safeLocation)"
            counts[key, default: 0] += 1
            if includeJerseyNumbers, let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
                jerseysByKey[key, default: []].insert(jersey)
            }
        }

        return counts.map { key, count in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let pitch = parts.first ?? "Unknown Pitch"
            let location = parts.count > 1 ? parts[1] : "Unknown Location"
            let jerseys = jerseysByKey[key, default: []].sorted().joined(separator: ", ")
            return (pitch, location, count, jerseys)
        }
        .sorted { lhs, rhs in
            if lhs.pitch == rhs.pitch { return lhs.location < rhs.location }
            return lhs.pitch < rhs.pitch
        }
    }

    private func hitSpotDetailRows() -> [(pitch: String, location: String, intended: String, count: Int, jerseys: String)] {
        // Hit-Spot detail should list each pitch in sequence.
        var seenEventKeys: Set<String> = []

        let dedupedEvents: [PitchEvent] = filteredEvents.filter { event in
            let key: String
            if let id = event.id, !id.isEmpty {
                key = "id:\(id)"
            } else {
                let calledPitch = event.calledPitch?.pitch ?? ""
                let calledLocation = event.calledPitch?.location ?? ""
                key = [
                    String(event.timestamp.timeIntervalSince1970),
                    event.pitch,
                    event.location,
                    calledPitch,
                    calledLocation,
                    event.pitcherId ?? "",
                    event.gameId ?? "",
                    event.practiceId ?? ""
                ].joined(separator: "|")
            }

            guard !seenEventKeys.contains(key) else { return false }
            seenEventKeys.insert(key)
            return true
        }
        .sorted { $0.timestamp < $1.timestamp }

        return dedupedEvents.enumerated().map { index, event in
            let pitch = event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let intendedLocation = event.calledPitch?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let safePitch = pitch.isEmpty ? "Unknown Pitch" : pitch
            let safeResult = resultLocation.isEmpty ? "Unknown Location" : resultLocation
            let safeIntended = intendedLocation.isEmpty ? "Unknown Intended" : intendedLocation
            let resultPrefix = strictIsLocationMatch(event) ? "Hit: " : "Miss: "
            return (
                pitch: safePitch,
                location: "\(resultPrefix)\(safeResult)",
                intended: safeIntended,
                count: index + 1,
                jerseys: ""
            )
        }
    }

    private func hitSpotRowColor(forLocation location: String) -> Color {
        if location.lowercased().hasPrefix("hit:") { return .green }
        if location.lowercased().hasPrefix("miss:") { return .red }
        return .secondary
    }

    private var summaryDetailContent: some View {
        let detail = summaryDetail
        let events: [PitchEvent]
        switch detail {
        case .swingK:
            events = swingingStrikeEvents
        case .lookK:
            events = lookingStrikeEvents
        case .hitSpot:
            events = []
        case .none:
            events = []
        }

        let includeJerseyNumbers = detail == .swingK || detail == .lookK
        let includeIntended = detail == .hitSpot
        let rows: [(id: String, pitch: String, location: String, intended: String?, count: Int, jerseys: String)] = {
            if detail == .hitSpot {
                return hitSpotDetailRows().map { row in
                    (
                        id: "\(row.pitch)|\(row.location)|\(row.intended)",
                        pitch: row.pitch,
                        location: row.location,
                        intended: row.intended,
                        count: row.count,
                        jerseys: row.jerseys
                    )
                }
            }
            return summaryDetailRows(for: events, includeJerseyNumbers: includeJerseyNumbers).map { row in
                (
                    id: "\(row.pitch)|\(row.location)|\(row.jerseys)",
                    pitch: row.pitch,
                    location: row.location,
                    intended: nil,
                    count: row.count,
                    jerseys: row.jerseys
                )
            }
        }()
        let rowWidth: CGFloat = includeJerseyNumbers ? 400 : (includeIntended ? 430 : 300)

        return VStack(alignment: .leading, spacing: 12) {
            Text(detail?.rawValue ?? "Details")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)
            Divider()
            if rows.isEmpty {
                Text("No pitches recorded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("#")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text("Pitch")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Text("Location")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: includeIntended ? 130 : 150, alignment: .leading)
                            if includeIntended {
                                Text("Intended")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 130, alignment: .leading)
                            }
                            if includeJerseyNumbers {
                                Text("Batters")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90, alignment: .leading)
                            }
                        }
                        .frame(width: rowWidth, alignment: .center)
                        ForEach(rows, id: \.id) { row in
                            HStack(spacing: 8) {
                                Text("\(row.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .leading)
                                Text(row.pitch)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 90, alignment: .leading)
                                Text(row.location)
                                    .font(.subheadline)
                                    .foregroundColor(hitSpotRowColor(forLocation: row.location))
                                    .frame(width: includeIntended ? 130 : 150, alignment: .leading)
                                if includeIntended {
                                    Text((row.intended ?? "").isEmpty ? "—" : (row.intended ?? "—"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 130, alignment: .leading)
                                }
                                if includeJerseyNumbers {
                                    Text(row.jerseys.isEmpty ? "—" : row.jerseys)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                }
                            }
                            .frame(width: rowWidth, alignment: .center)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 12)
        .padding()
        .presentationDetents([.medium, .large])
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lockToGameId == nil {
                        HStack(alignment: .center, spacing: 12) {
                            Text(pitcher.name)
                                .font(.title2.weight(.semibold))

                            Spacer(minLength: 8)
                            VStack(spacing: 8) {
                                Picker("Scope", selection: $scope) {
                                    ForEach(StatScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                            .fixedSize()

                                scopeSelectionMenu
                            }
                        }
                        .padding(.horizontal)

                        if scope == .games {
                            HStack {
                                Spacer()
                                Button {
                                    showGameSummarySheet = true
                                } label: {
                                    Label("Game Summary", systemImage: "doc.text")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedSingleGameIdForSummary == nil)
                                Spacer()
                            }
                            .padding(.horizontal)

                            if selectedSingleGameIdForSummary == nil {
                                Text("Select one game to open the game summary.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal)
                            }
                        }

                        summarySection
                        statsPickerSection
                    } else {
                        HStack(spacing: 0) {
                            Spacer(minLength: 12)

                            HStack(alignment: .center, spacing: 12) {
                                Text(pitcher.name)
                                    .font(.title2.weight(.semibold))
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Game")
                                        .font(.headline)
                                    if let lockedGameId = lockToGameId,
                                       let game = games.first(where: { $0.id == lockedGameId }) {
                                        Text("vs. \(game.opponent)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Selected game")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )

                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal)

                        summarySection
                    }
                    pitchBreakdownSection
                    outcomesSection
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Pitcher Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $summaryDetail) { _ in
                summaryDetailContent
            }
            .sheet(isPresented: $showGameSummarySheet) {
                if let game = selectedSingleGameForSummary {
                    SettingsGameSummarySheetView(
                        pitcherName: pitcher.name,
                        game: game,
                        events: selectedGameSummaryEvents
                    )
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Select one game to view a game summary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.fraction(0.3)])
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .onAppear {
                initializeSelections()
                loadEvents()
                loadCachedStats()
                startLiveListener()
                startSharedPitcherListener()
            }
            .onDisappear {
                stopLiveListener()
                stopSharedPitcherListener()
            }
            .onChange(of: selectedGameIds) { _, _ in
                loadEvents()
                loadCachedStats()
            }
            .onChange(of: selectedPracticeIds) { _, _ in
                loadEvents()
                loadCachedStats()
            }
            .onChange(of: scope) { _, _ in
                if lockToGameId != nil {
                    scope = .games
                }
                loadEvents()
                loadCachedStats()
            }
            .onChange(of: liveId) { _, _ in
                startLiveListener()
            }
            .onChange(of: pitcher.id) { _, _ in
                cachedGameIdsWithEvents = []
                startSharedPitcherListener()
                loadCachedStats()
            }
        }
    }

    private var statsPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Date Range", selection: $dateFilter) {
                ForEach(DateRangeFilter.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if dateFilter == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                .padding(.horizontal)
            }
        }
    }

    private var scopeSelectionMenu: some View {
        Menu {
            switch scope {
            case .games:
                Button("All Games") {
                    selectedGameIds = allGameIds
                }
                ForEach(gamesWithPitcherEvents, id: \.id) { game in
                    let title = "vs \(game.opponent) • \(formattedDate(game.date))"
                    Button(title) {
                        if let id = game.id {
                            selectedGameIds = [id]
                        }
                    }
                }
            case .practice:
                Button("All Practices") {
                    selectedPracticeIds = allPracticeIds
                }
                Button("General") {
                    selectedPracticeIds = ["__GENERAL__"]
                }
                ForEach(practiceSessions, id: \.id) { session in
                    let title = "\(session.name) • \(formattedDate(session.date))"
                    Button(title) {
                        if let id = session.id {
                            selectedPracticeIds = [id]
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(scopeSelectionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
                .padding(.horizontal)

            Picker("Scope", selection: $scope) {
                ForEach(StatScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if scope == .games {
                gameFilterList
            } else if scope == .practice {
                practiceFilterList
            }
        }
    }

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
                .padding(.horizontal)

            Picker("Date Range", selection: $dateFilter) {
                ForEach(DateRangeFilter.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if dateFilter == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                .padding(.horizontal)
            }
        }
    }

    private var lockedGameHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game")
                .font(.headline)
                .padding(.horizontal)
            if let lockedGameId = lockToGameId,
               let game = games.first(where: { $0.id == lockedGameId }) {
                Text("vs. \(game.opponent)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                Text("Selected game")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

        }
    }

    private var gameFilterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Games")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("All") {
                    selectedGameIds = Set(sortedGames.compactMap { $0.id })
                }
                .font(.caption)
                Button("Clear") {
                    selectedGameIds.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedGames) { game in
                        let gid = game.id ?? ""
                        let isSelected = selectedGameIds.contains(gid)
                        Button("\(game.opponent)") {
                            guard !gid.isEmpty else { return }
                            if isSelected {
                                selectedGameIds.remove(gid)
                            } else {
                                selectedGameIds.insert(gid)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? Color.black.opacity(0.14) : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(Color.black, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var practiceFilterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Practice")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("All") {
                    let ids = practiceSessions.compactMap { $0.id } + ["__GENERAL__"]
                    selectedPracticeIds = Set(ids)
                }
                .font(.caption)
                Button("Clear") {
                    selectedPracticeIds.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("General") {
                        if selectedPracticeIds.contains("__GENERAL__") {
                            selectedPracticeIds.remove("__GENERAL__")
                        } else {
                            selectedPracticeIds.insert("__GENERAL__")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(selectedPracticeIds.contains("__GENERAL__") ? Color.black.opacity(0.14) : Color.clear)
                    )
                    .overlay(
                        Capsule().stroke(Color.black, lineWidth: 1)
                    )

                    ForEach(practiceSessions, id: \.id) { session in
                        Group {
                            if let pid = session.id {
                                let isSelected = selectedPracticeIds.contains(pid)
                                Button(session.name) {
                                    if isSelected {
                                        selectedPracticeIds.remove(pid)
                                    } else {
                                        selectedPracticeIds.insert(pid)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(isSelected ? Color.black.opacity(0.14) : Color.clear)
                                )
                                .overlay(
                                    Capsule().stroke(Color.black, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Total", value: "\(totalCount)")
                statCard(title: "Strike %", value: "\(strikePercent)%")
                statCard(title: "Ball %", value: "\(ballPercent)%")
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    summaryDetail = .swingK
                } label: {
                    statCard(title: "Swing K", value: "\(swingingStrikeCount)")
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    summaryDetail = .lookK
                } label: {
                    statCard(title: "Look ꓘ", value: "\(lookingStrikeCount)")
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    summaryDetail = .hitSpot
                } label: {
                    statCard(title: "Hit-Spot %", value: "\(hitSpotPercent)%")
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Walks", value: "\(walkCount)")
                statCard(title: "Wild", value: "\(wildPitchCount)")
                statCard(title: "Passed", value: "\(passedBallCount)")
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Strikes", value: "\(strikeCount)")
                statCard(title: "Balls", value: "\(ballCount)")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes (\(strikeCount)) / Total Pitches (\(totalCount))")
                Text("Ball % = Balls (\(ballCount)) / Total Pitches (\(totalCount))")
                Text("Hit-Spot % = Location matches (\(hitSpotCount)) / Total Pitches (\(totalCount))")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        }
    }

    private var pitchBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pitch Type Breakdown")
                .font(.headline)
                .padding(.horizontal)

            if pitchStats.isEmpty {
                Text("No pitch data yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Type")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text("Count")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Text("Hit %")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }

                    ForEach(Array(pitchStats.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 54, alignment: .leading)
                            Text("\(row.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Text("\(row.hitSpotPct)%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal)

            Text("Outcomes")
                .font(.headline)
                .padding(.horizontal)

            if outcomesSummary.isEmpty {
                Text("No outcomes recorded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Type")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text("#")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)
                        Text("Jersey")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                    }

                    ForEach(outcomesSummary, id: \.label) { item in
                        HStack(spacing: 4) {
                            Text(item.label)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 70, alignment: .trailing)
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text(item.jerseys.isEmpty ? "—" : item.jerseys)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 110, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private func initializeSelections() {
        if let lockedGameId = lockToGameId {
            scope = .games
            selectedGameIds = [lockedGameId]
            selectedPracticeIds = []
            return
        }

        cachedGameIdsWithEvents = []

        let ids = sortedGames.compactMap { $0.id }
        selectedGameIds = Set(ids)

        // Treat empty selection as "All Practices" so historical practice events
        // are not excluded when session IDs are missing/stale in local metadata.
        selectedPracticeIds = []
    }

    private func loadEvents() {
        guard let pitcherId = pitcher.id else { return }
        let requestToken = UUID()
        loadEventsToken = requestToken

        isLoading = true
        hasLoadedEvents = false
        practiceEvents = []
        gameEvents = []
        liveEvents = []
        sharedGameEvents = []
        sharedPracticeEvents = []

        authManager.loadPitcherEvents(pitcherId: pitcherId) { events in
            guard loadEventsToken == requestToken else { return }

            var sharedGameBucket: [PitchEvent] = []
            var sharedPracticeBucket: [PitchEvent] = []
            var seenIdentities = Set<String>()

            if !events.isEmpty {
                for event in events {
                    if event.mode == .game || (event.gameId?.isEmpty == false) {
                        sharedGameBucket.append(event)
                    } else {
                        sharedPracticeBucket.append(event)
                    }
                }
                seenIdentities = Set((sharedGameBucket + sharedPracticeBucket).map { $0.identity })

                DispatchQueue.main.async {
                    self.gameEvents = sharedGameBucket
                    self.practiceEvents = sharedPracticeBucket
                }
            }

            guard let ownerUid = authManager.user?.uid else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.hasLoadedEvents = true
                }
                return
            }

            let group = DispatchGroup()

            group.enter()
            authManager.loadPitchEvents { events in
                guard loadEventsToken == requestToken else { group.leave(); return }
                let filtered = events.filter { $0.pitcherId == pitcherId }
                DispatchQueue.main.async {
                    let unique = filtered.filter { !seenIdentities.contains($0.identity) }
                    seenIdentities.formUnion(unique.map { $0.identity })
                    self.practiceEvents.append(contentsOf: unique)
                    group.leave()
                }
            }

            let gameIdsToLoad: [String] = {
                if let lockedGameId = lockToGameId { return [lockedGameId] }
                switch scope {
                case .practice:
                    return []
                case .games:
                    return selectedGameIds.isEmpty ? sortedGames.compactMap { $0.id } : Array(selectedGameIds)
                }
            }()

            for gameId in gameIdsToLoad {
                group.enter()
                authManager.loadGamePitchEvents(ownerUserId: ownerUid, gameId: gameId) { events in
                    guard loadEventsToken == requestToken else { group.leave(); return }
                    let filtered = events.filter { $0.pitcherId == pitcherId }
                    DispatchQueue.main.async {
                        let unique = filtered.filter { !seenIdentities.contains($0.identity) }
                        seenIdentities.formUnion(unique.map { $0.identity })
                        self.gameEvents.append(contentsOf: unique)
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                guard loadEventsToken == requestToken else { return }
                let ids = Set(self.combinedGameEvents.compactMap { $0.gameId })
                if !ids.isEmpty {
                    self.cachedGameIdsWithEvents.formUnion(ids)
                }
                self.isLoading = false
                self.hasLoadedEvents = true
            }
        }
    }

    private var combinedGameEvents: [PitchEvent] {
        mergeUnique([gameEvents, liveEvents, sharedGameEvents]).filter { event in
            if let gid = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines), !gid.isEmpty {
                return validGameIds.contains(gid)
            }
            return lockToGameId != nil && liveId != nil
        }
    }

    private var combinedPracticeEvents: [PitchEvent] {
        mergeUnique([practiceEvents, sharedPracticeEvents]).filter { event in
            let pid = event.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if pid == nil || pid == "" {
                return true
            }
            return validPracticeIds.contains(pid!)
        }
    }

    private func statsScopeKey() -> (scope: String, scopeId: String)? {
        if let lockedGameId = lockToGameId {
            return ("game", lockedGameId)
        }

        switch scope {
        case .games:
            if selectedGameIds.count == 1, let gid = selectedGameIds.first {
                return ("game", gid)
            }
        case .practice:
            if selectedPracticeIds.count == 1, let pid = selectedPracticeIds.first {
                let normalized = pid.trimmingCharacters(in: .whitespacesAndNewlines)
                return ("practice", normalized.isEmpty ? "__GENERAL__" : normalized)
            }
        }

        return nil
    }

    private func loadCachedStats() {
        cachedStats = nil
        guard let pitcherId = pitcher.id else { return }
        guard let key = statsScopeKey() else { return }

        let docId: String = {
            switch key.scope {
            case "overall":
                return "overall"
            case "game":
                return "game_\(key.scopeId)"
            case "practice":
                return "practice_\(key.scopeId)"
            default:
                return "overall"
            }
        }()

        let ref = Firestore.firestore()
            .collection("pitchers").document(pitcherId)
            .collection("stats").document(docId)

        ref.getDocument { snap, error in
            if let error {
                print("❌ loadCachedStats error:", error.localizedDescription)
                return
            }
            guard let snap, snap.exists else { return }
            Task { @MainActor in
                do {
                    let doc = try snap.data(as: PitcherStatsDoc.self)
                    self.cachedStats = doc
                } catch {
                    print("❌ decode cached stats failed:", error.localizedDescription)
                }
            }
        }
    }

    private func startLiveListener() {
        stopLiveListener()
        liveEvents = []
        guard let liveId, !liveId.isEmpty, let pitcherId = pitcher.id else { return }

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        liveEventsListener = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ live stats pitchEvents listener error:", error.localizedDescription)
                return
            }

            let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            } ?? []

            let filtered = events.filter { $0.pitcherId == pitcherId }
            DispatchQueue.main.async {
                self.liveEvents = filtered
            }
        }
    }

    private func stopLiveListener() {
        liveEventsListener?.remove()
        liveEventsListener = nil
    }

    private func startSharedPitcherListener() {
        stopSharedPitcherListener()
        sharedGameEvents = []
        sharedPracticeEvents = []

        guard let pitcherId = pitcher.id else { return }

        let ref = Firestore.firestore()
            .collection("pitchers").document(pitcherId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        sharedPitcherEventsListener = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ shared pitcherEvents listener error:", error.localizedDescription)
                return
            }

            let docs = snapshot?.documents ?? []
            print("🧾 shared pitcherEvents snapshot count=\(docs.count) pitcherId=\(pitcherId)")

            let events: [PitchEvent] = docs.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            }

            let sharedGame = events.filter { $0.mode == .game || ($0.gameId?.isEmpty == false) }
            let sharedPractice = events.filter { !($0.mode == .game || ($0.gameId?.isEmpty == false)) }

            if let sample = events.last {
                print("🧾 shared pitcherEvents sample gameId=\(sample.gameId ?? "<nil>") mode=\(sample.mode.rawValue) pitcherId=\(sample.pitcherId ?? "<nil>") location=\(sample.location)")
            }

            DispatchQueue.main.async {
                self.sharedGameEvents = sharedGame
                self.sharedPracticeEvents = sharedPractice
            }
        }
    }

    private func stopSharedPitcherListener() {
        sharedPitcherEventsListener?.remove()
        sharedPitcherEventsListener = nil
    }

    private func mergeUnique(_ groups: [[PitchEvent]]) -> [PitchEvent] {
        var seen = Set<String>()
        var merged: [PitchEvent] = []
        for group in groups {
            for event in group {
                let key = logicalEventKey(for: event)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                merged.append(event)
            }
        }
        return merged
    }

    // Use a logical key so mirrored copies of the same pitch event (different Firestore doc IDs)
    // are counted once in stats sheets.
    private func logicalEventKey(for event: PitchEvent) -> String {
        let ts = String(format: "%.6f", event.timestamp.timeIntervalSince1970)
        let mode = event.mode.rawValue
        let gameId = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let practiceId = event.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let batterId = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calledPitch = event.calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calledLocation = event.calledPitch?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            ts,
            mode,
            event.pitch,
            event.location,
            calledPitch,
            calledLocation,
            gameId,
            practiceId,
            pitcherId,
            batterId,
            jersey
        ].joined(separator: "|")
    }
}

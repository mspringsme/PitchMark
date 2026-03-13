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

struct PitcherPitchStats: Codable {
    var count: Int
    var hitSpotCount: Int
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
    @State private var showSignOutConfirmation = false
    @State private var templatePendingDeletion: PitchTemplate?
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var templatePendingLaunch: PitchTemplate? = nil
    @State private var showModeChoice = false
    @State private var showGameChooser = false
    @State private var showPracticeChooser = false
    @State private var editorTemplate: PitchTemplate? = nil
    @State private var showAddPitcher = false
    @State private var newPitcherName: String = ""
    @State private var newPitcherTemplateId: String? = nil
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
    @State private var isJoiningInvite = false

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
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var templatesHeader: some View {
        HStack {
            Text("Templates")
                .font(.title2)
                .bold()
                .padding(.horizontal)
            Spacer()
            Button(isRefreshingTemplates ? "Refreshing..." : "Refresh") {
                guard !isRefreshingTemplates else { return }
                isRefreshingTemplates = true
                authManager.loadTemplates { loaded in
                    templates = loaded
                    if selectedTemplate == nil {
                        selectedTemplate = loaded.first
                    }
                    isRefreshingTemplates = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshingTemplates)
            Button("New Template") {
                editorTemplate = PitchTemplate(
                    id: UUID(),
                    name: "",
                    pitches: [],
                    codeAssignments: []
                )
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var pitchersHeader: some View {
        HStack {
            Text("Pitchers")
                .font(.title2)
                .bold()
                .padding(.horizontal)
            Spacer()
            Button("New Pitcher") {
                editingPitcher = nil
                newPitcherName = ""
                newPitcherTemplateId = selectedTemplate?.id.uuidString
                showAddPitcher = true
            }
            .padding(.horizontal)
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
                            newPitcherTemplateId = pitcher.templateId
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
                } else {
                    Text("Select a pitcher to manage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                        .padding(.trailing, 4)
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
                        Button("Launch") {
                            templatePendingLaunch = template
                            showModeChoice = true
                        }
                        .buttonStyle(.borderedProminent)

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
                    }
                    .padding(.horizontal)
                } else {
                    Text("Select a template to manage")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            Text("Store")
                .font(.title2)
                .bold()
                .padding(.horizontal)

            NavigationLink {
                Storefront
            } label: {
                HStack {
                    Image(systemName: "cart")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Template Inserts")
                            .font(.headline)
                        Text("Buy wristband card inserts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.title2)
                .bold()
                .padding(.horizontal)

            NavigationLink("Profile") {
                Text("Coach profile settings go here")
                    .padding()
            }
            .padding(.horizontal)

            NavigationLink("Sign-In Options") {
                Text("Google / Firebase settings")
                    .padding()
            }
            .padding(.horizontal)

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
                    authManager.signOut()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0)
                        

                        // 🔹 Templates Header
                        templatesHeader

                        // 🔹 Templates List / Empty State
                        templatesListView

                        if showHiddenTemplates {
                            if !hiddenTemplates.isEmpty {
                                hiddenTemplatesSection
                            }
                        }

                        Divider()
                            .padding(.horizontal)

                        // 🔹 Pitchers Header
                        pitchersHeader

                        // 🔹 Pitchers List / Empty State
                        pitchersListView

                        if showHiddenPitchers {
                            if !hiddenPitchers.isEmpty {
                                hiddenPitchersSection
                            }
                        }

                        Divider()
                            .padding(.horizontal)
                        
                        storeSection
                        Divider()
                        
                        // 🔹 Account Section
                        accountSection
                    }
                    .padding(.top, 4)
                }
                .safeAreaInset(edge: .bottom) {
                    Text("Signed in as: \(authManager.userEmail)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showInviteJoinSheet) { inviteJoinSheetView }
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
            .confirmationDialog("Launch as…", isPresented: $showModeChoice, titleVisibility: .visible) {
                Button("Game") {
                    showGameChooser = true
                }
                Button("Practice") {
                    showPracticeChooser = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Join a Game") {
                        inviteJoinError = nil
                        inviteJoinText = ""
                        showInviteJoinSheet = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.darkGray))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
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

                    Picker("Template", selection: $newPitcherTemplateId) {
                        Text("No Template").tag(String?.none)
                        ForEach(templates, id: \.id) { template in
                            Text(template.name).tag(Optional(template.id.uuidString))
                        }
                    }
                    .pickerStyle(.menu)

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
                                authManager.updatePitcher(id: pid, name: name, templateId: newPitcherTemplateId) { updated in
                                    if let updated,
                                       let idx = pitchers.firstIndex(where: { $0.id == pid }) {
                                        pitchers[idx] = updated
                                    }
                                    showAddPitcher = false
                                    editingPitcher = nil
                                }
                            } else {
                                authManager.createPitcher(name: name, templateId: newPitcherTemplateId) { created in
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
                        if let tmpl = templatePendingLaunch {
                            selectedTemplate = tmpl
                            NotificationCenter.default.post(
                                name: .templateSelectionDidChange,
                                object: nil,
                                userInfo: [
                                    "templateId": tmpl.id.uuidString
                                ]
                            )

                            if let ownerUid = authManager.user?.uid {
                                authManager.updateGameTemplateName(
                                    ownerUserId: ownerUid,
                                    gameId: gameId,
                                    templateName: tmpl.name
                                )
                            }
                        }

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
                        encryptedSelectionByPracticeId[practiceId] = true
                        if practiceId == "__GENERAL__" {
                            selectedTemplate = nil
                            let defaults = UserDefaults.standard
                            defaults.set(true, forKey: PitchTrackerView.DefaultsKeys.activeIsPractice)
                            defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameId)
                            defaults.set("tracker", forKey: PitchTrackerView.DefaultsKeys.lastView)
                            return
                        }
                        let sessions = loadPracticeSessions()
                        if let session = sessions.first(where: { $0.id == practiceId }) {
                            selectedTemplate = templates.first(where: { $0.id.uuidString == session.templateId })
                            let defaults = UserDefaults.standard
                            defaults.set(true, forKey: PitchTrackerView.DefaultsKeys.activeIsPractice)
                            defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameId)
                            defaults.set("tracker", forKey: PitchTrackerView.DefaultsKeys.lastView)
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
        case all = "All"
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
    @State private var loadEventsToken = UUID()
    @State private var summaryDetail: SummaryDetail? = nil

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

    private func formattedDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private var scopeSelectionLabel: String {
        switch scope {
        case .all:
            return "All"
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
            case .all:
                return combinedPracticeEvents + combinedGameEvents
            case .practice:
                return combinedPracticeEvents
            case .games:
                return combinedGameEvents
            }
        }()

        let byScopeSelection: [PitchEvent] = {
            switch scope {
            case .all:
                return allForPitcher
            case .practice:
                if selectedPracticeIds.isEmpty { return allForPitcher }
                return allForPitcher.filter { event in
                    let pid = event.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalized = (pid == nil || pid == "") ? "__GENERAL__" : pid!
                    return selectedPracticeIds.contains(normalized)
                }
            case .games:
                if selectedGameIds.isEmpty { return allForPitcher }
                return allForPitcher.filter { event in
                    if let gid = event.gameId { return selectedGameIds.contains(gid) }
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
        cachedStats
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
            .sorted { $0.count > $1.count }
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
        .sorted { $0.count > $1.count }
    }

    private var pitchStats: [(name: String, count: Int, hitSpotPct: Int)] {
        if let stats = activeStats {
            let rows = stats.pitchStats.map { key, value in
                let total = value.count
                let hitSpotPct = total == 0 ? 0 : Int(Double(value.hitSpotCount) / Double(total) * 100)
                return (key, total, hitSpotPct)
            }
            return rows.sorted { $0.1 > $1.1 }
        }

        let grouped = Dictionary(grouping: filteredEvents, by: { $0.pitch })
        var rows: [(String, Int, Int)] = []
        for (pitch, events) in grouped {
            let total = events.count
            let hitSpots = events.filter { strictIsLocationMatch($0) }.count
            let hitSpotPct = total == 0 ? 0 : Int(Double(hitSpots) / Double(total) * 100)
            rows.append((pitch, total, hitSpotPct))
        }
        return rows.sorted { $0.1 > $1.1 }
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

    private func hitSpotDetailRows() -> [(pitch: String, location: String, count: Int, jerseys: String)] {
        if let stats = activeStats {
            let rows: [(pitch: String, location: String, count: Int, jerseys: String)] = stats.pitchLocationStats.flatMap { key, value in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                let pitch = parts.first ?? "Unknown Pitch"
                let location = parts.count > 1 ? parts[1] : "Unknown Location"
                let jerseys = value.jerseys.sorted().joined(separator: ", ")

                let hitRow = (pitch: pitch, location: "Hit: \(location)", count: value.hitCount, jerseys: jerseys)
                let missRow = (pitch: pitch, location: "Miss: \(location)", count: value.missCount, jerseys: jerseys)
                return [hitRow, missRow]
            }

            return rows.sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.pitch < rhs.pitch }
                return lhs.count > rhs.count
            }
        }

        var hitCounts: [String: Int] = [:]
        var missCounts: [String: Int] = [:]

        for event in filteredEvents {
            let pitch = event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let safePitch = pitch.isEmpty ? "Unknown Pitch" : pitch
            let safeLocation = location.isEmpty ? "Unknown Location" : location
            let key = "\(safePitch)|\(safeLocation)"

            if strictIsLocationMatch(event) {
                hitCounts[key, default: 0] += 1
            } else {
                missCounts[key, default: 0] += 1
            }
        }

        func rows(from counts: [String: Int], prefix: String) -> [(pitch: String, location: String, count: Int, jerseys: String)] {
            counts.map { key, count in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                let pitch = parts.first ?? "Unknown Pitch"
                let location = parts.count > 1 ? parts[1] : "Unknown Location"
                return (pitch, "\(prefix) \(location)", count, "")
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.pitch < rhs.pitch }
                return lhs.count > rhs.count
            }
        }

        let hits = rows(from: hitCounts, prefix: "Hit:")
        let misses = rows(from: missCounts, prefix: "Miss:")
        return hits + misses
    }

    private func hitSpotRowColor(_ row: (pitch: String, location: String, count: Int, jerseys: String)) -> Color {
        if row.location.lowercased().hasPrefix("hit:") { return .green }
        if row.location.lowercased().hasPrefix("miss:") { return .red }
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
        let rows: [(pitch: String, location: String, count: Int, jerseys: String)] = {
            if detail == .hitSpot {
                return hitSpotDetailRows()
            }
            return summaryDetailRows(for: events, includeJerseyNumbers: includeJerseyNumbers)
        }()
        let rowWidth: CGFloat = includeJerseyNumbers ? 400 : 300

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
                                .frame(width: 150, alignment: .leading)
                            if includeJerseyNumbers {
                                Text("Batters")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90, alignment: .leading)
                            }
                        }
                        .frame(width: rowWidth, alignment: .center)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
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
                                    .foregroundColor(hitSpotRowColor(row))
                                    .frame(width: 150, alignment: .leading)
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

                                if scope != .all {
                                    scopeSelectionMenu
                                }
                            }
                        }
                        .padding(.horizontal)

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
            case .all:
                EmptyView()
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

        let practiceIds = practiceSessions.compactMap { $0.id }
        if practiceIds.isEmpty {
            selectedPracticeIds = ["__GENERAL__"]
        } else {
            selectedPracticeIds = Set(practiceIds + ["__GENERAL__"])
        }
    }

    private func loadEvents() {
        guard let pitcherId = pitcher.id else { return }
        let requestToken = UUID()
        loadEventsToken = requestToken

        isLoading = true
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
                DispatchQueue.main.async { self.isLoading = false }
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
                case .all, .games:
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
            }
        }
    }

    private var combinedGameEvents: [PitchEvent] {
        mergeUnique([gameEvents, liveEvents, sharedGameEvents])
    }

    private var combinedPracticeEvents: [PitchEvent] {
        mergeUnique([practiceEvents, sharedPracticeEvents])
    }

    private func statsScopeKey() -> (scope: String, scopeId: String)? {
        if let lockedGameId = lockToGameId {
            return ("game", lockedGameId)
        }

        switch scope {
        case .all:
            return ("overall", "overall")
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
                let key = event.identity
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                merged.append(event)
            }
        }
        return merged
    }
}

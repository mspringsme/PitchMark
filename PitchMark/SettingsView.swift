//
//  SettingsView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//

import SwiftUI
import FirebaseAuth
import UIKit

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

    @State private var showInviteJoinSheet = false
    @State private var inviteJoinText: String = ""
    @State private var inviteJoinError: String? = nil
    @State private var isJoiningInvite = false

    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    @State private var encryptedSelectionByPracticeId: [String: Bool] = [:]
    
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

                HStack {
                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            inviteJoinText = pasted
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            if let error = inviteJoinError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    inviteJoinError = nil
                    showInviteJoinSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(isJoiningInvite ? "Joining..." : "Join") {
                    joinLiveGameFromInvite()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteJoinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningInvite)
            }
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var templatesHeader: some View {
        HStack{
            Text("Templates")
                .font(.title2)
                .bold()
                .padding(.horizontal)
            Spacer()
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
        } else {
            List {
                ForEach(sortedPitchers) { pitcher in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pitcher.name)
                                .font(.headline)
                            if let tid = pitcher.templateId,
                               let t = templates.first(where: { $0.id.uuidString == tid }) {
                                Text("Template: \(t.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxHeight: 260)
            .listStyle(.plain)
            .padding(.horizontal)
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
        } else {
            List {
                ForEach(sortedTemplates) { template in
                    TemplateRowView(
                        template: template,
                        isSelected: selectedTemplate?.id == template.id,
                        isEditable: isTemplateEditable(template),
                        editAction: {
                            editorTemplate = template
                        },
                        launchAction: {
                            templatePendingLaunch = template
                            showModeChoice = true
                        }
                    )
                }
                .onDelete { indexSet in
                    let itemsToDelete = indexSet.map { sortedTemplates[$0] }
                    for templateToDelete in itemsToDelete {
                        if isTemplateEditable(templateToDelete) {
                            showDeleteConfirmation(for: templateToDelete)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .listStyle(.plain)
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
                
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Join a live game")
                            .font(.headline)
                        Text("Use the invite link or scan the QR code from the host.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Button("Join via Invite Link") {
                        inviteJoinError = nil
                        inviteJoinText = ""
                        showInviteJoinSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                    // 🔹 Templates Header
                    templatesHeader

                    // 🔹 Templates List / Empty State
                    templatesListView

                    Divider()
                        .padding(.horizontal)

                    // 🔹 Pitchers Header
                    pitchersHeader

                    // 🔹 Pitchers List / Empty State
                    pitchersListView

                    Divider()
                        .padding(.horizontal)
                    
                    storeSection
                    Divider()
                    
                    // 🔹 Account Section
                    accountSection
                    
                    Spacer(minLength: 80) // 👈 Leaves room for footer
                }
                .padding(.top)
                
                
                // 🔹 Bottom-Centered Email
                VStack {
                    Spacer()
                    Text("Signed in as: \(authManager.userEmail)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }
            }
            .sheet(isPresented: $showInviteJoinSheet) { inviteJoinSheetView }
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
                    Text("New Pitcher")
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
                        }
                        Spacer()
                        Button("Save") {
                            let name = newPitcherName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            authManager.createPitcher(name: name, templateId: newPitcherTemplateId) { created in
                                if let created {
                                    pitchers.append(created)
                                }
                                showAddPitcher = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.35)])
                .presentationDragIndicator(.visible)
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

                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
                .environmentObject(authManager)
            }
            .sheet(isPresented: $showPracticeChooser) {
                PracticeSelectionSheet(
                    onCreate: { name, date, _, _ in
                        var sessions = loadPracticeSessions()
                        let new = PracticeSession(id: UUID().uuidString, name: name, date: date)
                        sessions.append(new)
                        savePracticeSessions(sessions)
                    },
                    onChoose: { practiceId in
                        if let tmpl = templatePendingLaunch {
                            selectedTemplate = tmpl
                            NotificationCenter.default.post(
                                name: .templateSelectionDidChange,
                                object: nil,
                                userInfo: [
                                    "templateId": tmpl.id.uuidString
                                ]
                            )
                        }
                        // Look up the session name locally so receivers can update UI immediately
                        let sessions = loadPracticeSessions()
                        let name = sessions.first(where: { $0.id == practiceId })?.name
                        
                        // Persist active practice selection immediately to avoid races
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: "activeIsPractice")
                        defaults.removeObject(forKey: "activeGameId")
                        defaults.set(practiceId, forKey: "activePracticeId")
                        defaults.set("tracker", forKey: "lastView")
                        
                        NotificationCenter.default.post(
                            name: .gameOrSessionChosen,
                            object: nil,
                            userInfo: [
                                "type": "practice",
                                "practiceId": practiceId,
                                "practiceName": name as Any
                            ]
                        )
                        showPracticeChooser = false
                        dismiss()
                    },
                    onCancel: {
                        showPracticeChooser = false
                    },
                    encryptedSelectionByPracticeId: $encryptedSelectionByPracticeId
                )
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct TemplateRowView: View {
    let template: PitchTemplate
    let isSelected: Bool
    let isEditable: Bool
    let editAction: () -> Void
    let launchAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                if template.ownerUid != nil && isEditable == false {
                    Text("Shared")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(template.pitches.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Edit", action: editAction)
                .buttonStyle(.bordered)
                .disabled(!isEditable)
            Button("Launch", action: launchAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isSelected ? Color.blue.opacity(0.2) : Color.clear
        )
    }
}

private struct SettingsPreviewContainer: View {
    @State private var templates: [PitchTemplate] = [
        PitchTemplate(
            id: UUID(),
            name: "Bullpen vs L",
            pitches: ["FB", "SL", "CH"],
            codeAssignments: [
                PitchCodeAssignment(code: "101", pitch: "FB", location: "Strike Middle"),
                PitchCodeAssignment(code: "115", pitch: "FB", location: "Strike Up")
            ]
        ),
        PitchTemplate(
            id: UUID(),
            name: "Game Plan – RHB",
            pitches: ["FB", "SL", "CH"],
            codeAssignments: []
        )
    ]
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var codeShareInitialTab: Int = 0
    @State private var showCodeShareSheet: Bool = false
    @State private var shareCode: String = ""
    @State private var codeShareSheetID: UUID = UUID()
    @State private var showCodeShareModePicker: Bool = false
    @State private var games: [Game] = []
    @State private var pitchers: [Pitcher] = []

    private let allPitches: [String] = ["FB", "SL", "CH", "CB", "SI", "CT"]

    var body: some View {
        SettingsView(
            templates: $templates,
            games: $games,
            pitchers: $pitchers,
            allPitches: allPitches,
            selectedTemplate: $selectedTemplate,
            codeShareInitialTab: $codeShareInitialTab,
            showCodeShareSheet: $showCodeShareSheet,
            shareCode: $shareCode,                 // ✅ ADD
            codeShareSheetID: $codeShareSheetID,    // ✅ ADD
            showCodeShareModePicker: $showCodeShareModePicker
        )
        .environmentObject(AuthManager())
    }
}

extension Notification.Name {
    static let templateSelectionDidChange = Notification.Name("templateSelectionDidChange")
}

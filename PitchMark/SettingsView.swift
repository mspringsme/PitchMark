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
                            Button(pitcher.name) {
                                pitcherActionTargetId = (pitcherActionTargetId == pitcher.id) ? nil : pitcher.id
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

                        Spacer()

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

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    init(pitcher: Pitcher, games: [Game], lockToGameId: String? = nil) {
        self.pitcher = pitcher
        self.games = games
        self.lockToGameId = lockToGameId
    }

    @State private var dateFilter: DateRangeFilter = .all
    @State private var scope: StatScope = .games

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    @State private var selectedGameIds: Set<String> = []
    @State private var selectedPracticeIds: Set<String> = []

    @State private var practiceEvents: [PitchEvent] = []
    @State private var gameEvents: [PitchEvent] = []
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
        let gameIdsWithEvents = Set(gameEvents.compactMap { $0.gameId })
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
            let lockedEvents = gameEvents.filter { $0.gameId == lockedGameId }
            guard let range = dateRange else { return lockedEvents }
            return lockedEvents.filter { range.contains($0.timestamp) }
        }

        let allForPitcher: [PitchEvent] = {
            switch scope {
            case .all:
                return practiceEvents + gameEvents
            case .practice:
                return practiceEvents
            case .games:
                return gameEvents
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

    private var strikeCount: Int {
        filteredEvents.filter { resultType(for: $0) == .strike }.count
    }

    private var totalCount: Int {
        filteredEvents.count
    }

    private var strikePercent: Int {
        totalCount == 0 ? 0 : Int(Double(strikeCount) / Double(totalCount) * 100)
    }

    private var ballCount: Int {
        filteredEvents.filter { resultType(for: $0) == .ball }.count
    }

    private var ballPercent: Int {
        totalCount == 0 ? 0 : Int(Double(ballCount) / Double(totalCount) * 100)
    }

    private var swingingStrikeCount: Int {
        filteredEvents.filter { $0.strikeSwinging && $0.outcome == "K" }.count
    }

    private var lookingStrikeCount: Int {
        filteredEvents.filter { $0.strikeLooking && $0.outcome == "ꓘ" }.count
    }

    private var swingingStrikeEvents: [PitchEvent] {
        filteredEvents.filter { $0.strikeSwinging && $0.outcome == "K" }
    }

    private var lookingStrikeEvents: [PitchEvent] {
        filteredEvents.filter { $0.strikeLooking && $0.outcome == "ꓘ" }
    }

    private var wildPitchCount: Int {
        filteredEvents.filter { $0.wildPitch }.count
    }

    private var passedBallCount: Int {
        filteredEvents.filter { $0.passedBall }.count
    }

    private var walkCount: Int {
        filteredEvents.filter {
            guard let outcome = $0.outcome, !outcome.isEmpty else { return false }
            return outcome == "BB" || outcome == "Walk"
        }.count
    }

    private var hitSpotCount: Int {
        filteredEvents.filter { strictIsLocationMatch($0) }.count
    }

    private var hitSpotEvents: [PitchEvent] {
        filteredEvents.filter { strictIsLocationMatch($0) }
    }

    private var hitSpotPercent: Int {
        totalCount == 0 ? 0 : Int(Double(hitSpotCount) / Double(totalCount) * 100)
    }

    private var outcomesSummary: [(label: String, count: Int, jerseys: String)] {
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
            }
            .onChange(of: selectedGameIds) { _, _ in loadEvents() }
            .onChange(of: selectedPracticeIds) { _, _ in loadEvents() }
            .onChange(of: scope) { _, _ in
                if lockToGameId != nil {
                    scope = .games
                }
                loadEvents()
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
        guard let ownerUid = authManager.user?.uid else { return }

        let requestToken = UUID()
        loadEventsToken = requestToken

        isLoading = true
        practiceEvents = []
        gameEvents = []

        let group = DispatchGroup()

        group.enter()
        authManager.loadPitchEvents { events in
            guard loadEventsToken == requestToken else { group.leave(); return }
            self.practiceEvents = events.filter { $0.pitcherId == pitcherId }
            group.leave()
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
                self.gameEvents.append(contentsOf: filtered)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard loadEventsToken == requestToken else { return }
            self.isLoading = false
        }
    }
}

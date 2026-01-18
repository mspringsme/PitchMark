//
//  SettingsView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//

import SwiftUI

struct SettingsView: View {
    @Binding var templates: [PitchTemplate]
    let allPitches: [String]
    @Binding var selectedTemplate: PitchTemplate? // ✅ Add this line
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

    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    @State private var encryptedSelectionByPracticeId: [String: Bool] = [:]
    
    private var sortedTemplates: [PitchTemplate] {
        templates.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
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
                        showDeleteConfirmation(for: templateToDelete)
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
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 24)
                    // 🔹 Templates Header
                    templatesHeader

                    // 🔹 Templates List / Empty State
                    templatesListView

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
                        }
                        var opponent: String? = nil
                        authManager.loadGames { games in
                            if let g = games.first(where: { $0.id == gameId }) {
                                opponent = g.opponent
                            }
                            NotificationCenter.default.post(name: .gameOrSessionChosen, object: nil, userInfo: ["type": "game", "gameId": gameId, "opponent": opponent as Any])
                        }
                        dismiss()
                    },
                    onCancel: {
                        showGameChooser = false
                    }
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
    let editAction: () -> Void
    let launchAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                Text(template.pitches.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Edit", action: editAction)
                .buttonStyle(.bordered)
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

    private let allPitches: [String] = ["FB", "SL", "CH", "CB", "SI", "CT"]

    var body: some View {
        SettingsView(
            templates: $templates,
            allPitches: allPitches,
            selectedTemplate: $selectedTemplate
        )
        .environmentObject(AuthManager())
    }
}

extension Notification.Name {
    static let templateSelectionDidChange = Notification.Name("templateSelectionDidChange")
}


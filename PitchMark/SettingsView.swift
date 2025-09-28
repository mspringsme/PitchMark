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
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(alignment: .leading, spacing: 20) {
                    // 🔹 Templates Header
                    Text("Templates")
                        .font(.title2)
                        .bold()
                        .padding(.horizontal)
                    
                    // 🔹 New Template Button
                    Button("New Template") {
                        selectedTemplate = PitchTemplate(
                            id: UUID(),
                            name: "",
                            pitches: [],
                            codeAssignments: []
                        )
                    }
                    .padding(.horizontal)
                    
                    // 🔹 Empty State
                    if templates.isEmpty {
                        Text("No templates saved")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        // 🔹 Alphabetical Template List
                        List {
                            ForEach(templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })) { template in
                                Button(action: {
                                    selectedTemplate = template
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .font(.headline)
                                        Text(template.pitches.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(
                                    selectedTemplate?.id == template.id
                                    ? Color.blue.opacity(0.2)
                                    : Color.clear
                                )
                            }
                            .onDelete { indexSet in
                                    for index in indexSet {
                                        let templateToDelete = templates.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending })[index]
                                        showDeleteConfirmation(for: templateToDelete)
                                    }
                                }
                        }
                        .frame(maxHeight: 400) // Optional: constrain height
                        .listStyle(.plain)
                        .padding(.horizontal)
                        
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // 🔹 Account Section
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
            .navigationTitle("Settings")
            .sheet(item: $selectedTemplate) { template in
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
                        selectedTemplate = nil
                    }
                )
            }
        }
    }
}

struct CodeAssignmentPanelWrapper: View {
    @State private var selectedCodes: Set<String> = []
    @State private var selectedPitch: String = ""
    @State private var selectedLocation: String = ""
    @State private var pitchCodeAssignments: [PitchCodeAssignment] = []
    
    let allPitches = ["2 Seam", "4 Seam", "Change", "Curve", "Screw", "Smile", "Drop", "Rise", "Pipe"]
    let allLocations = allLocationsFromGrid()
    
    var body: some View {
        CodeAssignmentPanel(
            selectedCodes: $selectedCodes,
            selectedPitch: $selectedPitch,
            selectedLocation: $selectedLocation,
            pitchCodeAssignments: $pitchCodeAssignments,
            allPitches: allPitches,
            allLocations: allLocations,
            assignAction: {
                // Optional: handle external sync or feedback
            }
        )
        .navigationTitle("Assign Codes")
        .navigationBarTitleDisplayMode(.inline)
        .padding()
    }
}

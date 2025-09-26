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

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
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
                            // 🔹 Template Grid
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                                ForEach(templates) { template in
                                    Button(action: {
                                        selectedTemplate = template
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(template.name)
                                                .font(.headline)
                                            Text(template.pitches.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(
                                            selectedTemplate?.id == template.id
                                                ? Color.blue.opacity(0.2)
                                                : Color.gray.opacity(0.1)
                                        )
                                        .cornerRadius(8)
                                    }
                                }
                            }
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
                }

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

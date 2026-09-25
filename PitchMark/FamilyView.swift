//
//  FamilyView.swift
//  PitchMark
//
//  Phase 9 - the real Family screen, replacing the
//  ComingSoonSheetView(area: .family, ...) placeholder wired up in Phase 2
//  step 2. Family members never install or sign into PitchMark - every
//  update goes out through iOS's native share sheet (`ShareSheet`,
//  TemplateEditorView.swift:22, reused as-is), so recipients get a normal
//  text/AirDrop/Mail message with nothing new to set up. Deliberately kept
//  out of the Pitchmark Display target's membershipExceptions; Display
//  has no use for this UI.
//

import SwiftUI

private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct FamilyView: View {
    /// From ParentGameShellView's currently-selected child, same as
    /// MomentsLibraryView's contextPlayer - words the one-tap messages.
    var contextPlayerName: String? = nil
    var onSwitchToArea: ((HomeArea) -> Void)? = nil

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [FamilyContact] = []
    @State private var newContactName: String = ""
    @State private var selectedContact: FamilyContact? = nil

    @State private var activeShareItem: ShareSheetItem? = nil
    @State private var showMomentPicker = false
    @State private var moments: [Moment] = []
    @State private var showCustomMessageComposer = false
    @State private var customMessageText: String = ""

    private var subjectName: String { contextPlayerName ?? "She" }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contactsSection

                    if let contact = selectedContact {
                        actionsSection(for: contact)
                    }
                }
                .padding()
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeAreaTabBar(current: .family) { selected in
                    onSwitchToArea?(selected)
                    dismiss()
                }
            }
        }
        .onAppear { refreshContacts() }
        .sheet(item: $activeShareItem) { item in
            ShareSheet(items: item.items)
        }
        .sheet(isPresented: $showMomentPicker) {
            momentPickerSheet
        }
        .sheet(isPresented: $showCustomMessageComposer) {
            customMessageSheet
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family")
                .font(.headline)

            if contacts.isEmpty {
                Text("No family added yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(contacts) { contact in
                        Button {
                            selectedContact = contact
                        } label: {
                            HStack {
                                Text(contact.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if contact.id == selectedContact?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Name", text: $newContactName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addContact()
                }
                .disabled(newContactName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(for contact: FamilyContact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send \(contact.name) an update")
                .font(.headline)

            VStack(spacing: 8) {
                familyActionButton("🥎 Game Starting") {
                    share(text: "\(subjectName)'s game is starting!")
                }
                familyActionButton("⭐ Great Play!") {
                    share(text: "\(subjectName) just had a great play!")
                }
                familyActionButton("📷 Send Moment") {
                    refreshMoments()
                    showMomentPicker = true
                }
                familyActionButton("🏁 Game Over") {
                    share(text: "\(subjectName)'s game just ended!")
                }
                familyActionButton("💬 Write Message") {
                    customMessageText = ""
                    showCustomMessageComposer = true
                }
            }
        }
    }

    private func familyActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var momentPickerSheet: some View {
        NavigationView {
            List {
                if moments.isEmpty {
                    Text("No Moments recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(moments) { moment in
                    let hasLocalFile = moment.id.flatMap(resolvedMomentVideoURL(for:)).map {
                        FileManager.default.fileExists(atPath: $0.path)
                    } ?? false

                    Button {
                        showMomentPicker = false
                        guard let id = moment.id, let url = resolvedMomentVideoURL(for: id) else { return }
                        activeShareItem = ShareSheetItem(items: [url])
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(moment.displayTitle)
                                Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !hasLocalFile {
                                Text("Unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!hasLocalFile)
                }
            }
            .navigationTitle("Send Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showMomentPicker = false }
                }
            }
        }
    }

    @ViewBuilder
    private var customMessageSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Message")
                    .font(.headline)
                TextField("Type a message…", text: $customMessageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
                Spacer()
            }
            .padding()
            .navigationTitle("Write Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        showCustomMessageComposer = false
                        share(text: customMessageText)
                    }
                    .disabled(customMessageText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showCustomMessageComposer = false }
                }
            }
        }
    }

    private func share(text: String) {
        activeShareItem = ShareSheetItem(items: [text])
    }

    private func refreshContacts() {
        authManager.loadFamilyContacts { contacts = $0 }
    }

    private func refreshMoments() {
        authManager.loadMoments { moments = $0 }
    }

    private func addContact() {
        let name = newContactName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        authManager.saveFamilyContact(name: name) { result in
            if case .success = result {
                newContactName = ""
                refreshContacts()
            }
        }
    }
}

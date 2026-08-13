import SwiftUI

struct DisplayRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showAccount = false

    var body: some View {
        Group {
            if authManager.isCheckingAuth {
                DisplaySplashView()
            } else if authManager.isSignedIn {
                if subscriptionManager.isPro {
                    DisplayOnlyScreen()
                } else {
                    VStack(spacing: 16) {
                        ProPaywallView(
                            title: "PitchMark Pro Required",
                            message: "Display app access is included with PitchMark Pro.",
                            allowsClose: false
                        )

                        Button("Sign Out") {
                            authManager.signOut()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                SignInView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if authManager.isSignedIn {
                Button {
                    showAccount = true
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding()
                .accessibilityLabel("Account and support")
                .accessibilityHint("Opens account deletion, support, privacy, and sign-out options.")
            }
        }
        .sheet(isPresented: $showAccount) {
            DisplayAccountSheet()
                .environmentObject(authManager)
                .dynamicTypeSize(.medium)
        }
        .onAppear {
            authManager.restoreSignIn()
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            Task {
                await subscriptionManager.refreshForAuthStateChange(isSignedIn: isSignedIn)
            }
        }
    }
}

private struct DisplayAccountSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteAccount = false
    @State private var deleteConfirmation = ""
    @State private var isDeleting = false
    @State private var deleteError: String?

    private let supportURL = URL(string: "https://pitchmark.app/support")!
    private let privacyPolicyURL = URL(string: "https://pitchmark.app/privacy")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: authManager.userEmail)

                    Button("Sign Out", role: .destructive) {
                        dismiss()
                        authManager.signOut()
                    }

                    Button("Delete Account", role: .destructive) {
                        deleteConfirmation = ""
                        deleteError = nil
                        showDeleteAccount = true
                    }
                }

                Section("Help and Legal") {
                    Link("Contact Support", destination: supportURL)
                    Link("Privacy Policy", destination: privacyPolicyURL)
                    Link("Terms of Use (EULA)", destination: termsOfUseURL)
                }

                Section {
                    Text("Deleting your account permanently removes or unlinks account-associated app data. Active subscriptions must be managed separately in your Apple ID settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showDeleteAccount) {
            NavigationStack {
                Form {
                    Section {
                        Text("This permanently deletes your PitchMark account and account-associated data. Type DELETE to confirm.")
                    }

                    Section("Confirmation") {
                        TextField("Type DELETE", text: $deleteConfirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        if let deleteError {
                            Text(deleteError)
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button(isDeleting ? "Deleting…" : "Permanently Delete Account", role: .destructive) {
                            isDeleting = true
                            deleteError = nil
                            authManager.deleteAccount { result in
                                DispatchQueue.main.async {
                                    isDeleting = false
                                    switch result {
                                    case .success:
                                        showDeleteAccount = false
                                        dismiss()
                                    case .failure(let error):
                                        deleteError = error.localizedDescription
                                    }
                                }
                            }
                        }
                        .disabled(
                            isDeleting ||
                            deleteConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE"
                        )
                    }
                }
                .navigationTitle("Delete Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDeleteAccount = false }
                    }
                }
            }
            .interactiveDismissDisabled(isDeleting)
            .dynamicTypeSize(.medium)
        }
        .dynamicTypeSize(.medium)
    }
}

private struct DisplaySplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Pitchmark")
                    .font(.largeTitle).bold()
                    .foregroundColor(.blue)
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

import SwiftUI
import UIKit

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
        .overlay {
            if authManager.accountDeletionAcknowledgementID != nil {
                DisplayAccountDeletionAcknowledgementOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: authManager.accountDeletionAcknowledgementID
        )
        .sheet(isPresented: $showAccount) {
            DisplayAccountSheet()
                .environmentObject(authManager)
                .dynamicTypeSize(.medium)
        }
        .onAppear {
            authManager.restoreSignIn()
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if !isSignedIn {
                showAccount = false
            }
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
    @State private var showFinalDeleteConfirmation = false
    @State private var deleteConfirmation = ""
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var requiresDeleteRecentLogin = false
    @FocusState private var isDeleteConfirmationFocused: Bool

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
                        requiresDeleteRecentLogin = false
                        showDeleteAccount = true
                    }
                }

                Section("Help and Legal") {
                    Link("Contact Support", destination: supportURL)
                    Link("Privacy Policy", destination: privacyPolicyURL)
                    Link("Terms of Use (EULA)", destination: termsOfUseURL)
                }

                Section {
                    Text("Deleting your account permanently removes or unlinks account-associated app data. Some order, payment, fulfillment, tax, accounting, dispute, or legal records may be retained as needed without an active account link. Active subscriptions must be managed separately in your Apple ID settings.")
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
                ZStack {
                    Form {
                        Section {
                            Text("This permanently deletes your PitchMark account and removes or unlinks account-associated app data. Some transaction records may be retained when legally required, without an active account link. Type DELETE to confirm.")
                        }

                        Section("Confirmation") {
                            TextField("Type DELETE", text: $deleteConfirmation)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .focused($isDeleteConfirmationFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    isDeleteConfirmationFocused = false
                                }

                            if let deleteError {
                                Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Account deletion failed. \(deleteError)")
                            }

                            if requiresDeleteRecentLogin {
                                Button("Sign Out to Re-Authenticate", role: .destructive) {
                                    showDeleteAccount = false
                                    dismiss()
                                    authManager.signOut()
                                }
                            }
                        }

                        Section {
                            Button("Permanently Delete Account", role: .destructive) {
                                isDeleteConfirmationFocused = false
                                showFinalDeleteConfirmation = true
                            }
                            .disabled(
                                deleteConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE"
                            )
                            .accessibilityHint("Opens the final permanent deletion confirmation.")
                        }
                    }
                    .disabled(accountDeletionIsBlocking)
                    .accessibilityHidden(accountDeletionIsBlocking)

                    if accountDeletionIsBlocking {
                        accountDeletionStatusView
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .navigationTitle("Delete Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDeleteAccount = false }
                            .disabled(accountDeletionIsBlocking)
                    }
                }
            }
            .alert("Permanently delete this account?", isPresented: $showFinalDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Account Permanently", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This cannot be undone.")
            }
            .interactiveDismissDisabled(accountDeletionIsBlocking)
            .animation(.easeInOut(duration: 0.2), value: accountDeletionIsBlocking)
            .onAppear {
                isDeleteConfirmationFocused = true
            }
            .dynamicTypeSize(.medium)
        }
        .dynamicTypeSize(.medium)
    }

    private var accountDeletionIsBlocking: Bool {
        isDeleting
    }

    @ViewBuilder
    private var accountDeletionStatusView: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Deleting Account…")
                    .font(.headline)
                Text("Securely removing your account data. Keep PM Display open until this finishes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Deleting account. Keep PM Display open until this finishes.")
        }
    }

    private func deleteAccount() {
        isDeleteConfirmationFocused = false
        showFinalDeleteConfirmation = false
        isDeleting = true
        deleteError = nil
        requiresDeleteRecentLogin = false
        UIAccessibility.post(
            notification: .announcement,
            argument: "Deleting account. Keep PM Display open until this finishes."
        )

        authManager.deleteAccount { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    deleteConfirmation = ""
                    deleteError = nil
                    requiresDeleteRecentLogin = false
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Account deleted. Returning to sign in."
                    )
                case .failure(let error):
                    deleteError = error.localizedDescription
                    if let deleteError = error as? DeleteAccountError,
                       case .requiresRecentLogin = deleteError {
                        requiresDeleteRecentLogin = true
                    } else {
                        requiresDeleteRecentLogin = false
                    }
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Account deletion failed. \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

private struct DisplayAccountDeletionAcknowledgementOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Account Deleted")
                    .font(.headline)
                Text("Your account-associated app data was deleted or unlinked. Returning to sign in…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Account deleted. Returning to sign in.")
        }
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

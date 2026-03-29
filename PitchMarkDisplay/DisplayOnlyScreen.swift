import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct DisplayOnlyScreen: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var displayCodePayload: DisplayOnlyPayload?
    @State private var displayStateListener: ListenerRegistration?
    @State private var activeSessionListener: ListenerRegistration?
    @State private var statusMessage: String = "Waiting for primary…"
    @State private var showSignOutConfirm = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let payload = displayCodePayload {
                CodeDisplayOverlayView(
                    colorName: payload.colorName,
                    code: payload.code,
                    showsCloseButton: false,
                    onClose: {}
                )

                Button(action: clearDisplayCode) {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    Text("Display Mode")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    showSignOutConfirm = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 100)
            }
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("You will need to sign in again to use display mode.")
        }
        .onAppear {
            forceOrientation(.landscapeRight)
            startListeningToDisplayState()
            startListeningToActiveSession()
        }
        .onDisappear {
            stopListening()
            forceOrientation(.portrait)
        }
    }

    private func startListeningToDisplayState() {
        stopDisplayStateListener()
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")

        displayStateListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Display listener error:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                DispatchQueue.main.async { self.displayCodePayload = nil }
                return
            }
            if let colorName = data["colorName"] as? String,
               let code = data["code"] as? String,
               !colorName.isEmpty,
               !code.isEmpty {
                DispatchQueue.main.async {
                    self.displayCodePayload = DisplayOnlyPayload(colorName: colorName, code: code)
                }
            } else {
                DispatchQueue.main.async { self.displayCodePayload = nil }
            }
        }
    }

    private func startListeningToActiveSession() {
        stopActiveSessionListener()
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("meta")
            .document("activeSession")

        activeSessionListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Active session listener error:", err.localizedDescription)
                return
            }
            let data = snap?.data() ?? [:]
            let mode = (data["mode"] as? String ?? "").lowercased()
            DispatchQueue.main.async {
                if mode == "primary" {
                    self.statusMessage = "Waiting for code…"
                } else {
                    self.statusMessage = "Waiting for primary…"
                }
            }
        }
    }

    private func stopListening() {
        stopDisplayStateListener()
        stopActiveSessionListener()
    }

    private func clearDisplayCode() {
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return }
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")
            .setData([
                "colorName": FieldValue.delete(),
                "code": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    private func signOut() {
        authManager.signOut()
    }

    private func stopDisplayStateListener() {
        displayStateListener?.remove()
        displayStateListener = nil
    }

    private func stopActiveSessionListener() {
        activeSessionListener?.remove()
        activeSessionListener = nil
    }

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        activeWindowRootViewController()?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func activeWindowRootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
}

private struct DisplayOnlyPayload: Identifiable {
    let id = UUID()
    let colorName: String
    let code: String
}

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

private struct DisplayCodePayload: Identifiable {
    let id = UUID()
    let colorName: String
    let code: String
}

struct DisplayOnlyWindowView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayCodePayload: DisplayCodePayload?
    @State private var displayStateListener: ListenerRegistration?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let payload = displayCodePayload {
                CodeDisplayOverlayView(
                    colorName: payload.colorName,
                    code: payload.code,
                    showsCloseButton: true,
                    onClose: { handleExit() }
                )
            } else {
                VStack(spacing: 12) {
                    Text("Display Mode")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Waiting for code…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Button("Exit") {
                handleExit()
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.85))
            .padding(.top, 10)
            .padding(.trailing, 12)
        }
        .onAppear {
            forceOrientation(.landscapeRight)
            startListeningToDisplayState()
        }
        .onDisappear {
            stopListeningToDisplayState()
            forceOrientation(.portrait)
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayOnlyExitRequested)) { _ in
            dismiss()
        }
    }

    private func handleExit() {
        NotificationCenter.default.post(name: .displayOnlyExitRequested, object: nil)
        dismiss()
    }

    private func startListeningToDisplayState() {
        stopListeningToDisplayState()
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")

        displayStateListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Display window listener error:", err.localizedDescription)
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
                    self.displayCodePayload = DisplayCodePayload(colorName: colorName, code: code)
                }
            } else {
                DispatchQueue.main.async { self.displayCodePayload = nil }
            }
        }
    }

    private func stopListeningToDisplayState() {
        displayStateListener?.remove()
        displayStateListener = nil
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

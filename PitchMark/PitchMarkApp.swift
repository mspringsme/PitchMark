//
//  PitchMarkApp.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAppCheck

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isCheckingAuth {
                SplashView()
            } else if authManager.isSignedIn {
                PitchTrackerView()
            } else {
                SignInView()
            }
        }
        .onAppear {
            authManager.restoreSignIn() // ✅ safe here
        }
        .onOpenURL { url in
            handleInviteLink(url)
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                LiveGameService.shared.cleanupExpiredJoinArtifacts()
                if let token = UserDefaults.standard.string(forKey: "pendingInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingInviteToken")
                    joinLiveGameByInviteToken(token)
                }
            }
        }
    }

    private func handleInviteLink(_ url: URL) {
        guard let token = inviteToken(from: url), !token.isEmpty else { return }
        if authManager.isSignedIn {
            joinLiveGameByInviteToken(token)
        } else {
            UserDefaults.standard.set(token, forKey: "pendingInviteToken")
        }
    }

    private func joinLiveGameByInviteToken(_ token: String) {
        LiveGameService.shared.joinLiveGameByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "resolved": true,
                            "type": "liveGame",
                            "liveId": liveId
                        ]
                    )
                case .failure(let err):
                    print("❌ Invite link join failed:", err.localizedDescription)
                }
            }
        }
    }

    private func inviteToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        guard host == "join" || path == "/join" else { return nil }
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        return token
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("PitchMark")
                    .font(.largeTitle).bold()
                    .foregroundColor(.blue)
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // ✅ Set provider factory BEFORE configuring Firebase
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif

        // ✅ Configure Firebase BEFORE touching AppCheck.appCheck()
        FirebaseApp.configure()

        FirebaseConfiguration.shared.setLoggerLevel(.warning)

        // ✅ Now it's safe to request an App Check token (prints debug token)
        #if DEBUG
        AppCheck.appCheck().token(forcingRefresh: true) { token, error in
            if let error = error {
                print("❌ AppCheck token error:", error.localizedDescription)
            } else {
                print("✅ AppCheck token:", token?.token ?? "nil")
            }
        }
        #endif

        return true
    }
}


@main
struct PitchMarkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authManager = AuthManager()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
        }
    }
}


extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

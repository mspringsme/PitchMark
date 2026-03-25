//
//  PitchMarkApp.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAppCheck

private final class PitchMarkAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        return AppAttestProvider(app: app)
    }
}

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
            if authManager.handleEmailSignInLink(url) {
                return
            }
            handleInviteLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if authManager.handleEmailSignInLink(url) {
                return
            }
            handleInviteLink(url)
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                LiveGameService.shared.cleanupExpiredJoinArtifacts()
                if let token = UserDefaults.standard.string(forKey: "pendingInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingInviteToken")
                    joinLiveGameByInviteToken(token)
                }
                if let token = UserDefaults.standard.string(forKey: "pendingDisplayInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingDisplayInviteToken")
                    joinDisplayGameByInviteToken(token)
                }
                if let token = UserDefaults.standard.string(forKey: "pendingPitcherInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingPitcherInviteToken")
                    joinPitcherByInviteToken(token)
                }
            }
        }
    }

    private func handleInviteLink(_ url: URL) {
        if let token = pitcherInviteToken(from: url), !token.isEmpty {
            if authManager.isSignedIn {
                joinPitcherByInviteToken(token)
            } else {
                UserDefaults.standard.set(token, forKey: "pendingPitcherInviteToken")
            }
            return
        }

        if let token = displayInviteToken(from: url), !token.isEmpty {
            if authManager.isSignedIn {
                joinDisplayGameByInviteToken(token)
            } else {
                UserDefaults.standard.set(token, forKey: "pendingDisplayInviteToken")
            }
            return
        }

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

    private func joinDisplayGameByInviteToken(_ token: String) {
        LiveGameService.shared.joinDisplayGameByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "resolved": true,
                            "type": "display",
                            "liveId": liveId
                        ]
                    )
                case .failure(let err):
                    print("❌ Display invite join failed:", err.localizedDescription)
                }
            }
        }
    }

    private func joinPitcherByInviteToken(_ token: String) {
        authManager.joinPitcherByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let err):
                    print("❌ Pitcher invite join failed:", err.localizedDescription)
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

    private func displayInviteToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        guard host == "display" || path == "/display" else { return nil }
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        return token
    }

    private func pitcherInviteToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        guard host == "pitcher" || path == "/pitcher" else { return nil }
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
        #else
        AppCheck.setAppCheckProviderFactory(PitchMarkAppCheckProviderFactory())
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

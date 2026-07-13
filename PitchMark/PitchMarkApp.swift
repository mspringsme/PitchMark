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
    private struct CheckoutAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showDisplayCover = false
    @State private var showDisplayOnboarding = false
    @State private var showProPaywall = false
    @State private var checkoutAlert: CheckoutAlert? = nil
    @AppStorage(PitchTrackerView.DefaultsKeys.didShowDisplayOnboarding) private var didShowDisplayOnboarding = false
    private let displayAppSearchURL = URL(string: "https://apps.apple.com/us/search?term=Pitchmark%20Display")!

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
        .fullScreenCover(isPresented: $showDisplayCover) {
            DisplayOnlyWindowView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView(
                title: "PitchMark Pro",
                message: "PitchMark Pro unlocks the main app features and gives you access to the separate Pitchmark Display companion app. You can install Display from the App Store after purchase.",
                allowsClose: true
            )
        }
        .sheet(isPresented: $showDisplayOnboarding) {
            DisplayOnboardingView(
                displayAppSearchURL: displayAppSearchURL,
                openDisplayApp: {
                    guard let url = URL(string: "pitchmarkdisplay://") else { return }
                    UIApplication.shared.open(url)
                },
                dismissAction: {
                    didShowDisplayOnboarding = true
                    showDisplayOnboarding = false
                }
            )
        }
        .alert(item: $checkoutAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            authManager.restoreSignIn() // ✅ safe here
        }
        .onOpenURL { url in
            if authManager.handleEmailSignInLink(url) {
                return
            }
            if handleRetailCheckoutReturn(url) {
                return
            }
            handleInviteLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if authManager.handleEmailSignInLink(url) {
                return
            }
            if handleRetailCheckoutReturn(url) {
                return
            }
            handleInviteLink(url)
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            Task {
                await subscriptionManager.refreshForAuthStateChange(isSignedIn: isSignedIn)
            }
            if isSignedIn {
                LiveGameService.shared.cleanupExpiredJoinArtifacts()
                if let token = UserDefaults.standard.string(forKey: "pendingInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingInviteToken")
                    joinLiveGameByInviteToken(token)
                }
                if let token = UserDefaults.standard.string(forKey: "pendingPitcherInviteToken"), !token.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "pendingPitcherInviteToken")
                    joinPitcherByInviteToken(token)
                }
            } else {
                showDisplayCover = false
                showDisplayOnboarding = false
            }
        }
        .onChange(of: subscriptionManager.isPro) { _, isPro in
            guard isPro, !didShowDisplayOnboarding else { return }
            DispatchQueue.main.async {
                showDisplayOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayOnlyPresentRequested)) { _ in
            showDisplayCover = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayOnlyExitRequested)) { _ in
            showDisplayCover = false
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

        guard let token = inviteToken(from: url), !token.isEmpty else { return }
        if authManager.isSignedIn {
            joinLiveGameByInviteToken(token)
        } else {
            UserDefaults.standard.set(token, forKey: "pendingInviteToken")
        }
    }

    private func handleRetailCheckoutReturn(_ url: URL) -> Bool {
        let normalizedPath = url.path.lowercased()
        switch normalizedPath {
        case "/stripe/success":
            UserDefaults.standard.set(true, forKey: "openOrderHistoryAfterCheckout")
            NotificationCenter.default.post(name: .retailCheckoutSucceeded, object: nil)
            return true
        case "/stripe/cancel":
            checkoutAlert = CheckoutAlert(
                title: "Checkout Canceled",
                message: "No charge was made. You can return to the store and try again anytime."
            )
            return true
        default:
            return false
        }
    }

    private func joinLiveGameByInviteToken(_ token: String) {
        guard subscriptionManager.isPro else {
            showProPaywall = true
            return
        }

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
                    debugLog("❌ Invite link join failed:", err.localizedDescription)
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
                    debugLog("❌ Pitcher invite join failed:", err.localizedDescription)
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

    private func pitcherInviteToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        guard host == "pitcher" || path == "/pitcher" else { return nil }
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value
        return token
    }
}

private struct DisplayOnboardingView: View {
    let displayAppSearchURL: URL
    let openDisplayApp: () -> Void
    let dismissAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("PitchMark Display is a separate app")
                        .font(.title2.bold())

                    Text("PitchMark Pro unlocks access to the companion Display app, but it installs separately from the App Store.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Buy Pro in the main app", systemImage: "checkmark.circle.fill")
                        Label("Install Pitchmark Display from the App Store", systemImage: "arrow.down.circle.fill")
                        Label("Open Display when you are ready to run a live session", systemImage: "play.circle.fill")
                    }
                    .font(.subheadline)

                    VStack(spacing: 12) {
                        Button {
                            openDisplayApp()
                        } label: {
                            Label("Open Display App", systemImage: "app.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Link(destination: displayAppSearchURL) {
                            Label("Get Pitchmark Display", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button("Maybe Later") {
                            dismissAction()
                            dismiss()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Display Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismissAction()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
//                Text("PitchMark")
//                    .font(.largeTitle).bold()
//                    .foregroundColor(.blue)

                Image("SoftballBaseballWtitle4")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

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
                debugLog("❌ AppCheck token error:", error.localizedDescription)
            } else {
                debugLog("✅ AppCheck token fetched")
            }
        }
        #endif

        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    static func setOrientationLock(_ lock: UIInterfaceOrientationMask) {
        orientationLock = lock
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { scene in
                    scene.windows.first(where: { $0.isKeyWindow })?
                        .rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
                }
        }
    }
}


@main
struct PitchMarkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authManager = AuthManager()
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(subscriptionManager)
        }
    }
}


extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

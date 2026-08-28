import SwiftUI
import FirebaseCore
import FirebaseAppCheck

private final class PitchMarkDisplayAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        return AppAttestProvider(app: app)
    }
}

class DisplayAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(PitchMarkDisplayAppCheckProviderFactory())
        #endif

        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        return true
    }
}

@main
struct PitchMarkDisplayApp: App {
    @UIApplicationDelegateAdaptor(DisplayAppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            DisplayRootView()
                .environmentObject(authManager)
                .environmentObject(subscriptionManager)
                .dynamicTypeSize(.medium)
                .onOpenURL { url in
                    _ = authManager.handleEmailSignInLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    _ = authManager.handleEmailSignInLink(url)
                }
        }
    }
}

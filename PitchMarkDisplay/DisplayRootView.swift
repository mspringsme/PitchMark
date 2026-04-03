import SwiftUI

struct DisplayRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

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
        .onAppear {
            authManager.restoreSignIn()
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

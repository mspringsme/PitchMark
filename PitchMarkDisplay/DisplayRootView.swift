import SwiftUI

struct DisplayRootView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isCheckingAuth {
                DisplaySplashView()
            } else if authManager.isSignedIn {
                DisplayOnlyScreen()
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

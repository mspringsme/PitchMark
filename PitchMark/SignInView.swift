//
//  SignInView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//


import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager
    

    var body: some View {
        VStack(spacing: 40) {
            Text("PitchMark")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.blue)

            GoogleSignInButton(
                scheme: .light,
                style: .standard,
                state: .normal
            ) {
                handleGoogleSignIn()
            }
            .frame(width: 250, height: 50) // Adjust width here

            Spacer()

        }
        .padding()
    }

    private func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
                print("No root view controller found")
                return
        }

        authManager.signInWithGoogle(presenting: rootViewController)
    }
}

//#Preview {
//    SignInView()
//        .environmentObject(AuthManager())
//}

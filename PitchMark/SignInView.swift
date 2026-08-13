//
//  SignInView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//


import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager
    var onSkipDemo: (() -> Void)? = nil

    @State private var email: String = ""
    @State private var isSendingEmail: Bool = false
    @State private var emailStatus: String? = nil
    @State private var animateGradient: Bool = false
    @State private var showLearnPitchMark = false

    private var isDisplayApp: Bool {
        Bundle.main.bundleIdentifier == "app.Pitchmark-Display"
    }

    private var canSendEmailLink: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let authControlMaxWidth: CGFloat = 360
    private let authControlHeight: CGFloat = 56
    private let authControlCornerRadius: CGFloat = 12
    private let secondaryAuthControlMaxWidth: CGFloat = 252
    private let secondaryAuthControlHeight: CGFloat = 50
    private let secondaryAuthControlCornerRadius: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                movingGradientBackground
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.34),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    if isDisplayApp {
                        VStack(spacing: 6) {
                            Text("PM Display")
                                .font(.largeTitle.bold())
                            Text("PitchMark companion display")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                        .accessibilityElement(children: .combine)
                    } else {
                        Image("SoftballBaseballWtitle4")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .accessibilityLabel("PitchMark")
                    }

                    VStack(spacing: 14) {
                        SignInWithAppleButton(.signIn, onRequest: { request in
                            authManager.prepareAppleSignIn(request)
                        }, onCompletion: { result in
                            authManager.handleAppleSignIn(result: result)
                        })
                        .signInWithAppleButtonStyle(.black)
                        .frame(maxWidth: authControlMaxWidth, minHeight: authControlHeight, maxHeight: authControlHeight)
                        .clipShape(RoundedRectangle(cornerRadius: authControlCornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                        .accessibilityLabel("Sign in with Apple")
                        .accessibilityHint("Authenticates your PitchMark account using Apple.")

                        GoogleSignInButton(
                            scheme: .dark,
                            style: .standard,
                            state: .normal
                        ) {
                            handleGoogleSignIn()
                        }
                        .frame(width: secondaryAuthControlMaxWidth, height: secondaryAuthControlHeight)
                        .clipShape(RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
                        .accessibilityLabel("Sign in with Google")
                        .accessibilityHint("Authenticates your PitchMark account using Google.")

                        if authManager.isSigningInWithApple {
                            ProgressView("Signing in with Apple...")
                                .tint(.white)
                                .foregroundStyle(.white)
                        }

                        if let authenticationErrorMessage = authManager.authenticationErrorMessage {
                            Text(authenticationErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 420)

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(Color.white.opacity(0.24))
                                .frame(height: 1)

                            Text("Email sign in")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.74))
                                .textCase(.uppercase)

                            Rectangle()
                                .fill(Color.white.opacity(0.24))
                                .frame(height: 1)
                        }
                        .frame(maxWidth: authControlMaxWidth)

                        TextField("you@email.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.plain)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: secondaryAuthControlMaxWidth, minHeight: secondaryAuthControlHeight, maxHeight: secondaryAuthControlHeight)
                            .background(
                                RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 7)
                            .accessibilityLabel("Email address")
                            .accessibilityHint("Enter the email where you want to receive a sign-in link.")

                        Button {
                            isSendingEmail = true
                            emailStatus = nil
                            authManager.sendEmailSignInLink(email: email) { result in
                                DispatchQueue.main.async {
                                    isSendingEmail = false
                                    switch result {
                                    case .success:
                                        emailStatus = "Check your email for a sign-in link."
                                    case .failure(let error):
                                        emailStatus = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSendingEmail {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }

                                Text(isSendingEmail ? "Sending..." : "Send Sign-In Link")
                                    .font(.body.weight(.semibold))
                            }
                                .foregroundStyle(canSendEmailLink ? .white : .white.opacity(0.38))
                                .frame(maxWidth: secondaryAuthControlMaxWidth, minHeight: secondaryAuthControlHeight, maxHeight: secondaryAuthControlHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous)
                                        .fill(canSendEmailLink ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: secondaryAuthControlCornerRadius, style: .continuous)
                                        .stroke(Color.white.opacity(canSendEmailLink ? 0.28 : 0.12), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(canSendEmailLink ? 0.22 : 0.08), radius: 12, x: 0, y: 7)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSendingEmail || !canSendEmailLink)
                        .accessibilityHint("Sends a sign-in link to your email.")

                        if let emailStatus {
                            Text(emailStatus)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(emailStatus.hasPrefix("Check") ? .white : .red)
                        }
                    }
                    .frame(maxWidth: 420)

                    if let onSkipDemo {
                        Button {
                            onSkipDemo()
                        } label: {
                            Text("Skip for Now")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens a local demo with one game, one pitcher, and one grid key.")
                    }

                    if !isDisplayApp {
                        Button {
                            showLearnPitchMark = true
                        } label: {
                            Text("Learn PitchMark")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.64))
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens PitchMark tutorial videos.")
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, isDisplayApp ? 28 : proxy.size.height * 0.16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .onAppear {
                animateGradient = true
            }
            .modifier(LearnPitchMarkPresentation(isPresented: $showLearnPitchMark))
        }
    }

    private var movingGradientBackground: some View {
        LinearGradient(
            colors: animateGradient
                ? [
                    Color(red: 0.02, green: 0.22, blue: 0.34),
                    Color(red: 0.08, green: 0.44, blue: 0.32),
                    Color(red: 0.73, green: 0.23, blue: 0.18),
                    Color(red: 0.02, green: 0.04, blue: 0.10)
                ]
                : [
                    Color(red: 0.02, green: 0.05, blue: 0.13),
                    Color(red: 0.09, green: 0.35, blue: 0.49),
                    Color(red: 0.14, green: 0.49, blue: 0.28),
                    Color(red: 0.57, green: 0.17, blue: 0.14)
                ],
            startPoint: animateGradient ? .topTrailing : .topLeading,
            endPoint: animateGradient ? .bottomLeading : .bottomTrailing
        )
        .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animateGradient)
    }

    private func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            debugLog("No root view controller found")
            return
        }

        authManager.signInWithGoogle(presenting: rootViewController)
    }

}

#if DISPLAY_APP
private struct LearnPitchMarkPresentation: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
    }
}
#else
private struct LearnPitchMarkPresentation: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            LearnPitchMarkView()
                .fixedAppDynamicType()
        }
    }
}
#endif

//#Preview {
//    SignInView()
//        .environmentObject(AuthManager())
//}

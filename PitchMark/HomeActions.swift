import SwiftUI

/// Home's row of three (2026-11-10): Team Supplies (the store), Join a
/// Game and Account, each with the softball/baseball art. It replaced the
/// "store" capsule, the top bar's Join button and the account button at
/// the bottom of Home. A top-level struct on purpose - see CLAUDE.md on
/// Home's generic type depth.
struct HomeActionRow<Supplies: View>: View {
    @ViewBuilder let supplies: () -> Supplies
    let onJoin: () -> Void
    let onAccount: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                supplies()
            } label: {
                HomeActionTile(title: "Team Supplies")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.action.supplies")

            Button(action: onJoin) {
                HomeActionTile(title: "Join a Game")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open join flow for invite link or QR code.")
            .accessibilityIdentifier("home.action.join")

            Button(action: onAccount) {
                HomeActionTile(title: "Account")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens account actions including sign out and account management.")
            .accessibilityIdentifier("home.action.account")
        }
        .padding(.horizontal)
    }
}

struct HomeActionTile: View {
    static let imageName = "SoftballAndBaseball"
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(Self.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// The line at the bottom of Home: who's signed in. Not a button - the
/// Account tile opens the account sheet.
enum HomeSignedInLine {
    static func text(email: String?) -> String {
        guard let email, !email.isEmpty else { return "Not signed in" }
        return "Signed in as \(email)"
    }
}

/// The bottom of Home (2026-11-10): the row of three, then the
/// signed-in line, pinned under the scrolling cards.
struct HomeBottomBar<Supplies: View>: View {
    let email: String?
    @ViewBuilder let supplies: () -> Supplies
    let onJoin: () -> Void
    let onAccount: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HomeActionRow(supplies: supplies, onJoin: onJoin, onAccount: onAccount)
                .padding(.top, 10)
            HomeSignedInFooter(email: email)
        }
        .background(.ultraThinMaterial)
    }
}

/// `-UITestHomeActions`: the row and the signed-in line on their own.
/// Each button reports what it opened; a Sign In / Sign Out button
/// changes the account the line shows.
struct HomeActionsUITestHarness: View {
    @State private var opened = ""
    @State private var email: String? = "coach@example.com"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text(opened)
                        .accessibilityIdentifier("harness.opened")
                    Button(email == nil ? "Sign In" : "Sign Out") {
                        email = email == nil ? "assistant@example.com" : nil
                    }
                    .accessibilityIdentifier("harness.toggleSignIn")
                    // Enough to scroll, like Home's cards.
                    ForEach(0..<30, id: \.self) { index in
                        Text("Card \(index)")
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.05)))
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("harness.scroll")
            .safeAreaInset(edge: .bottom) {
                HomeBottomBar(email: email) {
                    Text("Store")
                        .accessibilityIdentifier("harness.store")
                } onJoin: {
                    opened = "join"
                } onAccount: {
                    opened = "account"
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct HomeSignedInFooter: View {
    let email: String?

    var body: some View {
        Text(HomeSignedInLine.text(email: email))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal)
            .accessibilityIdentifier("home.signedIn")
    }
}

//
//  TeamMembers.swift
//  PitchMark
//
//  Team Members on the team roster (2026-11-22). The coach invites a
//  Scheduler (helps run the schedule - role "assistant", a single-use
//  link) or families (one reusable family link, role "parent"), sees who's
//  on the team, and removes anyone. Members see the team's tourneys live
//  in Tourney Info (TourneyStore.startTeams); Schedulers can edit them.
//
//  The rows are a List section; every sheet and dialog is attached at the
//  roster's root through `TeamMembersSheets` - a sheet on a List section is
//  copied onto every row (the Make a Trading Card bug).
//

import SwiftUI
import Combine
import FirebaseAuth

@MainActor
final class TeamMembersModel: ObservableObject {
    @Published var members: [TeamMembership] = []
    @Published var isWorking = false
    @Published var shareItems: ShareItems? = nil
    @Published var pendingRemoval: TeamMembership? = nil
    @Published var showRemoveDialog = false
    @Published var showResetDialog = false
    @Published var errorMessage: String? = nil
    @Published var showError = false

    struct ShareItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private(set) var team: Team? = nil

    func start(team: Team, authManager: AuthManager) {
        self.team = team
        reload(authManager)
    }

    func reload(_ authManager: AuthManager) {
        guard let teamId = team?.id else { return }
        authManager.loadTeamMembers(teamId: teamId) { [weak self] members in
            let me = authManager.user?.uid
            self?.members = members
                .filter { $0.uid != me }
                .sorted { TeamMembersModel.order($0, $1) }
        }
    }

    /// Schedulers first, then families, each by name.
    static func order(_ a: TeamMembership, _ b: TeamMembership) -> Bool {
        let ra = a.roles.contains(.assistant) ? 0 : 1, rb = b.roles.contains(.assistant) ? 0 : 1
        if ra != rb { return ra < rb }
        return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
    }

    func inviteScheduler(_ authManager: AuthManager) {
        guard let team, let teamId = team.id else { return }
        isWorking = true
        authManager.createTeamInviteToken(teamId: teamId, roles: [.assistant]) { [weak self] result in
            DispatchQueue.main.async {
                self?.isWorking = false
                switch result {
                case .success(let token):
                    self?.shareItems = ShareItems(items: [TeamInviteText.scheduler(team: team.name, token: token)])
                case .failure(let error):
                    self?.fail(error)
                }
            }
        }
    }

    func shareFamilyLink(_ authManager: AuthManager, reset: Bool = false) {
        guard let team else { return }
        isWorking = true
        authManager.familyInviteToken(for: team, reset: reset) { [weak self] result in
            DispatchQueue.main.async {
                self?.isWorking = false
                switch result {
                case .success(let token):
                    self?.team?.familyInviteToken = token
                    self?.shareItems = ShareItems(items: [TeamInviteText.families(team: team.name, token: token)])
                case .failure(let error):
                    self?.fail(error)
                }
            }
        }
    }

    func remove(_ member: TeamMembership, _ authManager: AuthManager) {
        guard let teamId = team?.id else { return }
        members.removeAll { $0.uid == member.uid }
        authManager.removeTeamMember(teamId: teamId, memberUid: member.uid) { [weak self] result in
            if case .failure(let error) = result {
                self?.fail(error)
                self?.reload(authManager)
            }
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

/// The text sent with an invite - the link, and the code for pasting.
enum TeamInviteText {
    static func scheduler(team: String, token: String) -> String {
        "Help me run \(team)'s schedule in PitchMark: \(TeamAccessRules.inviteLink(token).absoluteString)\n"
            + "Or in PitchMark: Tourney Info → Join a Team, code \(token). This link works once."
    }

    static func families(team: String, token: String) -> String {
        "See \(team)'s schedule in PitchMark - every tourney and game, kept up to date: "
            + "\(TeamAccessRules.inviteLink(token).absoluteString)\n"
            + "Or in PitchMark: Tourney Info → Join a Team, code \(token)."
    }
}

/// The roster's Team Members rows (creator only).
struct TeamMembersSection: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var model: TeamMembersModel

    var body: some View {
        Section {
            ForEach(model.members, id: \.uid) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name ?? "Team member")
                        Text(member.roleTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        model.pendingRemoval = member
                        model.showRemoveDialog = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("team.member.remove")
                }
                .accessibilityIdentifier("team.member")
            }
            Button {
                model.inviteScheduler(authManager)
            } label: {
                Label("Invite a Scheduler", systemImage: "person.badge.plus")
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("team.inviteScheduler")
            Button {
                model.shareFamilyLink(authManager)
            } label: {
                Label("Share Family Link", systemImage: "person.3")
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("team.familyLink")
            if model.team?.familyInviteToken != nil {
                Button("Reset Family Link", role: .destructive) {
                    model.showResetDialog = true
                }
                .disabled(model.isWorking)
            }
        } header: {
            Text("Team Members")
        } footer: {
            Text("Schedulers can add and change games in your team's tourneys. Families see the schedule. Removing someone ends their access right away.")
        }
    }
}

/// Team Members' sheets and dialogs, attached at the roster's root.
struct TeamMembersSheets: ViewModifier {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var model: TeamMembersModel

    func body(content: Content) -> some View {
        content
            .appSheet(item: $model.shareItems, chrome: .none) { share in
                ShareSheet(items: share.items)
            }
            .appConfirmationDialog(
                isPresented: $model.showRemoveDialog,
                title: "Remove \(model.pendingRemoval?.name ?? "this member")?",
                message: model.pendingRemoval?.roles.contains(.parent) == true
                    ? "They stop seeing the team's schedule. They could rejoin with the family link - reset it to stop that."
                    : "They stop seeing and editing the team's schedule.",
                primaryTitle: "Remove",
                primaryAction: {
                    if let member = model.pendingRemoval { model.remove(member, authManager) }
                    model.pendingRemoval = nil
                },
                secondaryTitle: "Cancel",
                secondaryAction: { model.pendingRemoval = nil }
            )
            .appConfirmationDialog(
                isPresented: $model.showResetDialog,
                title: "Reset the family link?",
                message: "The old link and code stop working. Families already on the team stay on it.",
                primaryTitle: "Reset",
                primaryAction: { model.shareFamilyLink(authManager, reset: true) },
                secondaryTitle: "Cancel",
                secondaryAction: {}
            )
            .appConfirmationDialog(
                isPresented: $model.showError,
                title: "Something went wrong",
                message: model.errorMessage ?? "",
                primaryTitle: "OK",
                primaryAction: {},
                secondaryTitle: "Cancel",
                secondaryAction: {}
            )
    }
}

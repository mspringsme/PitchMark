//
//  ParentGameShell.swift
//  PitchMark
//
//  Phase 3 of the 2026-09-24 Coach/Parent/Family direction: select a child
//  on a team, choose Pitching or Batting, and land on a tracking area.
//  Tracking content is a placeholder here - Phase 4/5 build the real
//  pitching/batting UI. Deliberately kept out of the Pitchmark Display
//  target's membershipExceptions; Display has no use for this UI.
//

import SwiftUI

enum ParentTrackingMode: String, CaseIterable {
    case pitching
    case batting

    var displayName: String {
        switch self {
        case .pitching: return "Pitching"
        case .batting: return "Batting"
        }
    }
}

struct TeamEntrySelection: Identifiable {
    let team: Team
    let membership: TeamMembership
    var id: String { team.id ?? UUID().uuidString }
}

struct ParentGameShellView: View {
    let selection: TeamEntrySelection

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var players: [TeamPlayer] = []
    @State private var selectedPlayerId: String? = nil
    @State private var selectedMode: ParentTrackingMode = .pitching
    @State private var visitedPitchingPlayerIds: Set<String> = []

    @State private var newPlayerName: String = ""
    @State private var newPlayerJersey: String = ""

    @State private var showMomentsSheet = false
    @State private var showFamilySheet = false

    private var isCoach: Bool { selection.membership.roles.contains(.coach) }
    private var selectedPlayer: TeamPlayer? {
        players.first(where: { $0.id == selectedPlayerId })
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rosterSection

                    if isCoach {
                        addPlayerSection
                    }

                    if let player = selectedPlayer {
                        trackingSection(for: player)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal)
            }
            .navigationTitle(selection.team.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            showMomentsSheet = true
                        } label: {
                            Image(systemName: "video.fill")
                        }
                        .accessibilityLabel("Moment")

                        Button {
                            showFamilySheet = true
                        } label: {
                            Image(systemName: "person.2.fill")
                        }
                        .accessibilityLabel("Family")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showMomentsSheet) {
                ComingSoonSheetView(
                    area: .moments,
                    title: "Moments",
                    systemImage: "video.fill",
                    message: "Capture and relive the season's best plays. Coming soon."
                )
            }
            .sheet(isPresented: $showFamilySheet) {
                ComingSoonSheetView(
                    area: .family,
                    title: "Family",
                    systemImage: "person.2.fill",
                    message: "Keep family up to date and connected. Coming soon."
                )
            }
        }
        .onAppear {
            refreshPlayers()
        }
    }

    @ViewBuilder
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Roster")
                .font(.headline)

            if players.isEmpty {
                Text(isCoach ? "No players yet - add your first one below." : "No players on this roster yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(players, id: \.id) { player in
                        Button {
                            selectedPlayerId = player.id
                        } label: {
                            HStack {
                                Text(player.name)
                                    .font(.subheadline.weight(.semibold))
                                if let jersey = player.jerseyNumber, !jersey.isEmpty {
                                    Text("#\(jersey)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if player.id == selectedPlayerId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addPlayerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Player")
                .font(.headline)
            HStack {
                TextField("Name", text: $newPlayerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Jersey #", text: $newPlayerJersey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Add") {
                    addPlayer()
                }
                .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func trackingSection(for player: TeamPlayer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(ParentTrackingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if selectedMode == .pitching {
                pitchingTrackers
            } else {
                battingPlaceholder(for: player)
            }
        }
        .onChange(of: selectedPlayerId) { _, id in
            if selectedMode == .pitching, let id { visitedPitchingPlayerIds.insert(id) }
        }
        .onChange(of: selectedMode) { _, mode in
            if mode == .pitching, let id = selectedPlayerId { visitedPitchingPlayerIds.insert(id) }
        }
        .onAppear {
            if selectedMode == .pitching, let id = selectedPlayerId { visitedPitchingPlayerIds.insert(id) }
        }
    }

    /// Every player visited in Pitching mode so far stays mounted, just
    /// hidden - not conditionally removed from the view tree - so each
    /// `ParentPitchingTrackerView` instance's @State (current count, last
    /// tap, etc.) survives switching to a different child and back. A
    /// SwiftUI `.id()` here would do the opposite: force teardown/recreate
    /// on every switch. Batting has no real state yet, so its placeholder
    /// doesn't need this treatment.
    @ViewBuilder
    private var pitchingTrackers: some View {
        ZStack {
            ForEach(players.filter { visitedPitchingPlayerIds.contains($0.id ?? "") }, id: \.id) { player in
                let isCurrent = player.id == selectedPlayerId
                ParentPitchingTrackerView(player: player, teamId: selection.team.id ?? "")
                    .opacity(isCurrent ? 1 : 0)
                    .allowsHitTesting(isCurrent)
            }
        }
    }

    @ViewBuilder
    private func battingPlaceholder(for player: TeamPlayer) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.softball")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(player.name)'s batting tracker is coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func refreshPlayers() {
        guard let teamId = selection.team.id else { return }
        authManager.loadTeamPlayers(teamId: teamId) { loaded in
            players = loaded
        }
    }

    private func addPlayer() {
        guard let teamId = selection.team.id else { return }
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        let jersey = newPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.addTeamPlayer(teamId: teamId, name: name, jerseyNumber: jersey.isEmpty ? nil : jersey, pitcherId: nil) { result in
            if case .success = result {
                newPlayerName = ""
                newPlayerJersey = ""
                refreshPlayers()
            }
        }
    }
}

//
//  SettingsView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//

import SwiftUI
import FirebaseAuth
import UIKit
import CoreImage
import FirebaseFirestore
import AVFoundation

struct PitcherPitchStats: Codable {
    var count: Int
    var hitSpotCount: Int
}

private struct SettingsGameSummarySheetView: View {
    let pitcherName: String
    let game: Game
    let events: [PitchEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    private var stats: PitchStatsSnapshot {
        PitchStatsCalculator.snapshot(for: events)
    }

    private var totalPitches: Int { stats.totalPitches }
    private var strikes: Int { stats.strikePitches }
    private var balls: Int { stats.ballPitches }
    private var hitSpots: Int { stats.hitSpotPitches }
    private var strikeLooking: Int { stats.strikeLookingCount }
    private var strikeSwinging: Int { stats.strikeSwingingCount }
    private var foulCount: Int { stats.foulCount }
    private var walks: Int { stats.walkCount }
    private var hits: Int { stats.hitCount }
    private var wildPitches: Int { stats.wildPitchCount }
    private var passedBalls: Int { stats.passedBallCount }
    private var pitchBreakdown: [(name: String, count: Int)] { stats.pitchBreakdown }

    private var outcomeBreakdown: [(name: String, count: Int)] { stats.outcomeBreakdown }

    private var heatmapsByPitch: [(pitch: String, events: [PitchEvent])] {
        Dictionary(grouping: events.filter(\.supportsLocationAnalytics), by: { $0.pitch.isEmpty ? "-" : $0.pitch })
            .map { key, value in
                (pitch: key, events: value.sorted { $0.timestamp < $1.timestamp })
            }
            .sorted { lhs, rhs in
                if lhs.events.count == rhs.events.count { return lhs.pitch < rhs.pitch }
                return lhs.events.count > rhs.events.count
            }
    }

    private var hasLocationAnalytics: Bool { stats.hasLocationAnalytics }

    private var locationAnalyticsEligibleCount: Int { stats.locationAnalyticsEligibleCount }

    private var firstPitchStrike: (made: Int, total: Int) { stats.firstPitchStrike }

    private func percent(_ part: Int, _ total: Int) -> String {
        guard total > 0 else { return "0%" }
        let value = (Double(part) / Double(total)) * 100.0
        return String(format: "%.0f%%", value.rounded())
    }

    private var shareText: String {
        let pitchLines = pitchBreakdown.isEmpty ? "None" : pitchBreakdown.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        let outcomeLines = outcomeBreakdown.isEmpty ? "None" : outcomeBreakdown.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        let hitSpotLine = hasLocationAnalytics
            ? "Hit Spot: \(hitSpots) of \(locationAnalyticsEligibleCount) (\(percent(hitSpots, locationAnalyticsEligibleCount)))"
            : "Hit Spot: Hidden for Track Game pitches"
        let firstPitchStrikeLine = "1st Pitch Strike: \(firstPitchStrike.total == 0 ? "0%" : percent(firstPitchStrike.made, firstPitchStrike.total)) (\(firstPitchStrike.made)/\(firstPitchStrike.total))"
        let hitSpotDefinition = hasLocationAnalytics
            ? "Hit Spot % = Location matches / Coach-mode pitches"
            : "Location-based metrics hidden for Track Game pitches."
        let foulPercentLine = "Foul % = Foul pitches / Total pitches"
        return """
        PitchMark Game Summary
        Pitcher: \(pitcherName)
        Opponent: \(game.opponent)
        Date: \(game.date.formatted(date: .abbreviated, time: .omitted))

        Pitches: \(totalPitches)
        Strikes: \(strikes) of \(totalPitches) (\(percent(strikes, totalPitches)))
        Balls: \(balls) of \(totalPitches) (\(percent(balls, totalPitches)))
        \(firstPitchStrikeLine)
        \(hitSpotLine)
        Foul %: \(percent(foulCount, totalPitches)) (\(foulCount)/\(totalPitches))

        Strike Looking: \(strikeLooking)
        Strike Swinging: \(strikeSwinging)
        Foul: \(foulCount)
        Walks: \(walks)
        Hits: \(hits)
        Wild Pitches: \(wildPitches)
        Passed Balls: \(passedBalls)

        Metric Definitions:
        Strike % = Strikes / Total Pitches
        Ball % = Balls / Total Pitches
        \(hitSpotDefinition)
        \(foulPercentLine)

        Pitch Breakdown: \(pitchLines)
        Outcome Breakdown: \(outcomeLines)
        """
    }

    @ViewBuilder
    private var summaryContentWithoutHeatmaps: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pitcherName)
                    .font(.title3.weight(.semibold))
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Group {
                summaryRow("Total Pitches", "\(totalPitches)")
                summaryRow("Strike %", "\(percent(strikes, totalPitches)) (\(strikes)/\(totalPitches))")
                summaryRow("Ball %", "\(percent(balls, totalPitches)) (\(balls)/\(totalPitches))")
                summaryRow("1st Pitch Strike", "\(firstPitchStrike.total == 0 ? "0%" : percent(firstPitchStrike.made, firstPitchStrike.total)) (\(firstPitchStrike.made)/\(firstPitchStrike.total))")
                if hasLocationAnalytics {
                    summaryRow("Hit Spot %", "\(percent(hitSpots, totalPitches)) (\(hitSpots)/\(totalPitches))")
                }
                summaryRow("Foul %", "\(percent(foulCount, totalPitches)) (\(foulCount)/\(totalPitches))")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes / Total Pitches")
                Text("Ball % = Balls / Total Pitches")
                Text("1st Pitch Strike % = Qualified first-pitch strikes / New batter appearances")
                if hasLocationAnalytics {
                    Text("Hit Spot % = Location matches / Coach-mode pitches")
                } else {
                    Text("Location-based metrics hidden for Track Game pitches.")
                }
                Text("Foul % = Foul pitches / Total pitches")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Group {
                summaryRow("Strike Looking", "\(strikeLooking)")
                summaryRow("Strike Swinging", "\(strikeSwinging)")
                summaryRow("Foul", "\(foulCount)")
                summaryRow("Walks", "\(walks)")
                summaryRow("Hits", "\(hits)")
                summaryRow("Wild Pitches", "\(wildPitches)")
                summaryRow("Passed Balls", "\(passedBalls)")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Pitch Breakdown")
                    .font(.headline)
                if pitchBreakdown.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(pitchBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryRow(item.name, "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Outcome Breakdown")
                    .font(.headline)
                if outcomeBreakdown.isEmpty {
                    Text("No outcomes recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(outcomeBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryRow(item.name, "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func printableHeatmapPage(for item: (pitch: String, events: [PitchEvent]), pageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(item.pitch) (\(item.events.count))")
                .font(.title3.weight(.semibold))
            HStack {
                Spacer()
                StrikeZoneHeatmapView(
                    events: item.events,
                    showLegend: false
                )
                .frame(width: 380, height: 312)
                Spacer()
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes:")
                    .font(.headline)
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: pageHeight, alignment: .top)
    }

    @MainActor
    private func renderedPrintableImage<Content: View>(for content: Content, width: CGFloat) -> UIImage? {
        let printableContent = content
            .padding()
            .frame(width: width)
            .background(Color.white)
        let imageRenderer = ImageRenderer(content: printableContent)
        imageRenderer.scale = 2
        return imageRenderer.uiImage
    }

    @ViewBuilder
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pitcherName)
                    .font(.title3.weight(.semibold))
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Group {
                summaryRow("Total Pitches", "\(totalPitches)")
                summaryRow("Strike %", "\(percent(strikes, totalPitches)) (\(strikes)/\(totalPitches))")
                summaryRow("Ball %", "\(percent(balls, totalPitches)) (\(balls)/\(totalPitches))")
                summaryRow("1st Pitch Strike", "\(firstPitchStrike.total == 0 ? "0%" : percent(firstPitchStrike.made, firstPitchStrike.total)) (\(firstPitchStrike.made)/\(firstPitchStrike.total))")
                if hasLocationAnalytics {
                    summaryRow("Hit Spot %", "\(percent(hitSpots, totalPitches)) (\(hitSpots)/\(totalPitches))")
                }
                summaryRow("Foul %", "\(percent(foulCount, totalPitches)) (\(foulCount)/\(totalPitches))")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes / Total Pitches")
                Text("Ball % = Balls / Total Pitches")
                Text("1st Pitch Strike % = Qualified first-pitch strikes / New batter appearances")
                if hasLocationAnalytics {
                    Text("Hit Spot % = Location matches / Coach-mode pitches")
                } else {
                    Text("Location-based metrics hidden for Track Game pitches.")
                }
                Text("Foul % = Foul pitches / Total pitches")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Group {
                summaryRow("Strike Looking", "\(strikeLooking)")
                summaryRow("Strike Swinging", "\(strikeSwinging)")
                summaryRow("Foul", "\(foulCount)")
                summaryRow("Walks", "\(walks)")
                summaryRow("Hits", "\(hits)")
                summaryRow("Wild Pitches", "\(wildPitches)")
                summaryRow("Passed Balls", "\(passedBalls)")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Pitch Breakdown")
                    .font(.headline)
                if pitchBreakdown.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(pitchBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryRow(item.name, "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Outcome Breakdown")
                    .font(.headline)
                if outcomeBreakdown.isEmpty {
                    Text("No outcomes recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(outcomeBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryRow(item.name, "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Heat Maps By Pitch")
                    .font(.headline)
                if !hasLocationAnalytics {
                    Text("Heat maps hidden for Track Game pitches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if heatmapsByPitch.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(heatmapsByPitch, id: \.pitch) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("\(item.pitch) (\(item.events.count))")
                                    .font(.subheadline.weight(.semibold))
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.35))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 16)

                            StrikeZoneHeatmapView(
                                events: item.events,
                                showLegend: false
                            )
                            .padding(.bottom, 28)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor
    private func printSummary() {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let contentRect = pageRect.insetBy(dx: 24, dy: 36)
        var printableImages: [UIImage] = []
        if let summaryImage = renderedPrintableImage(for: summaryContentWithoutHeatmaps, width: contentRect.width) {
            printableImages.append(summaryImage)
        }
        for item in heatmapsByPitch {
            if let heatmapImage = renderedPrintableImage(for: printableHeatmapPage(for: item, pageHeight: contentRect.height), width: contentRect.width) {
                printableImages.append(heatmapImage)
            }
        }
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = pdfRenderer.pdfData { context in
            func drawPaginatedImage(_ image: UIImage) {
                guard let cgImage = image.cgImage else { return }
                let scale = image.scale
                let totalHeightPoints = image.size.height
                var offsetYPoints: CGFloat = 0

                while offsetYPoints < totalHeightPoints {
                    context.beginPage()
                    let remainingHeight = totalHeightPoints - offsetYPoints
                    let sliceHeightPoints = min(contentRect.height, remainingHeight)
                    let cropRect = CGRect(
                        x: 0,
                        y: offsetYPoints * scale,
                        width: CGFloat(cgImage.width),
                        height: sliceHeightPoints * scale
                    ).integral

                    if let cropped = cgImage.cropping(to: cropRect) {
                        let sliceImage = UIImage(cgImage: cropped, scale: scale, orientation: .up)
                        sliceImage.draw(
                            in: CGRect(
                                x: contentRect.minX,
                                y: contentRect.minY,
                                width: contentRect.width,
                                height: sliceHeightPoints
                            )
                        )
                    }

                    offsetYPoints += sliceHeightPoints
                }
            }

            for image in printableImages {
                drawPaginatedImage(image)
            }
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = "PitchMark Game Summary"
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = pdfData
        controller.present(animated: true, completionHandler: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                summaryContent
                    .padding()
            }
            .navigationTitle("Game Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        printSummary()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .disabled(totalPitches == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(totalPitches == 0)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareText])
                    .fixedAppDynamicType()
            }
        }
        .fixedAppDynamicType()
    }

    @ViewBuilder
    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}

struct PitcherOutcomeStats: Codable {
    var count: Int
    var jerseys: [String]
}

struct PitcherLocationStats: Codable {
    var count: Int
    var hitCount: Int
    var missCount: Int
    var jerseys: [String]
}

struct PitcherStatsDoc: Codable {
    var pitcherId: String
    var scope: String
    var scopeId: String
    var updatedAt: Date?
    var totalCount: Int
    var strikeCount: Int
    var ballCount: Int
    var swingingStrikeCount: Int
    var lookingStrikeCount: Int
    var wildPitchCount: Int
    var passedBallCount: Int
    var walkCount: Int
    var hitSpotCount: Int
    var pitchStats: [String: PitcherPitchStats]
    var outcomeStats: [String: PitcherOutcomeStats]
    var pitchLocationStats: [String: PitcherLocationStats]
}

struct SettingsView: View {
    private let privacyPolicyURL = URL(string: "https://pitchmark.app/privacy")
    private let termsOfUseURL = URL(string: "https://pitchmark.app/terms")

    @Binding var templates: [PitchTemplate]
    @Binding var games: [Game]
    @Binding var joinedLiveSessions: [JoinedLiveSession]
    @Binding var pitchers: [Pitcher]
    let allPitches: [String]
    @Binding var selectedTemplate: PitchTemplate? // ✅ Add this line
    @Binding var codeShareInitialTab: Int
    @Binding var showCodeShareSheet: Bool
    @Binding var shareCode: String
    @Binding var codeShareSheetID: UUID
    @Binding var showCodeShareModePicker: Bool
    var onSwitchToArea: ((HomeArea) -> Void)? = nil

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showSignOutConfirmation = false
    @State private var showChangeEmailSheet = false
    @State private var changeEmailText: String = ""
    @State private var changeEmailError: String? = nil
    @State private var changeEmailStatus: String? = nil
    @State private var isChangingEmail = false
    @State private var requiresRecentLogin = false
    @State private var showDeleteAccountSheet = false
    @State private var deleteAccountText: String = ""
    @State private var deleteAccountError: String? = nil
    @State private var isDeletingAccount = false
    @State private var requiresDeleteRecentLogin = false
    @FocusState private var isDeleteConfirmationFocused: Bool
    @State private var showAccountActionsSheet = false
    @State private var showLearnPitchMark = false
    @State private var showSoundCreditsSheet = false
    @State private var activeGameIdValue: String? = nil
    @State private var showMoreAccountActionsSheet = false
    @State private var showFinalDeleteAccountConfirmation = false
    @State private var templatePendingDeletion: PitchTemplate?
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var myTeams: [(team: Team, membership: TeamMembership)] = []
    @State private var selectedTeamEntry: TeamEntrySelection? = nil
    @State private var newTeamNameForHome: String = ""
    // Creating a team is an inline form now (same shape as the Games
    // section's), because the four mandatory designation pickers no longer
    // fit the one-line name field + button it used to be.
    @State private var showInlineNewTeam = false
    @State private var newTeamDesignation = TeamDesignationDraft()
    @State private var createTeamError: String? = nil

    // Home's Players section - the pitcher roster that used to live inside
    // the gear/Settings sheet, plus every non-pitching roster player under
    // the "All" scope.
    // The row model, row view, scope, filter and loader all live in
    // PlayerDirectory.swift - the pitcher picker and "Link Existing Player"
    // render the same rows from the same code.
    @State private var playersScope: PlayerDirectoryScope = .pitchers
    @State private var showPlayersFilterSheet = false
    @State private var showLinkProfiles = false
    /// Set by tapping a team row's circle; drives `teamImageEditor`.
    @State private var teamImageEditTarget: Team? = nil
    /// Canonical `Player` docs - the Players rows need them to fold in
    /// records a Link Profiles link attached through the Player doc alone.
    @State private var myPlayers: [Player] = []
    @State private var playerFilter = PlayerDirectoryFilter()
    @State private var rosterEntries: [PlayerRosterEntry] = []
    @State private var myHitters: [Hitter] = []
    @State private var statsHitter: Hitter? = nil
    @State private var isRefreshingPlayers = false
    // Creating, archiving and deleting games all happen inline in Home's
    // Games section now. The old route was a separate GameSelectionSheet,
    // which put a sheet (the new-game card) inside a sheet (the chooser)
    // inside a tab - the presentation nesting behind several rounds of
    // "tapped the new game and nothing happened" bugs.
    @State private var showInlineNewGame = false
    @State private var inlineNewGameName: String = ""
    @State private var inlineNewGameDate: Date = Date()
    @State private var inlineNewGameTrackingMode: TrackingMode = .coach
    @State private var inlineNewGameTeamId: String? = nil
    @State private var inlineNewGameOpponentTeamId: String? = nil
    @State private var createGameError: String? = nil
    @State private var showArchivedGames = false
    @State private var showGamesCalendar = false
    // Scan Opponent Lineup (LineupScanHome.swift / LineupScanSheet.swift).
    @State private var lineupScan: LineupScanContext? = nil
    @State private var showLineupScan = false
    @State private var lineupScanRoster: [TeamPlayer]? = nil
    @State private var pendingNewGameLineup: PendingNewGameLineup? = nil
    @State private var isAddingScannedLineup = false
    @State private var lineupScanNotice: String? = nil
    @State private var pendingLiveLeave: HomeLiveLeave? = nil
    /// Home's Players + (HomeAddPlayerSheet). The old name-only sheet
    /// (`showAddPitcher`) is only Edit now.
    @State private var showHomeAddPlayer = false
    @State private var showArchivedTeams = false
    @State private var pendingArchiveGame: Game? = nil
    /// Set when an archive was refused because the player is on a team in
    /// the open game (`OpenGameLock`); drives that explanation dialog.
    @State private var openGameLockMessage: String? = nil
    /// A player archive waiting on its confirmation, which names everyone
    /// it would hide (`ArchiveScope`).
    @State private var pendingPlayerArchive: PendingPlayerArchive? = nil
    // Accordion: expanding one of Home's two collapsible sections closes
    // the other. nil means both collapsed; .games is the default open one.
    @State private var expandedHomeOverviewSection: HomeOverviewSection? = .games
    @State private var editorTemplate: PitchTemplate? = nil
    @State private var showAddPitcher = false
    @State private var newPitcherName: String = ""
    @State private var editingPitcher: Pitcher? = nil
    @State private var showPitcherPhotoPicker = false
    @State private var pitcherPortraitTarget: Pitcher? = nil
    @State private var pitcherPortraitSourceImage: UIImage? = nil
    @State private var showPitcherPortraitEditor = false
    @State private var pitcherImageErrorMessage: String = ""
    @State private var showPitcherImageError = false

    @State private var templatePendingShare: PitchTemplate? = nil
    @State private var showShareTemplateSheet = false
    @State private var shareTargetEmail: String = ""
    @State private var shareTemplateError: String = ""
    @State private var isSharingTemplate = false
    @State private var purchasedTemplateEditTarget: PitchTemplate? = nil
    @State private var showPurchasedTemplateEditAlert = false
    @State private var isCheckingPurchasedTemplate = false
    @State private var isRefreshingTemplates = false
    @State private var hiddenTemplateIds: Set<String> = []
    /// Archived players, synced per account (was device-local).
    private var hiddenPitcherIds: Set<String> { authManager.archivedPitcherIds }
    @State private var templateActionTargetId: UUID? = nil
    @State private var pitcherActionTargetId: String? = nil
    @State private var showHiddenTemplates = false
    @State private var statsPitcher: Pitcher? = nil
    /// The row's full set of records - see `PlayerDirectoryRow.pitcherIds`.
    @State private var statsPitcherIds: [String] = []
    @State private var statsHitterIds: [String] = []
    /// Only the teams this player is on - the stats sheets' Teams filter
    /// row lists exactly these.
    @State private var statsTeams: [Team] = []

    @State private var showInviteJoinSheet = false
    @State private var inviteJoinText: String = ""
    @State private var inviteJoinError: String? = nil
    @State private var showProPaywall = false
    @State private var showProGateAlert = false
    @State private var proGateMessage: String = ""
    @State private var isJoiningInvite = false
    @State private var showQRScanner = false
    @State private var showCameraUnavailableAlert = false
    @State private var showCameraPermissionAlert = false

    private static let quickLaunchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Muted tints that tell Home's three main cards apart at a glance.
    /// Translucent, so they sit on either appearance.
    enum HomeCardTint {
        case neutral, games, teams, players

        var fill: Color {
            switch self {
            case .neutral: return Color.black.opacity(0.04)
            case .games: return Color(red: 0.45, green: 0.62, blue: 0.50).opacity(0.16)   // sage
            case .teams: return Color(red: 0.42, green: 0.53, blue: 0.70).opacity(0.16)   // slate blue
            case .players: return Color(red: 0.80, green: 0.62, blue: 0.45).opacity(0.18) // sand
            }
        }

        var stroke: Color {
            switch self {
            case .neutral: return Color.black.opacity(0.08)
            case .games: return Color(red: 0.45, green: 0.62, blue: 0.50).opacity(0.35)
            case .teams: return Color(red: 0.42, green: 0.53, blue: 0.70).opacity(0.35)
            case .players: return Color(red: 0.80, green: 0.62, blue: 0.45).opacity(0.40)
            }
        }
    }

    private func sectionCard<Content: View>(tint: HomeCardTint = .neutral, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.stroke, lineWidth: 1)
            )
            .padding(.horizontal)
    }

    @State private var copyPitcherTarget: Pitcher? = nil
    @State private var showCopyPitcherConfirm = false

    @State private var revokePitcherTarget: Pitcher? = nil
    @State private var showRevokePitcherConfirm = false
    @State private var isRevokingPitcherSharing = false

    @State private var encryptedSelectionByGameId: [String: Bool] = [:]

    @State private var showPitcherShareSheet = false
    @State private var showPitcherShareActivity = false
    @State private var sharePitcherLink: String = ""
    @State private var sharePitcherQR: UIImage? = nil
    @State private var isGeneratingPitcherShare = false
    @State private var pitcherShareError: String? = nil
    @State private var showPitcherShareError = false
    @State private var isCopyingPitcher = false
    @State private var ownedPitchersListener: ListenerRegistration? = nil
    @State private var sharedPitchersListener: ListenerRegistration? = nil
    @State private var livePitchersById: [String: Pitcher] = [:]
    
    private var sortedTemplates: [PitchTemplate] {
        templates.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var sortedPitchers: [Pitcher] {
        var seenIds: Set<String> = []
        let deduped = pitchers.filter { pitcher in
            if let id = pitcher.id {
                if seenIds.contains(id) { return false }
                seenIds.insert(id)
            }
            return true
        }
        return deduped.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func isTemplateEditable(_ template: PitchTemplate) -> Bool {
        guard let currentUid = authManager.user?.uid else { return false }
        if let owner = template.ownerUid {
            return owner == currentUid
        }
        return true
    }
    
    private func showDeleteConfirmation(for template: PitchTemplate) {
        templatePendingDeletion = template
        showDeleteAlert = true
    }

    private func confirmDeleteTemplate() {
        guard let template = templatePendingDeletion else { return }
        authManager.deleteTemplate(template)
        templates.removeAll { $0.id == template.id }
        templatePendingDeletion = nil
    }

    private func beginShareTemplate(_ template: PitchTemplate) {
        templatePendingShare = template
        shareTargetEmail = ""
        shareTemplateError = ""
        showShareTemplateSheet = true
    }

    private func loadHiddenIds() {
        hiddenTemplateIds = Set(UserDefaults.standard.stringArray(forKey: PitchTrackerView.DefaultsKeys.hiddenTemplateIds) ?? [])
    }

    private func saveHiddenTemplateIds() {
        UserDefaults.standard.set(Array(hiddenTemplateIds), forKey: PitchTrackerView.DefaultsKeys.hiddenTemplateIds)
    }

    private var visibleTemplates: [PitchTemplate] {
        sortedTemplates.filter { !hiddenTemplateIds.contains($0.id.uuidString) }
    }

    private var hiddenTemplates: [PitchTemplate] {
        sortedTemplates.filter { hiddenTemplateIds.contains($0.id.uuidString) }
    }

    // visiblePitchers/hiddenPitchers used to split the Settings-sheet
    // pitcher strip in two. Home's Players section filters its own rows
    // instead (passesPlayerFilters), so both are gone.

    private func joinByCodeFromSettings() {
        // set the tab first
        showCodeShareModePicker = false
        codeShareInitialTab = 1
        shareCode = ""
        codeShareSheetID = UUID()

        // switch to Games, then present after a small delay
        onSwitchToArea?(.games)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showCodeShareSheet = true
        }
    }

    private func inviteToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }

        if trimmed.contains("://") { return nil }
        return trimmed
    }

    private func joinLiveGameFromInvite() {
        inviteJoinError = nil

        if !subscriptionManager.isPro {
            showProPaywall = true
            return
        }

        guard let token = inviteToken(from: inviteJoinText) else {
            inviteJoinError = "Paste a valid invite link."
            return
        }

        isJoiningInvite = true
        LiveGameService.shared.joinLiveGameByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                self.isJoiningInvite = false

                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "type": "liveGame",
                            "liveId": liveId
                        ]
                    )
                    self.inviteJoinText = ""
                    self.showInviteJoinSheet = false
                    self.onSwitchToArea?(.games)

                case .failure(let err):
                    self.inviteJoinError = err.localizedDescription
                }
            }
        }
    }

    private func openCameraForJoin() {
        if showInviteJoinSheet {
            showInviteJoinSheet = false
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraUnavailableAlert = true
            }
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            presentCameraFromJoin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        presentCameraFromJoin()
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        @unknown default:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        }
    }

    private func presentCameraFromJoin() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showQRScanner = true
        }
    }

    private func launchGame(_ game: Game) {
        guard let gameId = game.id else { return }
        let ownerUid = authManager.user?.uid ?? ""

        let defaults = UserDefaults.standard
        defaults.set(gameId, forKey: PitchTrackerView.DefaultsKeys.activeGameId)
        defaults.set(ownerUid, forKey: PitchTrackerView.DefaultsKeys.activeGameOwnerUserId)
        defaults.set("tracker", forKey: PitchTrackerView.DefaultsKeys.lastView)
        refreshActiveGameId()

        onSwitchToArea?(.games)
        // The Games tab has to be the one on screen before this lands: the
        // handler presents a sheet, and asking a tab that is still
        // mid-switch to present one gets the presentation dropped. 0.05s
        // was too tight to cover a real tab transition - and it mattered
        // most after an idle return, which forces the Home tab, so every
        // tap from then on needed a switch first. Two hops to the next
        // runloop plus a full transition's worth of delay is still
        // imperceptible but no longer lands mid-animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "game",
                    "gameId": gameId,
                    "ownerUserId": ownerUid
                ]
            )
        }
    }

    private func quickLaunchDateCaption(for game: Game) -> String {
        Self.quickLaunchDateFormatter.string(from: game.date)
    }

    private func quickLaunchId(for game: Game) -> String {
        if let id = game.id, !id.isEmpty { return id }
        return "\(game.opponent)|\(game.date.timeIntervalSince1970)"
    }

    /// "Reds 14U B vs. Hawks 15U A" - both sides with their class, so two
    /// games against same-named teams in different classes can be told
    /// apart. Falls back to the stored opponent text for whichever side
    /// isn't one of my teams (or a game created before teams were linked).
    private func matchupTitle(for game: Game) -> String {
        func team(_ id: String?) -> Team? {
            guard let id, !id.isEmpty else { return nil }
            return myTeams.first(where: { $0.team.id == id })?.team
        }
        let away = team(game.awayTeamId)?.nameWithClass ?? game.opponent
        guard let home = team(game.teamId) else { return away }
        return away.isEmpty ? home.nameWithClass : "\(home.nameWithClass) vs. \(away)"
    }

    private struct QuickLaunchGame: Identifiable {
        let id: String
        let game: Game
    }

    /// One full-width row for either a joined live session or a quick-launch
    /// game. Vertical (not the old horizontal scroll strip) deliberately
    /// leaves room to the right of the name/date for future per-game
    /// metadata (score, record, etc.) without needing another redesign.
    /// `menuGame` adds the per-game Archive menu. Live-session rows pass
    /// nil: a joined session isn't ours to archive.
    ///
    /// Returns `AnyView` on purpose. This row is used by three `ForEach`es
    /// in `gamesOverviewSection`, and its concrete type (Button + Menu +
    /// conditionals) was spelled out inside each - Home's body type got so
    /// deep that the Swift runtime overflowed the stack demangling it
    /// (`EXC_BAD_ACCESS code=2` in `decodeMangledType`, 2026-10-27, tapping
    /// Home from a game). Erasing here keeps each ForEach's type shallow.
    private func gameRow(
        opponent: String,
        dateText: String?,
        isLive: Bool,
        menuGame: Game? = nil,
        scanAction: (() -> Void)? = nil,
        disconnectAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> AnyView {
        AnyView(HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 10) {
                    if isLive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponent)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        if let dateText {
                            Text(dateText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let menuGame, menuGame.isArchived {
                        Label("Archived", systemImage: "archivebox")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isLive ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let menuGame {
                Menu {
                    if menuGame.isArchived {
                        Button {
                            guard let id = menuGame.id, !id.isEmpty else { return }
                            authManager.unarchiveGame(gameId: id)
                            if let idx = games.firstIndex(where: { $0.id == id }) {
                                games[idx].archivedAt = nil
                            }
                        } label: {
                            Label("Unarchive Game", systemImage: "archivebox")
                        }
                        archivedGameStatsToggle(menuGame)
                    } else {
                        lineupScanMenuItem(menuGame)
                        Button {
                            guard !(menuGame.id ?? "").isEmpty else { return }
                            pendingArchiveGame = menuGame
                        } label: {
                            Label("Archive Game…", systemImage: "archivebox")
                        }
                    }

                    // Games are never deleted (archive instead - see
                    // archiveGameDialog). Close Game takes the open one out
                    // of in-use status.
                    if isActiveGame(menuGame) {
                        Button {
                            closeActiveGame(menuGame)
                        } label: {
                            Label("Close Game (in use)", systemImage: "xmark.circle")
                        }
                        Button(role: .destructive) {
                            beginEndLiveSession(menuGame)
                        } label: {
                            Label("End Live Session…", systemImage: "antenna.radiowaves.left.and.right.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let scanAction {
                // A joined live game: a partner can scan the opponent's
                // lineup into the room.
                Menu {
                    Button(action: scanAction) {
                        Label("Scan Opponent Lineup…", systemImage: "text.viewfinder")
                    }
                    if let disconnectAction {
                        Button(role: .destructive, action: disconnectAction) {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        })
    }

    // MARK: Scan Opponent Lineup

    /// The own-game menu item. A game with no opponent team picks one
    /// first (teams created from Home's Teams card or the new-game card).
    private func lineupScanMenuItem(_ game: Game) -> AnyView {
        if let awayId = game.awayTeamId, !awayId.isEmpty {
            return AnyView(Button {
                beginGameLineupScan(game, teamId: awayId)
            } label: {
                Label("Scan Opponent Lineup…", systemImage: "text.viewfinder")
            })
        }
        let candidates = activeTeamEntries.map(\.team).filter { $0.id != nil && $0.id != game.teamId }
        return AnyView(Menu {
            if candidates.isEmpty {
                Text("Add the opponent as a team first")
            }
            ForEach(candidates, id: \.id) { team in
                Button(team.nameWithClass) { setOpponentThenScan(game, team: team) }
            }
        } label: {
            Label("Scan Opponent Lineup…", systemImage: "text.viewfinder")
        })
    }

    // MARK: Leaving a live game

    /// The in-use game's room, looked up on tap (Home doesn't track it).
    private func beginEndLiveSession(_ game: Game) {
        guard let gameId = game.id, let uid = authManager.user?.uid else { return }
        authManager.findOpenLiveRoom(ownerUid: uid, gameId: gameId) { liveId in
            guard let liveId else {
                lineupScanNotice = "No live session is running for \(matchupTitle(for: game))."
                return
            }
            pendingLiveLeave = .endSession(liveId: liveId, title: matchupTitle(for: game))
        }
    }

    private func confirmLiveLeave(_ leave: HomeLiveLeave) {
        switch leave {
        case .disconnect(let session):
            joinedLiveSessions.removeAll { $0.liveId == session.liveId }
            LiveGameService.shared.removeJoinedLiveSession(liveId: session.liveId)
            LiveGameService.shared.leaveLiveRoom(liveId: session.liveId)
            OpponentPartnerAccess.shared.clear(liveId: session.liveId)
            // If the tracker is in that room, it leaves too. Only with a
            // game id - without one the post would close whatever is open.
            if let gameId = session.ownerGameId, !gameId.isEmpty {
                NotificationCenter.default.post(name: .activeGameShouldClose, object: nil, userInfo: ["gameId": gameId])
            }
            lineupScanNotice = "Disconnected from \(session.opponent)."
        case .endSession(let liveId, let title):
            // The room's status is what every phone acts on, the coach's
            // own tracker included (it keeps the game open).
            LiveGameService.shared.endLiveSession(liveId: liveId) { error in
                lineupScanNotice = error.map { "Couldn't end the live session: \($0.localizedDescription)" }
                    ?? "Live session for \(title) ended."
            }
        }
    }

    private var lineupScanBusyOverlay: AnyView {
        AnyView(ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white).scaleEffect(1.4)
                Text("Adding lineup…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        })
    }

    private var lineupScanSheetContent: AnyView {
        guard let context = lineupScan else { return AnyView(EmptyView()) }
        return AnyView(
            LineupScanSheet(
                teamName: context.teamName,
                roster: lineupScanRoster,
                alreadyInLineup: context.alreadyInLineup,
                confirmTitle: context.confirmTitle,
                onConfirm: { decisions, done in confirmLineupScan(context, decisions: decisions, done: done) },
                onCancel: { showLineupScan = false }
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
        )
    }

    private func teamName(_ teamId: String, fallback: String) -> String {
        myTeams.first(where: { $0.team.id == teamId })?.team.nameWithClass ?? fallback
    }

    /// Opens the sheet and loads the roster behind it. A roster that
    /// can't be read leaves the sheet waiting, with a notice.
    private func presentLineupScan(_ context: LineupScanContext) {
        lineupScan = context
        lineupScanRoster = nil
        lineupScanNotice = nil
        showLineupScan = true
        authManager.loadTeamPlayersResult(teamId: context.teamId) { result in
            switch result {
            case .success(let players):
                lineupScanRoster = players
            case .failure(let error):
                showLineupScan = false
                lineupScanNotice = "Couldn't open \(context.teamName)'s roster: \(error.localizedDescription)"
            }
        }
    }

    private func beginNewGameLineupScan() {
        guard let teamId = inlineNewGameOpponentTeamId else { return }
        presentLineupScan(LineupScanContext(kind: .newGame, teamId: teamId, teamName: teamName(teamId, fallback: inlineNewGameName)))
    }

    private func beginGameLineupScan(_ game: Game, teamId: String) {
        presentLineupScan(LineupScanContext(
            kind: .game(game),
            teamId: teamId,
            teamName: teamName(teamId, fallback: game.opponent),
            alreadyInLineup: LineupScanContext.lineupHitters(of: game)
        ))
    }

    private func setOpponentThenScan(_ game: Game, team: Team) {
        guard let gameId = game.id, let teamId = team.id, let uid = authManager.user?.uid else { return }
        authManager.setGameAwayTeam(ownerUid: uid, gameId: gameId, teamId: teamId, opponentName: team.name) { error in
            if let error {
                lineupScanNotice = "Couldn't set the opponent: \(error.localizedDescription)"
                return
            }
            var updated = game
            updated.awayTeamId = teamId
            updated.opponent = team.name
            if let index = games.firstIndex(where: { $0.id == gameId }) {
                games[index].awayTeamId = teamId
                games[index].opponent = team.name
            }
            beginGameLineupScan(updated, teamId: teamId)
        }
    }

    /// A partner: the room's game says who the opponent is, and the room
    /// is what opens their roster (OpponentPartnerAccess).
    private func beginJoinedLineupScan(_ session: JoinedLiveSession) {
        guard let gameId = session.ownerGameId, !gameId.isEmpty else {
            lineupScanNotice = "This live game can't take a lineup yet - open it once, then try again."
            return
        }
        lineupScanNotice = nil
        Firestore.firestore()
            .collection("users").document(session.ownerUid)
            .collection("games").document(gameId)
            .getDocument { snap, error in
                guard let game = try? snap?.data(as: Game.self) else {
                    lineupScanNotice = "Couldn't open this live game\(error.map { ": \($0.localizedDescription)" } ?? ".")"
                    return
                }
                guard let teamId = game.awayTeamId, !teamId.isEmpty else {
                    lineupScanNotice = "The coach hasn't set an opponent team for this game yet."
                    return
                }
                authManager.claimOpponentAccess(teamId: teamId, liveId: session.liveId, ownerUid: session.ownerUid) { granted in
                    guard granted else {
                        lineupScanNotice = "Couldn't open the opponent's roster - is the live game still running?"
                        return
                    }
                    presentLineupScan(LineupScanContext(
                        kind: .joined(session),
                        teamId: teamId,
                        teamName: game.opponent,
                        alreadyInLineup: LineupScanContext.lineupHitters(of: game)
                    ))
                }
            }
    }

    private func confirmLineupScan(_ context: LineupScanContext, decisions: [LineupScanDecision], done: @escaping (String?) -> Void) {
        let roster = lineupScanRoster ?? []
        func finished(_ problem: String?, added: String) {
            done(nil)
            showLineupScan = false
            lineupScanNotice = problem ?? added
        }

        switch context.kind {
        case .newGame:
            pendingNewGameLineup = PendingNewGameLineup(teamId: context.teamId, decisions: decisions, roster: roster)
            done(nil)
            showLineupScan = false

        case .game(let game):
            guard let gameId = game.id, let uid = authManager.user?.uid else { done("This game isn't saved yet."); return }
            let openInTracker = isActiveGame(game)
            authManager.findOpenLiveRoom(ownerUid: uid, gameId: gameId) { liveId in
                let route = LineupScanRoute.decide(isOwner: true, openInTracker: openInTracker, liveRoomOpen: liveId != nil)
                // No room: the open game closes quietly first, so the
                // tracker can't save its older lineup over this one.
                if case .savedGame(closeFirst: true) = route { closeActiveGame(game) }
                authManager.addScannedLineup(
                    teamId: context.teamId, decisions: decisions, roster: roster,
                    alreadyInLineup: context.alreadyInLineup, route: route,
                    ownerUid: uid, gameId: gameId, liveId: liveId
                ) { problem in
                    finished(problem, added: "Lineup added to \(context.teamName).")
                }
            }

        case .joined(let session):
            authManager.addScannedLineup(
                teamId: context.teamId, decisions: decisions, roster: roster,
                alreadyInLineup: context.alreadyInLineup, route: .liveRoom(alsoSavedGame: false),
                ownerUid: session.ownerUid, gameId: session.ownerGameId, liveId: session.liveId
            ) { problem in
                finished(problem, added: "Lineup sent to the live game.")
            }
        }
    }

    private var activeGames: [Game] {
        games
            .filter { !$0.isArchived }
            .sorted(by: { $0.date > $1.date })
    }

    private var gameStateSignature: [String] {
        games.map { "\($0.id ?? "")|\($0.archivedAt?.timeIntervalSince1970 ?? 0)" }
    }

    /// Just the wordmark now. The gear that opened a separate Settings
    /// sheet is gone (2026-10-21): Code Grid Keys and store became Home
    /// sections of their own and Sound Credits moved into the account
    /// sheet, so the sheet had nothing left to hold.
    static let logoImageName = "SoftballBaseballWtitle4"

    private var homeHeaderRow: some View {
        Image(Self.logoImageName)
            .resizable()
            .scaledToFit()
            .frame(height: 120)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement()
            .accessibilityLabel("PitchMark")
            .accessibilityAddTraits([.isHeader, .isImage])
            .accessibilityIdentifier("home.logo")
            .padding(.horizontal)
    }

    private enum HomeOverviewSection {
        case games
        case teams
        case players
        case templates
        case signGrids
    }

    /// Shared collapsible-header row for Home's two accordion sections -
    /// the title+chevron toggles expand/collapse (and auto-closes the other
    /// section); the trailing icon button is a separate tap target for
    /// whatever action that section already had (refresh, go to chooser).
    private func collapsibleSectionHeader(
        title: String,
        section: HomeOverviewSection,
        trailingSystemImage: String,
        trailingFont: Font = .subheadline,
        secondarySystemImage: String? = nil,
        secondaryLabel: String = "",
        secondaryAction: (() -> Void)? = nil,
        trailingAction: @escaping () -> Void
    ) -> some View {
        let isExpanded = expandedHomeOverviewSection == section
        return HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedHomeOverviewSection = isExpanded ? nil : section
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let secondarySystemImage, let secondaryAction {
                Button(action: secondaryAction) {
                    Image(systemName: secondarySystemImage)
                        .font(trailingFont)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(secondaryLabel)
                .padding(.trailing, 10)
            }

            Button(action: trailingAction) {
                Image(systemName: trailingSystemImage)
                    .font(trailingFont)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func teamRow(_ entry: (team: Team, membership: TeamMembership)) -> some View {
        // No role label here on purpose - Coach/Parent/etc. was a leftover
        // from a dropped multi-person-per-team direction. One person can
        // coach one team and be a parent-follower on another; a team itself
        // carries no role, so nothing belongs next to its name.
        // Two separate buttons, layered rather than nested: the row opens
        // the team, the circle in its center edits the team photo. A Button
        // inside another Button's label doesn't reliably get its own tap.
        ZStack {
            Button {
                selectedTeamEntry = TeamEntrySelection(team: entry.team, membership: entry.membership)
            } label: {
                HStack(spacing: 10) {
                    Text(entry.team.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the circle, which sits on top in the ZStack.
                    Color.clear.frame(width: 40, height: 40)
                    // Right-justified designation. Renders nothing for a team
                    // created before designations existed.
                    TeamDesignationBadge(designation: entry.team.designation)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                teamImageEditTarget = entry.team
            } label: {
                TeamAvatarView(team: entry.team, size: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Team photo for \(entry.team.name)")
        }
    }

    @ViewBuilder
    private var myTeamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionHeader(
                title: "Teams",
                section: .teams,
                trailingSystemImage: showInlineNewTeam ? "xmark.circle.fill" : "plus.circle.fill",
                trailingFont: .title2,
                trailingAction: { toggleInlineNewTeam() }
            )

            if expandedHomeOverviewSection == .teams {
                VStack(alignment: .leading, spacing: 8) {
                    if let createTeamError {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(createTeamError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                            Spacer(minLength: 8)
                            Button("Dismiss") { self.createTeamError = nil }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                        }
                    }

                    if showInlineNewTeam {
                        newTeamCard
                    }

                    // The create-team row used to live ONLY in the empty-state
                    // branch below, so it disappeared the moment you had your
                    // first team - no way to add a second one from Home. It's
                    // the header's + now, available either way.
                    if myTeams.isEmpty, !showInlineNewTeam {
                        Text("You're not on any teams yet. Tap + to create one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeTeamEntries, id: \.team.id) { entry in
                            teamRow(entry)
                        }
                        if activeTeamEntries.isEmpty, !showInlineNewTeam {
                            Text("All your teams are archived.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !archivedTeamEntries.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showArchivedTeams.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(showArchivedTeams ? "Hide Archived" : "Show Archived (\(archivedTeamEntries.count))")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(showArchivedTeams ? 0 : -90))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        if showArchivedTeams {
                            ForEach(archivedTeamEntries, id: \.team.id) { entry in
                                teamRow(entry)
                                    .opacity(0.6)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            // Unconditional now: the header's manual refresh button became
            // the + for the inline create form, and teams/rosters are
            // one-shot reads (unlike pitchers, which have a live listener),
            // so this is the only thing that picks up a change made on
            // another device.
            refreshMyTeams()
        }
    }

    /// `myTeams` itself stays whole - game titles, stats filters and team
    /// names on old games still resolve archived teams. Only the list and
    /// the pickers for new choices hide them.
    private var activeTeamEntries: [(team: Team, membership: TeamMembership)] {
        myTeams.filter { !authManager.archivedTeamIds.contains($0.team.id ?? "") }
    }

    private var archivedTeamEntries: [(team: Team, membership: TeamMembership)] {
        myTeams.filter { authManager.archivedTeamIds.contains($0.team.id ?? "") }
    }

    private var newTeamCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New Team")
                    .font(.headline)
                Spacer()
                Button(action: { closeInlineNewTeam() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Team name", text: $newTeamNameForHome)
                .textFieldStyle(.roundedBorder)

            TeamDesignationForm(draft: $newTeamDesignation)

            HStack {
                Spacer()
                Button("Cancel") { closeInlineNewTeam() }
                Button("Save") { createTeamFromHome() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreateTeamFromHome)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
    }

    private var canCreateTeamFromHome: Bool {
        !newTeamNameForHome.trimmingCharacters(in: .whitespaces).isEmpty && newTeamDesignation.isComplete
    }

    private func toggleInlineNewTeam() {
        if showInlineNewTeam {
            closeInlineNewTeam()
            return
        }
        newTeamNameForHome = ""
        newTeamDesignation.reset()
        createTeamError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedHomeOverviewSection = .teams
            showInlineNewTeam = true
        }
    }

    private func closeInlineNewTeam() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showInlineNewTeam = false
        }
        newTeamNameForHome = ""
        newTeamDesignation.reset()
    }

    private func refreshMyTeams() {
        authManager.loadMyTeams { teams, error in
            myTeams = teams
            // The Players section draws every row's team/designation from
            // this same list, so a team edit has to re-seed the roster too.
            refreshRosterEntries(for: teams.map { $0.team })
        }
    }

    private func createTeamFromHome() {
        let name = newTeamNameForHome.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let designation = newTeamDesignation.designation else { return }
        authManager.createTeam(name: name, designation: designation) { result in
            switch result {
            case .success:
                closeInlineNewTeam()
                refreshMyTeams()
            case .failure(let error):
                createTeamError = "Couldn't create \"\(name)\": \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Home: Players

    /// Every roster row across every team I'm on, used to pair a player
    /// with the team (and therefore the designation) they belong to.
    /// Re-seeded whenever `myTeams` reloads, since a designation edit has
    /// to reach these rows too.
    private func refreshRosterEntries(for teams: [Team]? = nil) {
        let teams = teams ?? myTeams.map { $0.team }
        guard !teams.isEmpty else {
            rosterEntries = []
            return
        }
        isRefreshingPlayers = true
        authManager.loadMyPlayers { myPlayers = $0 }
        authManager.loadPlayerRosterEntries(for: teams) { entries in
            self.rosterEntries = entries
            self.isRefreshingPlayers = false
        }
    }

    private func refreshMyHitters() {
        authManager.loadHitters { loaded in
            myHitters = loaded
        }
    }

    /// Every person in the directory, unscoped and unfiltered - the Pitchers
    /// scope's empty message needs to know whether there are rows at all.
    private var playerRows: [PlayerDirectoryRow] {
        PlayerDirectory.rows(rosterEntries: rosterEntries, pitchers: sortedPitchers, players: myPlayers)
            .filter { PlayerDirectory.passes($0, filter: playerFilter, archivedPitcherIds: hiddenPitcherIds) }
    }

    /// What the list actually shows, after the Pitchers/All scope.
    private var scopedPlayerRows: [PlayerDirectoryRow] {
        playerRows.filter { playersScope == .all || $0.isPitcher }
    }

    private var hasActivePlayerFilter: Bool {
        playerFilter.isActive
    }

    private func beginAddPlayerFromHome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedHomeOverviewSection = .players
        }
        showHomeAddPlayer = true
    }

    /// Teams the + can add a player to: active teams this account created
    /// (only a team's creator can add to its roster).
    private var teamsForNewPlayer: [Team] {
        let uid = authManager.user?.uid
        return activeTeamEntries.map(\.team).filter { uid != nil && $0.createdByUid == uid }
    }

    private var homeAddPlayerSheet: AnyView {
        AnyView(
            HomeAddPlayerSheet(
                teams: teamsForNewPlayer,
                onAddToTeam: { teamId, name, jersey, positions, battingSide, completion in
                    authManager.addTeamPlayerCreatingNewPlayer(
                        teamId: teamId,
                        name: name,
                        jerseyNumber: jersey,
                        positions: positions,
                        battingSide: battingSide
                    ) { result in
                        switch result {
                        case .success:
                            completion(nil)
                            showHomeAddPlayer = false
                            refreshRosterEntries()
                        case .failure(let error):
                            completion(error.localizedDescription)
                        }
                    }
                },
                onAddWithoutTeam: { name in
                    authManager.createPitcher(name: name, templateId: selectedTemplate?.id.uuidString) { created in
                        if let created { pitchers.append(created) }
                        showHomeAddPlayer = false
                    }
                },
                onCancel: { showHomeAddPlayer = false }
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
        )
    }

    /// The Players header carries three controls of its own, so it can't use
    /// `collapsibleSectionHeader` - only the title+chevron half is shared
    /// behavior.
    private var playersSectionHeader: some View {
        let isExpanded = expandedHomeOverviewSection == .players
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedHomeOverviewSection = isExpanded ? nil : .players
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Players")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Sits right against the title (no spacer between them); the
            // spacer goes after it, pushing filter and + to the trailing edge.
            CapsuleSegmentedControl(
                options: [("Pitchers", PlayerDirectoryScope.pitchers), ("All", PlayerDirectoryScope.all)],
                selection: $playersScope,
                segmentMinWidth: 70
            )
            .font(.caption)

            // Link Profiles (link across teams / merge / archive) - was its
            // own Home card until 2026-11-02.
            Button {
                showLinkProfiles = true
            } label: {
                Image(systemName: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pitchMarkActiveGray)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link Profiles")

            Spacer(minLength: 4)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedHomeOverviewSection = .players
                }
                showPlayersFilterSheet = true
            } label: {
                Image(systemName: hasActivePlayerFilter
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(hasActivePlayerFilter ? Color.pitchMarkActiveGray : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter players")

            Button {
                beginAddPlayerFromHome()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add player")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var playersOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            playersSectionHeader

            if expandedHomeOverviewSection == .players {
                let rows = scopedPlayerRows
                if rows.isEmpty {
                    Text(playersEmptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                } else {
                    Divider()
                        .padding(.horizontal)
                    // Bounded vertical scroll rather than letting the list
                    // run the page's full length - a 20-kid roster would
                    // otherwise push Games and Teams far off screen.
                    playersScrollBody(rows)
                }
            }
        }
        .onChange(of: playersScope) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedHomeOverviewSection = .players
            }
        }
    }

    @ViewBuilder
    private func playersScrollBody(_ rows: [PlayerDirectoryRow]) -> some View {
        let content = VStack(spacing: 8) {
            ForEach(rows) { row in
                playerListRowView(row)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)

        if rows.count > 5 {
            ScrollView(.vertical, showsIndicators: true) {
                content
            }
            .frame(maxHeight: 360)
        } else {
            content
        }
    }

    private var playersEmptyMessage: String {
        // "Pitchers" keys off the P position on a roster entry, because every
        // player has a linked Pitcher record regardless. If there are players
        // but none is marked P, say so - otherwise this just looks broken.
        if playersScope == .pitchers, !playerRows.isEmpty {
            return "No one is listed at P. Open a team, tap a player, and add P to their positions - or tap + to add a pitcher directly."
        }
        if hasActivePlayerFilter {
            return "No players match the current filter."
        }
        switch playersScope {
        case .pitchers:
            return "No pitchers yet. Tap + to add one."
        case .all:
            return "No players yet. Add them to a team's roster, or tap + to add a pitcher."
        }
    }

    /// The row itself is `PlayerDirectoryRowView` (PlayerDirectory.swift);
    /// Home's contribution is the trailing Stats button + gear menu.
    private func playerListRowView(_ row: PlayerDirectoryRow) -> some View {
        let isArchived = row.isArchived(in: hiddenPitcherIds)
        return PlayerDirectoryRowView(row: row, isArchived: isArchived) {
            statsControl(for: row)

            Menu {
                playerRowMenu(row)
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A two-way player gets a Stats menu (Pitching / Hitting & Fielding); anyone else
    /// keeps the single button straight into the one sheet that applies.
    @ViewBuilder
    private func statsControl(for row: PlayerDirectoryRow) -> some View {
        let canPitch = canOpenPitchingStats(for: row)
        let canHit = canOpenHittingStats(for: row)
        if canPitch && canHit {
            Menu {
                Button("Pitching Stats") { openPitchingStats(for: row) }
                Button("Hitting & Fielding Stats") { openHittingStats(for: row) }
            } label: {
                Text("Stats")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
        } else {
            Button("Stats") {
                if canPitch {
                    openPitchingStats(for: row)
                } else {
                    openHittingStats(for: row)
                }
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
            .disabled(!canPitch && !canHit)
        }
    }

    /// Keys off `isPitcher`, not `pitcher != nil` - every player has a
    /// linked Pitcher record whether or not they pitch, so keying off that
    /// sent every non-pitcher to the pitching stats sheet.
    private func canOpenPitchingStats(for row: PlayerDirectoryRow) -> Bool {
        row.isPitcher && row.pitcher != nil
    }

    private func canOpenHittingStats(for row: PlayerDirectoryRow) -> Bool {
        guard let hitterId = row.hitterId else { return false }
        return myHitters.contains { $0.id == hitterId }
    }

    private func openPitchingStats(for row: PlayerDirectoryRow) {
        guard let pitcher = row.pitcher else { return }
        statsPitcherIds = row.pitcherIds
        statsTeams = row.teams.sorted(by: Team.listOrder)
        statsPitcher = pitcher
    }

    private func openHittingStats(for row: PlayerDirectoryRow) {
        guard let hitterId = row.hitterId else { return }
        statsHitterIds = row.hitterIds
        statsTeams = row.teams.sorted(by: Team.listOrder)
        statsHitter = myHitters.first(where: { $0.id == hitterId })
    }

    /// The gear menu - the same Image / Edit / Owned / Archive / Copy
    /// actions the old horizontal pitcher strip in Settings exposed, now
    /// per-row. A non-pitching player has none of those (they're Pitcher-doc
    /// operations), so its menu opens the roster screen that does own it.
    /// Owned/Reclaim+Copy split on active ownership; see the note on Copy.
    @ViewBuilder
    private func playerRowMenu(_ row: PlayerDirectoryRow) -> some View {
        if let pitcher = row.pitcher {
            let isArchived = row.isArchived(in: hiddenPitcherIds)
                || (pitcher.id.map { hiddenPitcherIds.contains($0) } ?? false)

            Button {
                beginPitcherPortraitSelection(for: pitcher)
            } label: {
                Label("Image", systemImage: "photo")
            }

            Button {
                editingPitcher = pitcher
                newPitcherName = pitcher.name
                showAddPitcher = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if pitcher.isActiveOwner(currentUid: authManager.user?.uid) {
                // Was labelled "Owned", which read as a status badge rather
                // than the action it is - this mints an invite link.
                Button {
                    beginPitcherShare(pitcher)
                } label: {
                    Label(isGeneratingPitcherShare ? "Sharing…" : "Share Pitcher", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(isGeneratingPitcherShare)
            } else {
                Button {
                    reclaimPitcher(pitcher)
                } label: {
                    Label("Reclaim", systemImage: "arrow.uturn.backward.circle")
                }

                // Copy belongs to this branch only. Reclaim is zero-sum -
                // `claimedByUid` is a single field, so taking active ownership
                // takes the pitcher away from the coach who shared it, and
                // without active ownership you can't select them in a game at
                // all (applySelectedPitcher / pitcherPickerButton / "Owner
                // only"). Copy is the non-destructive way out of that: both
                // coaches keep a usable pitcher. On a pitcher you already own
                // it has no such job and only mints a duplicate "X (Copy)"
                // career record for the same kid.
                Button {
                    copyPitcherTarget = pitcher
                    showCopyPitcherConfirm = true
                } label: {
                    Label(isCopyingPitcher ? "Copying…" : "Copy", systemImage: "doc.on.doc")
                }
                .disabled(isCopyingPitcher)
            }

            // Outside the active-ownership branch on purpose: if a recipient
            // hit Reclaim, the true owner is no longer the *active* owner, but
            // they are still the only account the rules let revoke - and that
            // is precisely the case where they most need to.
            if isTrueOwner(of: pitcher), hasOtherParticipants(pitcher) {
                Button(role: .destructive) {
                    revokePitcherTarget = pitcher
                    showRevokePitcherConfirm = true
                } label: {
                    Label(isRevokingPitcherSharing ? "Stopping…" : "Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
                }
                .disabled(isRevokingPitcherSharing)
            }

            Button {
                guard let id = pitcher.id else { return }
                if !isArchived, !openGameTeamIds.isDisjoint(with: row.teams.compactMap(\.id)) {
                    openGameLockMessage = OpenGameLock.message(for: row.name)
                    return
                }
                // Every record of the person, or a linked player with two
                // would stay visible after "archiving".
                let ids = row.pitcherIds.isEmpty ? [id] : row.pitcherIds
                if isArchived {
                    authManager.setPitchers(ids, archived: false)
                } else {
                    let names = ArchiveScope.names(hiddenBy: ids, rosterEntries: rosterEntries, pitchers: sortedPitchers)
                    pendingPlayerArchive = PendingPlayerArchive(
                        pitcherIds: ids,
                        names: names.isEmpty ? [row.name] : names
                    )
                }
                if pitcherActionTargetId == id { pitcherActionTargetId = nil }
            } label: {
                Label(isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
        }

        if let team = row.teams.first,
           let entry = myTeams.first(where: { $0.team.id == team.id }) {
            Button {
                selectedTeamEntry = TeamEntrySelection(team: entry.team, membership: entry.membership)
            } label: {
                Label("Open \(team.name) Roster", systemImage: "list.bullet.rectangle")
            }
        }
    }

    /// The filter list itself lives in PlayerDirectory.swift, shared with
    /// the pickers. Sheet-hosted `List`, not a `Menu`: Home re-renders
    /// constantly from the pitcher listeners, and a `Menu`'s contents are a
    /// transient `UIMenu` that loses its scroll position on every one of
    /// those re-renders (same reason the cards filter UI is a List - see
    /// CLAUDE.md).
    private var playersFilterSheetView: some View {
        PlayerDirectoryFilterSheet(
            teams: myTeams.map { $0.team },
            filter: $playerFilter
        ) {
            showPlayersFilterSheet = false
        }
    }

    // The gear's Settings sheet is gone (2026-10-21). Everything it held
    // moved out: Pitchers and Code Grid Keys to Home sections of their own,
    // store to a Home row, Sound Credits into the account sheet below Terms
    // of Use.

    /// Code Grid Keys as Home's fourth accordion. Same list body the
    /// Settings sheet used; only the header changed, so the refresh and
    /// new-template buttons keep working exactly as before.
    @ViewBuilder
    private var templatesOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedHomeOverviewSection =
                            (expandedHomeOverviewSection == .templates) ? nil : .templates
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Pitching")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("home.section.pitching")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expandedHomeOverviewSection == .templates ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Button {
                    guard !isRefreshingTemplates else { return }
                    isRefreshingTemplates = true
                    authManager.loadTemplates { loaded in
                        templates = loaded
                        if selectedTemplate == nil {
                            selectedTemplate = loaded.first
                        }
                        isRefreshingTemplates = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingTemplates)
                .accessibilityLabel("Refresh code grid keys")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedHomeOverviewSection = .templates
                    }
                    editorTemplate = PitchTemplate(
                        id: UUID(),
                        name: "",
                        pitches: [],
                        codeAssignments: []
                    )
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New code grid key")
            }
            .padding(.horizontal)

            if expandedHomeOverviewSection == .templates {
                templatesListView

                if showHiddenTemplates, !hiddenTemplates.isEmpty {
                    hiddenTemplatesSection
                }
            }
        }
    }

    /// `AnyView` for the same reason as `gameRow`: this section's concrete
    /// type was inlined into Home's body type deeply enough to overflow the
    /// stack when the runtime demangled it.
    private var gamesOverviewSection: AnyView {
        AnyView(VStack(alignment: .leading, spacing: 10) {
            collapsibleSectionHeader(
                title: "Games",
                section: .games,
                trailingSystemImage: showInlineNewGame ? "xmark.circle.fill" : "plus.circle.fill",
                trailingFont: .title2,
                secondarySystemImage: "calendar",
                secondaryLabel: "Games Calendar",
                secondaryAction: { showGamesCalendar = true },
                trailingAction: { toggleInlineNewGame() }
            )
            .sheet(isPresented: $showLineupScan, onDismiss: { lineupScan = nil }) {
                lineupScanSheetContent
            }
            .sheet(isPresented: $showGamesCalendar) {
                AnyView(
                    GamesCalendarView(
                        games: games,
                        title: { matchupTitle(for: $0) },
                        onOpen: { launchGame($0) }
                    )
                    .fixedAppDynamicType()
                )
            }

            if expandedHomeOverviewSection == .games {
                VStack(spacing: 8) {
                    if let createGameError {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(createGameError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                            Spacer(minLength: 8)
                            Button("Dismiss") { self.createGameError = nil }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                        }
                    }

                    if let lineupScanNotice {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "text.viewfinder")
                                .foregroundStyle(.secondary)
                            Text(lineupScanNotice)
                                .font(.footnote)
                            Spacer(minLength: 8)
                            Button("Dismiss") { self.lineupScanNotice = nil }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                        }
                    }

                    if showInlineNewGame {
                        AddGameCard(
                            opponentName: $inlineNewGameName,
                            gameDate: $inlineNewGameDate,
                            trackingMode: $inlineNewGameTrackingMode,
                            myTeams: activeTeamEntries.map { $0.team },
                            ourTeamId: $inlineNewGameTeamId,
                            opponentTeamId: $inlineNewGameOpponentTeamId,
                            onCreateTeam: { name, designation, completion in
                                authManager.createTeam(name: name, designation: designation) { result in
                                    switch result {
                                    case .success(let team):
                                        // Put it in the picker's pool right
                                        // away, otherwise the card would
                                        // select an id the menu can't name.
                                        refreshMyTeams()
                                        completion(team)
                                    case .failure(let error):
                                        debugLog("❌ createTeam from AddGameCard failed:", error.localizedDescription)
                                        completion(nil)
                                    }
                                }
                            },
                            onCancel: { closeInlineNewGame() },
                            onSave: { createInlineGame() },
                            lineupSummary: pendingNewGameLineup.flatMap { $0.teamId == inlineNewGameOpponentTeamId ? $0.summary : nil },
                            onScanLineup: { beginNewGameLineupScan() }
                        )
                    }

                    // Live-joined games first - they're the ones with a
                    // clock on them (owner can end the session any time).
                    ForEach(joinedLiveSessions) { session in
                        gameRow(
                            opponent: session.opponent,
                            dateText: nil,
                            isLive: true,
                            scanAction: { beginJoinedLineupScan(session) },
                            disconnectAction: { pendingLiveLeave = .disconnect(session) }
                        ) {
                            rejoinLiveSession(session)
                        }
                    }

                    let sorted = activeGames.sorted(by: { $0.date > $1.date })
                    let quickGames = sorted.map { QuickLaunchGame(id: quickLaunchId(for: $0), game: $0) }
                    ForEach(quickGames) { item in
                        gameRow(
                            opponent: matchupTitle(for: item.game),
                            dateText: quickLaunchDateCaption(for: item.game),
                            isLive: false,
                            menuGame: item.game
                        ) {
                            launchGame(item.game)
                        }
                    }

                    if joinedLiveSessions.isEmpty, activeGames.isEmpty, !showInlineNewGame {
                        Text("No games yet. Tap + to create one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }

                    if !archivedGames.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showArchivedGames.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(showArchivedGames ? "Hide Archived" : "Show Archived (\(archivedGames.count))")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(showArchivedGames ? 0 : -90))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        if showArchivedGames {
                            let archived = archivedGames.map { QuickLaunchGame(id: quickLaunchId(for: $0), game: $0) }
                            ForEach(archived) { item in
                                gameRow(
                                    opponent: matchupTitle(for: item.game),
                                    dateText: quickLaunchDateCaption(for: item.game),
                                    isLive: false,
                                    menuGame: item.game
                                ) {
                                    launchGame(item.game)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        })
    }

    private var archivedGames: [Game] {
        games
            .filter { $0.isArchived }
            .sorted(by: { $0.date > $1.date })
    }

    /// The game currently open in the Game tab. `chooseGame` writes this
    /// defaults key and clears it on exit, so it's the same notion of
    /// "active" the tracker itself restores from on launch.
    ///
    /// Mirrored into `@State` rather than read straight from UserDefaults
    /// at render time: SwiftUI doesn't observe UserDefaults, so "Close
    /// Game" would clear the key and the menu would still show the game as
    /// in-use until some unrelated change happened to redraw it.
    private var activeGameId: String? { activeGameIdValue }

    private func refreshActiveGameId() {
        let stored = UserDefaults.standard.string(forKey: PitchTrackerView.DefaultsKeys.activeGameId)
        let resolved = (stored?.isEmpty == false) ? stored : nil
        if activeGameIdValue != resolved {
            activeGameIdValue = resolved
        }
    }

    /// Takes the open game out of in-use status so it - and the teams and
    /// players linked to it - can be deleted. Clears the defaults keys here
    /// AND posts, because the tracker's own teardown
    /// (`disconnectFromGame`) is what stops its listeners and drops the
    /// lineup; doing only one of the two leaves the other side stale.
    private func closeActiveGame(_ game: Game) {
        guard let id = game.id, !id.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: PitchTrackerView.DefaultsKeys.activeGameOwnerUserId)
        NotificationCenter.default.post(
            name: .activeGameShouldClose,
            object: nil,
            userInfo: ["gameId": id]
        )
        refreshActiveGameId()
    }

    /// Both teams of the open game. Archiving a player or team on either
    /// waits until the game is closed - see `OpenGameLock`.
    private var openGameTeamIds: Set<String> {
        OpenGameLock.teamIds(activeGameId: activeGameId, games: games)
    }

    private func closeOpenGame() {
        guard let activeGameId, let game = games.first(where: { $0.id == activeGameId }) else { return }
        closeActiveGame(game)
    }

    private func isActiveGame(_ game: Game) -> Bool {
        guard let id = game.id, let activeGameId else { return false }
        return id == activeGameId
    }

    /// A team counts as in-use when it's either side of the open game -
    /// ours or the opponent's.
    /// Tapping + while the section is collapsed should open the section
    /// too, otherwise the form it just revealed would be hidden.
    private func toggleInlineNewGame() {
        if showInlineNewGame {
            closeInlineNewGame()
            return
        }
        inlineNewGameName = ""
        inlineNewGameDate = Date()
        inlineNewGameTrackingMode = .coach
        // Pre-select when there's only one team to choose - a coach with a
        // single team shouldn't have to pick it every game.
        inlineNewGameTeamId = myTeams.count == 1 ? myTeams.first?.team.id : nil
        inlineNewGameOpponentTeamId = nil
        pendingNewGameLineup = nil
        createGameError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedHomeOverviewSection = .games
            showInlineNewGame = true
        }
    }

    private func closeInlineNewGame() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showInlineNewGame = false
        }
        inlineNewGameName = ""
        inlineNewGameTeamId = nil
        inlineNewGameOpponentTeamId = nil
        pendingNewGameLineup = nil
    }

    /// Creates the game and puts it straight in the list. The row is real
    /// and openable as soon as Firestore mints the id (onLocalWrite) -
    /// waiting on the server ack is what used to leave a new game sitting
    /// in the list as an untappable "Saving..." row.
    private func createInlineGame() {
        let name = inlineNewGameName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var newGame = Game(
            id: nil,
            opponent: name,
            date: inlineNewGameDate,
            jerseyNumbers: [],
            trackingMode: inlineNewGameTrackingMode
        )
        // Our side, chosen in the card. Left nil the tracker still asks for
        // it on the first tap of "Us", exactly as before.
        newGame.teamId = inlineNewGameTeamId
        // The opponent is a real Team now, so the away roster is linked
        // from the start instead of being set up later from the tracker.
        newGame.awayTeamId = inlineNewGameOpponentTeamId
        // A scanned lineup for this opponent: make its new roster rows
        // first, then the game is created with the lineup already in it.
        let scanned = pendingNewGameLineup.flatMap { $0.teamId == inlineNewGameOpponentTeamId ? $0 : nil }
        closeInlineNewGame()

        guard let scanned else {
            saveInlineGame(newGame, name: name)
            return
        }
        isAddingScannedLineup = true
        let plan = LineupScanPlan.make(scanned.decisions, alreadyInLineup: [])
        var rowIdByHitter: [String: String] = [:]
        for player in scanned.roster {
            if let hitterId = player.hitterId, let id = player.id { rowIdByHitter[hitterId] = id }
        }
        authManager.resolveScanPlan(teamId: scanned.teamId, plan: plan, existingTeamPlayerIds: rowIdByHitter) { entries, failed in
            isAddingScannedLineup = false
            var game = newGame
            game.jerseyNumbers = entries.map(\.display)
            game.batterIds = entries.map(\.cellId)
            game.hitterIdByBatterId = Dictionary(uniqueKeysWithValues: entries.map { ($0.cellId, $0.hitterId) })
            if failed > 0 {
                lineupScanNotice = "\(failed) new player\(failed == 1 ? "" : "s") couldn't be added to the roster."
            }
            saveInlineGame(game, name: name)
        }
    }

    private func saveInlineGame(_ newGame: Game, name: String) {
        var stampedId: String? = nil
        authManager.saveGame(
            newGame,
            onLocalWrite: { stamped in
                stampedId = stamped.id
                if let idx = self.games.firstIndex(where: { $0.id == stamped.id }) {
                    self.games[idx] = stamped
                } else {
                    self.games.append(stamped)
                }
                self.createGameError = nil
            }
        ) { result in
            guard case .failure(let error) = result else { return }
            DispatchQueue.main.async {
                if let stampedId, let idx = self.games.firstIndex(where: { $0.id == stampedId }) {
                    self.games.remove(at: idx)
                }
                self.createGameError = "Couldn't save \"\(name)\": \(error.localizedDescription)"
                debugLog("❌ create game failed:", error.localizedDescription)
            }
        }
    }

    private func archivedGameStatsToggle(_ game: Game) -> some View {
        Toggle(isOn: Binding(
            get: { authManager.gameCountsInStats(game) },
            set: { include in
                guard let id = game.id, !id.isEmpty else { return }
                authManager.setArchivedGame(id, includedInStats: include)
            }
        )) {
            Label("Include in Stats", systemImage: "chart.bar")
        }
    }

    /// Re-enters a game joined as a partner, using the same
    /// `.gameOrSessionChosen`/"liveGame" path a fresh join uses - it resumes
    /// listeners and refreshes presence, it doesn't rejoin from scratch.
    /// Stays in the list until the owner ends the session, the room expires
    /// unrenewed, or this device explicitly disconnects (see
    /// `LiveGameService.removeJoinedLiveSession`).
    private func rejoinLiveSession(_ session: JoinedLiveSession) {
        onSwitchToArea?(.games)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .gameOrSessionChosen,
                object: nil,
                userInfo: [
                    "type": "liveGame",
                    "liveId": session.liveId,
                    "ownerUid": session.ownerUid
                ]
            )
        }
    }

    /// Join a Game (Home's row of three): the QR scanner, Pro only.
    private func startJoinFlow() {
        if !subscriptionManager.isPro {
            proGateMessage = "Joining games requires PitchMark Pro."
            showProGateAlert = true
            return
        }
        inviteJoinError = nil
        inviteJoinText = ""
        showQRScanner = true
    }

    private func deletePendingTemplate() {
        guard let template = templatePendingDeletion else { return }
        let templateId = template.id
        authManager.deleteTemplate(template)
        templates.removeAll { $0.id == templateId }
        templatePendingDeletion = nil
    }

    private func handleCreatedPitcher(_ created: Pitcher?) {
        if let created {
            pitchers.append(created)
        }
        showAddPitcher = false
    }

    private func handleSavedTemplate(_ updatedTemplate: PitchTemplate) {
        if let index = templates.firstIndex(where: { $0.id == updatedTemplate.id }) {
            templates[index] = updatedTemplate
        } else {
            templates.append(updatedTemplate)
        }

        // Adopt the first key the account ever gets. Both of these are
        // bindings onto the tracker's own state, and until this line only
        // `templates` was written - so after creating a first key the
        // tracker had a key to offer in its picker while `selectedTemplate`
        // stayed nil, which is the condition it blurs and shows
        // "No Code Grid Key Yet" for. The card stayed up on a screen that
        // was otherwise ready to use.
        //
        // Assignment is enough: the tracker's `.onChange(of:
        // selectedTemplate?.id)` turns it into a full `applyTemplate`, so
        // the pitch chips and code assignments come with it. Guarded on nil
        // so saving a second key never steals the selection from the one in
        // use.
        if selectedTemplate == nil {
            selectedTemplate = updatedTemplate
        }

        authManager.saveTemplate(updatedTemplate)
    }

    private func beginEditTemplate(_ template: PitchTemplate) {
        guard isTemplateEditable(template), !isCheckingPurchasedTemplate else { return }

        isCheckingPurchasedTemplate = true
        Task {
            let hasOrders = await authManager.hasRetailOrders(forTemplateId: template.id.uuidString)
            await MainActor.run {
                isCheckingPurchasedTemplate = false
                if hasOrders {
                    purchasedTemplateEditTarget = template
                    showPurchasedTemplateEditAlert = true
                } else {
                    editorTemplate = template
                }
            }
        }
    }

    private var pitcherShareSheetItems: [Any] {
        if let qr = sharePitcherQR {
            return [sharePitcherLink, qr]
        }
        return [sharePitcherLink]
    }

    private var pitcherShareSheetView: some View {
        VStack(spacing: 16) {
            Text("Share Pitcher")
                .font(.headline)

            if !sharePitcherLink.isEmpty {
                Text(sharePitcherLink)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }

            if let qr = sharePitcherQR {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack {
                Button("Close") {
                    showPitcherShareSheet = false
                }
                Spacer()
                Button("Share") {
                    showPitcherShareActivity = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(sharePitcherLink.isEmpty)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var addPitcherSheetTitle: String {
        editingPitcher == nil ? "New Player" : "Edit Player"
    }

    private func dismissPitcherEditor() {
        showAddPitcher = false
        editingPitcher = nil
    }

    private func updatePitcherInMemory(_ updated: Pitcher) {
        guard let id = updated.id else { return }
        if let idx = pitchers.firstIndex(where: { $0.id == id }) {
            pitchers[idx] = updated
        } else {
            pitchers.append(updated)
        }
    }

    private func savePitcherFromSheet() {
        let name = newPitcherName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let editing = editingPitcher, let pid = editing.id {
            authManager.updatePitcher(id: pid, name: name, templateId: editing.templateId) { updated in
                if let updated {
                    updatePitcherInMemory(updated)
                }
                dismissPitcherEditor()
                // The Pitcher doc is only one of four places this person's
                // name lives. Without this, the row right under this sheet
                // (and the in-game pitcher picker, which reads the same
                // roster rows) kept showing the old name.
                authManager.propagatePlayerRename(name: name, pitcherId: pid) {
                    refreshRosterEntries()
                }
            }
        } else {
            let templateId = selectedTemplate?.id.uuidString
            authManager.createPitcher(name: name, templateId: templateId) { created in
                handleCreatedPitcher(created)
            }
        }
    }

    private func beginPitcherPortraitSelection(for pitcher: Pitcher) {
        guard pitcher.id != nil else { return }
        pitcherPortraitTarget = pitcher
        pitcherPortraitSourceImage = nil
        showPitcherPhotoPicker = true
    }

    private func handlePickedPitcherPortrait(_ image: UIImage?) {
        guard let image else {
            pitcherPortraitTarget = nil
            pitcherPortraitSourceImage = nil
            return
        }
        pitcherPortraitSourceImage = image
        DispatchQueue.main.async {
            showPitcherPortraitEditor = true
        }
    }

    private func savePitcherPortrait(_ image: UIImage) {
        guard let target = pitcherPortraitTarget, let id = target.id else {
            pitcherPortraitSourceImage = nil
            showPitcherPortraitEditor = false
            return
        }

        let didSave = saveLocalPitcherPortrait(image, pitcherId: id)
        if !didSave {
            pitcherImageErrorMessage = "Unable to save that image."
            showPitcherImageError = true
        } else {
            updatePitcherInMemory(target)
        }
        pitcherPortraitSourceImage = nil
        showPitcherPortraitEditor = false
        pitcherPortraitTarget = nil
    }

    private func resetPitcherPortraitEditorState() {
        pitcherPortraitSourceImage = nil
        showPitcherPortraitEditor = false
        pitcherPortraitTarget = nil
    }

    private var addPitcherSheetView: some View {
        VStack(spacing: 16) {
            Text(addPitcherSheetTitle)
                .font(.headline)

            TextField("Name", text: $newPitcherName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismissPitcherEditor()
                }
                Spacer()
                Button("Save") {
                    savePitcherFromSheet()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationDetents([.fraction(0.35)])
        .presentationDragIndicator(.visible)
    }

    private func qrImage(for text: String) -> UIImage? {
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func beginPitcherShare(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        isGeneratingPitcherShare = true
        authManager.createPitcherInviteToken(pitcherId: pitcherId) { result in
            DispatchQueue.main.async {
                self.isGeneratingPitcherShare = false
                switch result {
                case .success(let token):
                    let link = "pitchmark://pitcher?token=\(token)"
                    self.sharePitcherLink = link
                    self.sharePitcherQR = self.qrImage(for: link)
                    self.showPitcherShareSheet = true
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    /// True owner, i.e. `ownerUid` - distinct from `isActiveOwner`, which a
    /// recipient takes over by hitting Reclaim.
    private func isTrueOwner(of pitcher: Pitcher) -> Bool {
        guard let uid = authManager.user?.uid else { return false }
        return pitcher.ownerUid == uid
    }

    /// Is anyone other than the owner currently holding access? Covers both
    /// routes in: `sharedWith` (invite redeemed) and `claimedByUid` (Reclaim).
    private func hasOtherParticipants(_ pitcher: Pitcher) -> Bool {
        if pitcher.sharedWith.contains(where: { $0 != pitcher.ownerUid }) { return true }
        if let claimed = pitcher.claimedByUid, claimed != pitcher.ownerUid { return true }
        return false
    }

    private func revokePitcherSharing(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        guard !isRevokingPitcherSharing else { return }
        isRevokingPitcherSharing = true
        authManager.revokePitcherSharing(pitcherId: pitcherId) { result in
            DispatchQueue.main.async {
                self.isRevokingPitcherSharing = false
                switch result {
                case .success(let updated):
                    if let id = updated.id, let idx = pitchers.firstIndex(where: { $0.id == id }) {
                        pitchers[idx] = updated
                    } else {
                        authManager.loadPitchers { loaded in
                            pitchers = loaded
                        }
                    }
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func reclaimPitcher(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        authManager.reclaimPitcher(pitcherId: pitcherId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    if let id = updated.id, let idx = pitchers.firstIndex(where: { $0.id == id }) {
                        pitchers[idx] = updated
                    } else {
                        authManager.loadPitchers { loaded in
                            pitchers = loaded
                        }
                    }
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func copyPitcher(_ pitcher: Pitcher) {
        guard !isCopyingPitcher else { return }
        isCopyingPitcher = true
        authManager.copyPitcherWithEvents(sourcePitcher: pitcher) { result in
            DispatchQueue.main.async {
                self.isCopyingPitcher = false
                switch result {
                case .success(let newPitcher):
                    pitchers.append(newPitcher)
                    if let sourceId = pitcher.id, let newId = newPitcher.id {
                        copyLocalPitcherPortrait(from: sourceId, to: newId)
                    }
                    NotificationCenter.default.post(name: .pitcherSharedUpdated, object: nil)
                case .failure(let error):
                    self.pitcherShareError = error.localizedDescription
                    self.showPitcherShareError = true
                }
            }
        }
    }

    private func startPitchersListenerIfNeeded() {
        guard ownedPitchersListener == nil && sharedPitchersListener == nil else { return }
        guard let uid = authManager.user?.uid else { return }

        let db = Firestore.firestore()
        let ownedRef = db.collection("pitchers").whereField("ownerUid", isEqualTo: uid)
        let sharedRef = db.collection("pitchers").whereField("sharedWith", arrayContains: uid)

        func mergeDocs(_ docs: [QueryDocumentSnapshot]) {
            Task { @MainActor in
                var map = livePitchersById
                for doc in docs {
                    do {
                        let pitcher = try doc.data(as: Pitcher.self)
                        if let id = pitcher.id {
                            map[id] = pitcher
                        }
                    } catch {
                        debugLog("❌ Pitcher decode failed (listener) docId=\(doc.documentID) error=\(error)")
                    }
                }
                livePitchersById = map
                pitchers = Array(map.values)
            }
        }

        ownedPitchersListener = ownedRef.addSnapshotListener { snapshot, error in
            if let error {
                debugLog("❌ owned pitchers listener error:", error.localizedDescription)
                return
            }
            let docs = snapshot?.documents ?? []
            mergeDocs(docs)
        }

        sharedPitchersListener = sharedRef.addSnapshotListener { snapshot, error in
            if let error {
                debugLog("❌ shared pitchers listener error:", error.localizedDescription)
                return
            }
            let docs = snapshot?.documents ?? []
            mergeDocs(docs)
        }
    }

    @ViewBuilder
    private var inviteJoinSheetView: some View {
        VStack(spacing: 16) {
            Text("Join a Live Game")
                .font(.headline)

            VStack(spacing: 6) {
                Text("You'll join as a participant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Tip: scan the primary user's code to open quickly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Paste invite link", text: $inviteJoinText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let error = inviteJoinError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(isJoiningInvite ? "Joining..." : "Join") {
                joinLiveGameFromInvite()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviteJoinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningInvite)

            Button("Scan QR Code") {
                openCameraForJoin()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    // templatesHeader/templatesSection were the Settings sheet's wrapper
    // around templatesListView. The accordion header in
    // templatesOverviewSection replaced both.

    @ViewBuilder
    private var templatesListView: some View {
        if templates.isEmpty {
            Text("No templates saved")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            let selected = visibleTemplates.first(where: { $0.id == templateActionTargetId })

            VStack(alignment: .leading, spacing: 12) {
                // Archiving every key used to render this message and
                // nothing else: the "Show Archived" toggle lives in the
                // chip row below, and that row only existed while at least
                // one key was still visible. So the archived keys became
                // unreachable from Home - the one control that could bring
                // them back was hidden by the same condition that hid them.
                // (They were still reachable from the tracker's "Open Code
                // Grid Keys", which sets showHiddenTemplates directly,
                // which is how this got noticed.) The row now renders
                // whether or not any key is visible.
                if visibleTemplates.isEmpty {
                    Text("Every key is archived.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            let isActive = template.id == templateActionTargetId
                            Button(template.name) {
                                templateActionTargetId = (templateActionTargetId == template.id) ? nil : template.id
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isActive ? Color.black.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(Color.black, lineWidth: 1)
                            )
                        }

                        if !hiddenTemplates.isEmpty {
                            Button(showHiddenTemplates ? "Hide Archived" : "Show Archived") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showHiddenTemplates.toggle()
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                    }
                    .padding(.horizontal)
                }

                if let template = selected {
                    HStack(spacing: 8) {
                        Button("Share") {
                            beginShareTemplate(template)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isTemplateEditable(template))

                        Button("Edit") {
                            beginEditTemplate(template)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isTemplateEditable(template) || isCheckingPurchasedTemplate)

                        Spacer()

                        Button("Archive") {
                            hiddenTemplateIds.insert(template.id.uuidString)
                            saveHiddenTemplateIds()
                            if templateActionTargetId == template.id {
                                templateActionTargetId = nil
                            }
                            if selectedTemplate?.id == template.id {
                                selectedTemplate = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.horizontal)
                }

                Spacer().frame(height: 8)
            }
        }
    }
    
    @ViewBuilder
    private var hiddenTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden Templates")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(hiddenTemplates) { template in
                    HStack {
                        Text(template.name)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("Unhide") {
                            hiddenTemplateIds.remove(template.id.uuidString)
                            saveHiddenTemplateIds()
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                    .padding(.vertical, 6)
                    Divider().padding(.leading)
                }
            }
            .padding(.horizontal)
        }
    }

    // soundCreditsSection's capsule row lived in the Settings sheet. The
    // list itself now opens from the account sheet, below Terms of Use.

    @ViewBuilder
    private var accountActionsSheetView: some View {
        VStack(spacing: 16) {
            Text("Account")
                .font(.headline)

            Text("Signed in as \(authManager.userEmail)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let privacyPolicyURL {
                Link("Privacy Policy", destination: privacyPolicyURL)
                    .font(.subheadline)
            }

            if let termsOfUseURL {
                Link("Terms of Use", destination: termsOfUseURL)
                    .font(.subheadline)
            }

            // Moved here from the (now removed) Settings sheet - it sits
            // with Privacy Policy and Terms of Use because it's the same
            // kind of thing: a legal/courtesy attribution list, not a
            // control. Presented as its own sheet rather than a
            // NavigationLink: this sheet has no NavigationView to push into.
            Button {
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showSoundCreditsSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "quote.bubble")
                        .foregroundStyle(.secondary)
                    Text("Sound Credits")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens the bundled sound pack's attribution list.")

            Button {
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showLearnPitchMark = true
                }
            } label: {
                HStack {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.blue)
                    Text("Learn PitchMark")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens PitchMark tutorial videos.")

            Button {
                let current = authManager.userEmail
                changeEmailText = (current == "Unknown") ? "" : current
                changeEmailError = nil
                changeEmailStatus = nil
                requiresRecentLogin = false
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showChangeEmailSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundStyle(.blue)
                    Text("Change Email")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }

            Button(role: .destructive) {
                showSignOutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundStyle(.red)
                    Text("Sign Out")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }

            Button {
                showAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showMoreAccountActionsSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                    Text("More")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
            }

        }
        .padding()
        // Attached to the whole sheet, not to the Sign Out row. appConfirmationDialog
        // draws as an .overlay, and SwiftUI clips an overlay's *hit testing* to its
        // parent's frame even though it draws outside it. Hung off the small button
        // the dialog was visible but untappable, so taps fell through to the "More"
        // button underneath and opened the Delete Account sheet.
        .appConfirmationDialog(
            isPresented: $showSignOutConfirmation,
            title: "Sign Out?",
            message: "Are you sure you want to sign out of \(authManager.userEmail)?",
            primaryTitle: "Sign Out",
            primaryRole: .destructive,
            primaryAction: {
                showAccountActionsSheet = false
                authManager.signOut()
            },
            secondaryTitle: "Cancel"
        )
        .presentationDetents([.fraction(0.42)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var moreAccountActionsSheetView: some View {
        VStack(spacing: 16) {
            Text("More")
                .font(.headline)

            Button(role: .destructive) {
                deleteAccountText = ""
                deleteAccountError = nil
                requiresDeleteRecentLogin = false
                showMoreAccountActionsSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showDeleteAccountSheet = true
                }
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Account")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
            }

            Button("Cancel", role: .cancel) {
                showMoreAccountActionsSheet = false
            }
        }
        .padding()
        .presentationDetents([.fraction(0.24)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var changeEmailSheetView: some View {
        VStack(spacing: 16) {
            Text("Change Email")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("New Email")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("name@example.com", text: $changeEmailText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let error = changeEmailError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let status = changeEmailStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if requiresRecentLogin {
                Button("Sign Out to Re-Authenticate", role: .destructive) {
                    showChangeEmailSheet = false
                    authManager.signOut()
                }
                .buttonStyle(.bordered)
            }

            Button(isChangingEmail ? "Sending..." : "Send Verification") {
                let trimmed = changeEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    changeEmailError = "Email required."
                    changeEmailStatus = nil
                    requiresRecentLogin = false
                    return
                }

                isChangingEmail = true
                changeEmailError = nil
                changeEmailStatus = nil
                requiresRecentLogin = false
                authManager.changeEmail(to: trimmed) { result in
                    DispatchQueue.main.async {
                        isChangingEmail = false
                        switch result {
                        case .success:
                            changeEmailError = nil
                            changeEmailStatus = "Verification email sent. Confirm it to finish updating your account email."
                            requiresRecentLogin = false
                        case .failure(let error):
                            changeEmailError = error.localizedDescription
                            changeEmailStatus = nil
                            if let changeError = error as? ChangeEmailError {
                                if case .requiresRecentLogin = changeError {
                                    requiresRecentLogin = true
                                } else {
                                    requiresRecentLogin = false
                                }
                            } else {
                                requiresRecentLogin = false
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChangingEmail)

            Button("Cancel", role: .cancel) {
                showChangeEmailSheet = false
            }
        }
        .padding()
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var deleteAccountSheetView: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Delete Account")
                    .font(.headline)

                Text("This permanently deletes your PitchMark account and removes or unlinks account-associated app data. Some transaction records may be retained when legally required, without an active account link. Type DELETE to confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Type DELETE", text: $deleteAccountText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($isDeleteConfirmationFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isDeleteConfirmationFocused = false
                    }

                if let error = deleteAccountError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Account deletion failed. \(error)")
                }

                if requiresDeleteRecentLogin {
                    Button("Sign Out to Re-Authenticate", role: .destructive) {
                        showDeleteAccountSheet = false
                        authManager.signOut()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Delete Account") {
                    isDeleteConfirmationFocused = false
                    showFinalDeleteAccountConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(deleteAccountText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")
                .accessibilityHint("Opens the final permanent deletion confirmation.")

                Button("Cancel", role: .cancel) {
                    showDeleteAccountSheet = false
                }
            }
            .padding()
            .disabled(accountDeletionIsBlocking)
            .accessibilityHidden(accountDeletionIsBlocking)

            if accountDeletionIsBlocking {
                accountDeletionStatusView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .appConfirmationDialog(
            isPresented: $showFinalDeleteAccountConfirmation,
            title: "Permanently delete this account?",
            message: "This cannot be undone.",
            primaryTitle: "Delete Account Permanently",
            primaryRole: .destructive,
            primaryAction: {
                deleteAccount()
            },
            secondaryTitle: "Cancel"
        )
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(accountDeletionIsBlocking ? .hidden : .visible)
        .interactiveDismissDisabled(accountDeletionIsBlocking)
        .animation(.easeInOut(duration: 0.2), value: accountDeletionIsBlocking)
        .onAppear {
            isDeleteConfirmationFocused = true
        }
    }

    private var accountDeletionIsBlocking: Bool {
        isDeletingAccount
    }

    @ViewBuilder
    private var accountDeletionStatusView: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Deleting Account…")
                    .font(.headline)
                Text("Securely removing your account data. Keep PitchMark open until this finishes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Deleting account. Keep PitchMark open until this finishes.")
        }
    }

    private func deleteAccount() {
        isDeleteConfirmationFocused = false
        showFinalDeleteAccountConfirmation = false
        isDeletingAccount = true
        deleteAccountError = nil
        requiresDeleteRecentLogin = false
        UIAccessibility.post(
            notification: .announcement,
            argument: "Deleting account. Keep PitchMark open until this finishes."
        )
        authManager.deleteAccount { result in
            DispatchQueue.main.async {
                isDeletingAccount = false
                switch result {
                case .success:
                    deleteAccountText = ""
                    deleteAccountError = nil
                    requiresDeleteRecentLogin = false
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Account deleted. Returning to sign in."
                    )
                case .failure(let error):
                    deleteAccountError = error.localizedDescription
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Account deletion failed. \(error.localizedDescription)"
                    )
                    if let deleteError = error as? DeleteAccountError {
                        if case .requiresRecentLogin = deleteError {
                            requiresDeleteRecentLogin = true
                        } else {
                            requiresDeleteRecentLogin = false
                        }
                    } else {
                        requiresDeleteRecentLogin = false
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        homeHeaderRow

                        sectionCard(tint: .games) {
                            gamesOverviewSection
                        }

                        sectionCard(tint: .teams) {
                            myTeamsSection
                        }

                        sectionCard(tint: .players) {
                            playersOverviewSection
                        }

                        // Pitching and Batting keys are both worn on the
                        // armband (2026-11-10).
                        Divider()
                            .padding(.horizontal)
                        Text("Armband Keys")
                            .font(.title3.weight(.bold))
                            .padding(.horizontal)
                            .padding(.bottom, -8)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home.armbandKeys")

                        sectionCard {
                            templatesOverviewSection
                        }

                        sectionCard {
                            SignGridsHomeSection(isExpanded: Binding(
                                get: { expandedHomeOverviewSection == .signGrids },
                                set: { expandedHomeOverviewSection = $0 ? .signGrids : nil }
                            ))
                        }


                        Color.clear.frame(height: 8)
                    }
                    .padding(.top, 4)
                }
                .safeAreaInset(edge: .bottom) {
                    HomeBottomBar(email: authManager.user?.email) {
                        Storefront
                    } onJoin: {
                        startJoinFlow()
                    } onAccount: {
                        showAccountActionsSheet = true
                    }
                }

                if isAddingScannedLineup {
                    lineupScanBusyOverlay
                }
            }
            .sheet(isPresented: $showInviteJoinSheet) {
                inviteJoinSheetView
                    .fixedAppDynamicType()
            }
            .sheet(item: $selectedTeamEntry, onDismiss: { refreshMyTeams() }) { entry in
                TeamRosterView(
                    selection: entry,
                    isInOpenGame: openGameTeamIds.contains(entry.team.id ?? ""),
                    onCloseGame: { closeOpenGame() }
                )
                .environmentObject(authManager)
            }
            // Root of Home, not the row - see CLAUDE.md's Dialogs section.
            .teamImageEditor(team: $teamImageEditTarget)
            .fullScreenCover(isPresented: $showQRScanner) {
                ZStack(alignment: .bottom) {
                    QRScannerView { scanned in
                        inviteJoinText = scanned
                        inviteJoinError = nil
                        showQRScanner = false
                        joinLiveGameFromInvite()
                    } onCancel: {
                        showQRScanner = false
                    }

                    Button("Paste invite link") {
                        showQRScanner = false
                        showInviteJoinSheet = true
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
                .fixedAppDynamicType()
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This device doesn’t have a camera available.")
            }
            .homeLiveLeaveDialog(pending: $pendingLiveLeave) { leave in confirmLiveLeave(leave) }
            .archiveGameDialog(game: $pendingArchiveGame, title: matchupTitle) { game, keepInStats in
                guard let id = game.id, !id.isEmpty else { return }
                authManager.archiveGame(gameId: id, keepInStats: keepInStats)
                if let idx = games.firstIndex(where: { $0.id == id }) {
                    games[idx].archivedAt = Date()
                }
            }
            .appConfirmationDialog(
                isPresented: Binding(
                    get: { openGameLockMessage != nil },
                    set: { if !$0 { openGameLockMessage = nil } }
                ),
                title: OpenGameLock.title,
                message: openGameLockMessage ?? "",
                primaryTitle: "Close Game",
                primaryAction: { closeOpenGame() },
                secondaryTitle: "Not Now"
            )
            .appConfirmationDialog(
                isPresented: Binding(
                    get: { pendingPlayerArchive != nil },
                    set: { if !$0 { pendingPlayerArchive = nil } }
                ),
                title: pendingPlayerArchive?.title ?? "Archive Player?",
                message: pendingPlayerArchive?.message ?? "",
                primaryTitle: "Archive",
                primaryAction: {
                    guard let pending = pendingPlayerArchive else { return }
                    authManager.setPitchers(pending.pitcherIds, archived: true)
                },
                secondaryTitle: "Cancel"
            )
            .appConfirmationDialog(
                isPresented: $showCameraPermissionAlert,
                title: "Camera Access Needed",
                message: "Enable Camera access in Settings to scan the owner’s QR code.",
                primaryTitle: "Open Settings",
                primaryAction: {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                },
                secondaryTitle: "Cancel"
            )
            .sheet(isPresented: $showAccountActionsSheet, onDismiss: {
                showSignOutConfirmation = false
            }) {
                accountActionsSheetView
                    .fixedAppDynamicType()
            }
            .fullScreenCover(isPresented: $showLearnPitchMark) {
                LearnPitchMarkView()
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showSoundCreditsSheet) {
                NavigationView {
                    SoundCreditsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSoundCreditsSheet = false }
                            }
                        }
                }
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $showChangeEmailSheet) {
                changeEmailSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showMoreAccountActionsSheet) {
                moreAccountActionsSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showDeleteAccountSheet) {
                deleteAccountSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showProPaywall) {
                ProPaywallView(
                    title: "PitchMark Pro",
                    message: "Invite links and participant connections require PitchMark Pro.",
                    allowsClose: true
                )
                .fixedAppDynamicType()
            }
            .appConfirmationDialog(
                isPresented: $showProGateAlert,
                title: "Upgrade to Pro",
                message: proGateMessage,
                primaryTitle: "Upgrade",
                primaryAction: {
                    showProPaywall = true
                },
                secondaryTitle: "Not Now"
            )
            .onAppear {
                loadHiddenIds()
                startPitchersListenerIfNeeded()
                refreshMyHitters()
                refreshActiveGameId()
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionChosen)) { _ in
                // The tracker writes activeGameId as part of opening a
                // game; mirror it so "Close Game" shows up on the right row.
                refreshActiveGameId()
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionDeleted)) { _ in
                refreshActiveGameId()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createCodeGridKeyRequested)) { note in
                // Sent by the tracker when it is blurred for want of a
                // usable key.
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedHomeOverviewSection = .templates
                }
                // createNew == false means keys exist but are all archived:
                // reveal the archived list, where Unhide is, instead of
                // opening a blank editor they didn't ask for.
                if (note.userInfo?["createNew"] as? Bool) ?? true {
                    editorTemplate = PitchTemplate(
                        id: UUID(),
                        name: "",
                        pitches: [],
                        codeAssignments: []
                    )
                } else {
                    showHiddenTemplates = true
                }
            }
            .onDisappear {
                ownedPitchersListener?.remove()
                ownedPitchersListener = nil
                sharedPitchersListener?.remove()
                sharedPitchersListener = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .pitcherSharedUpdated)) { _ in
                authManager.loadPitchers { loaded in
                    pitchers = loaded
                }
            }
            .sheet(isPresented: $showShareTemplateSheet) {
                VStack(spacing: 16) {
                    Text("Share Template")
                        .font(.headline)

                    if let template = templatePendingShare {
                        Text(template.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    TextField("Recipient Email", text: $shareTargetEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textFieldStyle(.roundedBorder)

                    if !shareTemplateError.isEmpty {
                        Text(shareTemplateError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Button("Cancel") {
                            showShareTemplateSheet = false
                        }
                        Spacer()
                        Button(isSharingTemplate ? "Sharing..." : "Share") {
                            guard let template = templatePendingShare else { return }

                            isSharingTemplate = true
                            shareTemplateError = ""

                            authManager.shareTemplateByEmail(template, email: shareTargetEmail) { err in
                                DispatchQueue.main.async {
                                    isSharingTemplate = false
                                    if let err {
                                        shareTemplateError = err.localizedDescription
                                    } else {
                                        showShareTemplateSheet = false
                                    }
                                }
                            }
                        }
                        .disabled(shareTargetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSharingTemplate)
                    }
                }
                .padding()
                .presentationDetents([.medium])
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $showPitcherShareSheet) {
                pitcherShareSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showPitcherShareActivity) {
                ShareSheet(items: pitcherShareSheetItems)
                    .fixedAppDynamicType()
            }
            .appConfirmationDialog(
                isPresented: $showDeleteAlert,
                title: "Delete Template?",
                message: "Are you sure you want to delete this template?",
                primaryTitle: "Delete",
                primaryRole: .destructive,
                primaryAction: {
                    deletePendingTemplate()
                },
                secondaryTitle: "Cancel"
            )
            .alert("Pitcher Share", isPresented: $showPitcherShareError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(pitcherShareError ?? "Something went wrong.")
            }
            .appConfirmationDialog(
                isPresented: $showCopyPitcherConfirm,
                title: "Copy pitcher?",
                message: "This creates a new pitcher profile you own, with the same stats. It won’t affect the shared pitcher.",
                primaryTitle: "Copy",
                primaryAction: {
                    if let pitcher = copyPitcherTarget {
                        copyPitcher(pitcher)
                    }
                    copyPitcherTarget = nil
                },
                secondaryTitle: "Cancel",
                secondaryAction: {
                    copyPitcherTarget = nil
                }
            )
            .appConfirmationDialog(
                isPresented: $showRevokePitcherConfirm,
                title: "Stop sharing?",
                message: "Anyone you shared this pitcher with loses access, and any invite links you sent stop working. Pitches they already recorded stay on the record.",
                primaryTitle: "Stop Sharing",
                primaryRole: .destructive,
                primaryAction: {
                    if let pitcher = revokePitcherTarget {
                        revokePitcherSharing(pitcher)
                    }
                    revokePitcherTarget = nil
                },
                secondaryTitle: "Cancel",
                secondaryAction: {
                    revokePitcherTarget = nil
                }
            )
            // No toolbar: Join a Game moved into Home's row of three
            // (2026-11-10). The X that used to sit there (go to the Game
            // tab, gated on "Select Game First") is gone too - the bottom
            // tab bar controls flow between Home/Game/Moments.
            .sheet(item: $editorTemplate) { template in
                TemplateEditorView(
                    template: template,
                    allPitches: allPitches,
                    onSave: { updatedTemplate in
                        handleSavedTemplate(updatedTemplate)
                    }
                )
                .fixedAppDynamicType()
            }
            .appConfirmationDialog(
                isPresented: $showPurchasedTemplateEditAlert,
                title: "Edit Purchased Template?",
                message: "This grid key has already been used in a store purchase. Changes you make now will only affect future use and future orders. Existing purchased orders will not change.",
                primaryTitle: "Continue Editing",
                primaryAction: {
                    editorTemplate = purchasedTemplateEditTarget
                    purchasedTemplateEditTarget = nil
                },
                secondaryTitle: "Cancel",
                secondaryAction: {
                    purchasedTemplateEditTarget = nil
                }
            )
            .sheet(isPresented: $showAddPitcher) {
                addPitcherSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showHomeAddPlayer) {
                homeAddPlayerSheet
            }
            .sheet(isPresented: $showPitcherPhotoPicker) {
                PitcherImagePicker { image in
                    showPitcherPhotoPicker = false
                    handlePickedPitcherPortrait(image)
                }
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $showPitcherPortraitEditor) {
                if let sourceImage = pitcherPortraitSourceImage, let target = pitcherPortraitTarget {
                    PitcherPortraitCropEditor(
                        sourceImage: sourceImage,
                        pitcherName: target.name,
                        onCancel: {
                            resetPitcherPortraitEditorState()
                        },
                        onSave: { croppedImage in
                            savePitcherPortrait(croppedImage)
                        }
                    )
                    .fixedAppDynamicType()
                }
            }
            .alert("Pitcher Image", isPresented: $showPitcherImageError) {
                Button("OK", role: .cancel) {
                    pitcherImageErrorMessage = ""
                }
            } message: {
                Text(pitcherImageErrorMessage)
            }
            .sheet(item: $statsPitcher) { pitcher in
                PitcherStatsSheetView(
                    pitcher: pitcher,
                    combinedPitcherIds: statsPitcherIds,
                    games: games,
                    teams: statsTeams
                )
                .environmentObject(authManager)
                .fixedAppDynamicType()
            }
            .sheet(item: $statsHitter) { hitter in
                HitterStatsView(
                    hitter: hitter,
                    combinedHitterIds: statsHitterIds,
                    games: games,
                    teams: statsTeams
                )
                .environmentObject(authManager)
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $showLinkProfiles) {
                LinkProfilesView(
                    onChanged: {
                        refreshMyTeams()
                        refreshMyHitters()
                    },
                    openGameTeamIds: openGameTeamIds,
                    onCloseGame: { closeOpenGame() }
                )
                .environmentObject(authManager)
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $showPlayersFilterSheet) {
                playersFilterSheetView
                    .fixedAppDynamicType()
            }
        }
        .fixedAppDynamicType()
    }
}

private struct PitcherImagePicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}

private struct PitcherPortraitCropEditor: View {
    let sourceImage: UIImage
    let pitcherName: String
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @State private var zoom: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var dragBaseOffset: CGSize = .zero

    private let previewSize: CGFloat = 280
    private let outputSize: CGFloat = 512

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Crop Image")
                    .font(.headline)
                Text(pitcherName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                GeometryReader { _ in
                    let baseSize = fittedSize(for: sourceImage.size, in: CGSize(width: previewSize, height: previewSize))
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: baseSize.width * zoom, height: baseSize.height * zoom)
                        .offset(dragOffset)
                        .clipped()
                }
                .frame(width: previewSize, height: previewSize)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                )
                .contentShape(Circle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = CGSize(
                                width: dragBaseOffset.width + value.translation.width,
                                height: dragBaseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragBaseOffset = dragOffset
                        }
                )
            }
            .frame(width: previewSize, height: previewSize)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Resize")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Reset") {
                        zoom = 1.0
                        dragOffset = .zero
                        dragBaseOffset = .zero
                    }
                    .font(.footnote.weight(.semibold))
                }

                Slider(value: $zoom, in: 1.0...2.8)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Use Image") {
                    onSave(renderCroppedImage())
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationDetents([.fraction(0.72)])
        .presentationDragIndicator(.visible)
    }

    private func fittedSize(for imageSize: CGSize, in targetSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetSize }
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func renderCroppedImage() -> UIImage {
        let targetSize = CGSize(width: outputSize, height: outputSize)
        let normalizedImage = sourceImage.normalizedUpOrientation()
        let baseSize = fittedSize(for: normalizedImage.size, in: CGSize(width: previewSize, height: previewSize))
        let offsetScale = outputSize / previewSize
        let renderSize = CGSize(width: baseSize.width * zoom * offsetScale, height: baseSize.height * zoom * offsetScale)
        let origin = CGPoint(
            x: dragOffset.width * offsetScale,
            y: dragOffset.height * offsetScale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            context.cgContext.addEllipse(in: CGRect(origin: .zero, size: targetSize))
            context.cgContext.clip()
            normalizedImage.draw(in: CGRect(origin: origin, size: renderSize))
        }
    }
}

struct PitcherStatsSheetView: View {
    enum DateRangeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case last7 = "Last 7"
        case last30 = "Last 30"
        case last90 = "Last 90"
        case custom = "Custom"

        var id: String { rawValue }
    }

    enum StatScope: String, CaseIterable, Identifiable {
        case games = "Games"

        var id: String { rawValue }
    }


    enum SummaryDetail: String, Identifiable {
        case swingK = "Swing K"
        case lookK = "Look ꓘ"
        case hitSpot = "Hit-Spot %"

        var id: String { rawValue }
    }

    enum HitSpotSuccessFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case highestToLowest = "Highest to Lowest (Most Thrown)"

        var id: String { rawValue }
    }

    enum HitSpotOrder: String, CaseIterable, Identifiable {
        case chronological = "Chronological"
        case reverseChronological = "Reverse Chronological"

        var id: String { rawValue }
    }

    let pitcher: Pitcher
    let availablePitchers: [Pitcher]
    /// Every pitching record of the same *person* - more than one once two
    /// separately-entered roster entries with tracked history were linked
    /// (`mergeTeamPlayerIntoPlayer` never moves events). Outside a locked
    /// game they're read together as one history; inside one, the tracker's
    /// per-record selection still applies.
    let combinedPitcherIds: [String]
    let games: [Game]
    let lockToGameId: String?
    let liveId: String?
    let ownerUserId: String?
    /// Optional - when non-empty, a "Teams" filter row toggles whole teams'
    /// worth of games in/out of `selectedGameIds` at once (per-team, a few
    /// combined, or none selected = every team/career-wide, the existing
    /// default). Empty by default so existing call sites are unaffected.
    let teams: [Team]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    init(
        pitcher: Pitcher,
        availablePitchers: [Pitcher]? = nil,
        combinedPitcherIds: [String] = [],
        games: [Game],
        lockToGameId: String? = nil,
        liveId: String? = nil,
        ownerUserId: String? = nil,
        teams: [Team] = []
    ) {
        self.pitcher = pitcher
        self.availablePitchers = availablePitchers ?? [pitcher]
        self.combinedPitcherIds = combinedPitcherIds
        self.games = games
        self.lockToGameId = lockToGameId
        self.liveId = liveId
        self.ownerUserId = ownerUserId
        self.teams = teams
        _selectedPitcherId = State(initialValue: pitcher.id)
    }

    @State private var dateFilter: DateRangeFilter = .all
    @State private var scope: StatScope = .games

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    @State private var selectedGameIds: Set<String> = []
    /// The Teams chips. Empty means All - every team, career-wide.
    @State private var selectedTeamIds: Set<String> = []
    @State private var cachedGameIdsWithEvents: Set<String> = []

    @State private var gameEvents: [PitchEvent] = []
    @State private var liveEvents: [PitchEvent] = []
    @State private var sharedGameEvents: [PitchEvent] = []
    @State private var liveEventsListener: ListenerRegistration? = nil
    @State private var sharedPitcherEventsListeners: [ListenerRegistration] = []
    @State private var sharedEventsByPitcherId: [String: [PitchEvent]] = [:]
    @State private var cachedStats: PitcherStatsDoc? = nil
    @State private var isLoading = false
    @State private var hasLoadedEvents = false
    @State private var loadEventsToken = UUID()
    @State private var summaryDetail: SummaryDetail? = nil
    @State private var showGameSummarySheet = false
    @State private var hitSpotPitchFilter: String = "All"
    @State private var hitSpotSuccessFilter: HitSpotSuccessFilter = .all
    @State private var hitSpotOrder: HitSpotOrder = .chronological
    @State private var selectedHeatmapPitch: String = ""
    @State private var heatmapZoneFilter: HeatmapZoneFilter = .all
    @State private var selectedPitcherId: String?

    private enum HeatmapZoneFilter: String, CaseIterable, Identifiable {
        case all = "Strikes+Balls"
        case onlyStrikes = "Only Strikes"
        case onlyBalls = "Only Balls"

        var id: String { rawValue }
    }

    /// Every game that counts toward this viewer's stats - archived ones
    /// only when they chose to keep them (see `gameCountsInStats`).
    private var activeGames: [Game] {
        games.filter { authManager.gameCountsInStats($0) }
    }

    /// Includes the stats choice so flipping it re-runs the selection and
    /// load exactly like an archive does.
    private var gameStateSignature: [String] {
        games.map { game in
            let counts = authManager.gameCountsInStats(game) ? 1 : 0
            return "\(game.id ?? "")|\(game.archivedAt?.timeIntervalSince1970 ?? 0)|\(counts)"
        }
    }

    private var sortedGames: [Game] {
        activeGames.sorted { $0.date > $1.date }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private var selectablePitchers: [Pitcher] {
        let base = availablePitchers.isEmpty ? [pitcher] : availablePitchers
        return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var activePitcher: Pitcher {
        if let selectedPitcherId,
           let match = selectablePitchers.first(where: { $0.id == selectedPitcherId }) {
            return match
        }
        return selectablePitchers.first ?? pitcher
    }

    private var activePitcherId: String? {
        activePitcher.id
    }

    /// The records this sheet reads: the selected one, plus the rest of the
    /// same person's when not locked to a game.
    private var activePitcherIds: Set<String> {
        guard let activePitcherId else { return [] }
        guard lockToGameId == nil, combinedPitcherIds.contains(activePitcherId) else {
            return [activePitcherId]
        }
        return Set(combinedPitcherIds)
    }

    private var gamesWithPitcherEvents: [Game] {
        let gameIdsWithEvents: Set<String> = {
            if !cachedGameIdsWithEvents.isEmpty {
                return cachedGameIdsWithEvents
            }
            return Set(combinedGameEvents.compactMap { $0.gameId })
        }()
        return sortedGames.filter { game in
            guard let id = game.id else { return false }
            return gameIdsWithEvents.contains(id)
        }
    }

    /// `gamesWithPitcherEvents` narrowed to the selected Teams chips.
    private var gamesForSelectedTeams: [Game] {
        guard !selectedTeamIds.isEmpty else { return gamesWithPitcherEvents }
        return gamesWithPitcherEvents.filter { TeamFilterChips.game($0, belongsTo: selectedTeamIds) }
    }

    private var allGameIds: Set<String> {
        Set(gamesForSelectedTeams.compactMap { $0.id })
    }

    /// The locked game always counts: opening an excluded archived game
    /// and asking for its own stats should still show them.
    private var validGameIds: Set<String> {
        var ids = Set(sortedGames.compactMap { $0.id })
        if let lockToGameId { ids.insert(lockToGameId) }
        return ids
    }

    private func formattedDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private var scopeSelectionLabel: String {
        if selectedGameIds.count == 1,
           let id = selectedGameIds.first,
           let game = sortedGames.first(where: { $0.id == id }) {
            return "vs \(game.opponent) • \(formattedDate(game.date))"
        }
        if selectedGameIds.isEmpty || selectedGameIds == allGameIds {
            return "All Games"
        }
        return "Multiple Games"
    }

    private var dateRange: ClosedRange<Date>? {
        switch dateFilter {
        case .all:
            return nil
        case .last7:
            return (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())...Date()
        case .last30:
            return (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())...Date()
        case .last90:
            return (Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())...Date()
        case .custom:
            return min(startDate, endDate)...max(startDate, endDate)
        }
    }

    private var filteredEvents: [PitchEvent] {
        if let lockedGameId = lockToGameId {
            let lockedEvents = combinedGameEvents.filter { event in
                if let gid = event.gameId, !gid.isEmpty { return gid == lockedGameId }
                return liveId != nil
            }
            let pitcherFiltered = filterEventsForActivePitcher(lockedEvents)
            guard let range = dateRange else { return pitcherFiltered }
            return pitcherFiltered.filter { range.contains($0.timestamp) }
        }

        // Intersected with the Teams chips' games, so an empty game selection
        // (read as "all") can never widen past the chosen teams.
        let effectiveGameIds = (selectedGameIds.isEmpty ? allGameIds : selectedGameIds).intersection(allGameIds)
        let byScopeSelection: [PitchEvent] = {
            if effectiveGameIds.isEmpty { return [] }
            return combinedGameEvents.filter { event in
                if let gid = event.gameId { return effectiveGameIds.contains(gid) }
                return false
            }
        }()

        let byDate: [PitchEvent] = {
            guard let range = dateRange else { return byScopeSelection }
            return byScopeSelection.filter { range.contains($0.timestamp) }
        }()

        return filterEventsForActivePitcher(byDate)
    }

    private func filterEventsForActivePitcher(_ events: [PitchEvent]) -> [PitchEvent] {
        let pitcherIds = Set(activePitcherIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !pitcherIds.isEmpty else {
            return events
        }
        return events.filter { event in
            guard let eventPitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines), !eventPitcherId.isEmpty else {
                return false
            }
            return pitcherIds.contains(eventPitcherId)
        }
    }

    private enum ResultType {
        case strike, ball
    }

    private func resultType(for event: PitchEvent) -> ResultType? {
        switch inferredPitchResultType(for: event) {
        case .strike:
            return .strike
        case .ball:
            return .ball
        case nil:
            return nil
        }
    }

    private var activeStats: PitcherStatsDoc? {
        // Use cached aggregates only before events have loaded for this sheet session.
        // After loading completes, always render from filteredEvents so date/scope filters
        // immediately reflect user changes (including zero-result ranges).
        hasLoadedEvents ? nil : cachedStats
    }

    private var strikeCount: Int {
        activeStats?.strikeCount ?? filteredEvents.filter { resultType(for: $0) == .strike }.count
    }

    private var totalCount: Int {
        activeStats?.totalCount ?? filteredEvents.count
    }

    private var strikePercent: Int {
        statPercent(strikeCount, of: totalCount)
    }

    private var ballCount: Int {
        activeStats?.ballCount ?? filteredEvents.filter { resultType(for: $0) == .ball }.count
    }

    private var ballPercent: Int {
        statPercent(ballCount, of: totalCount)
    }

    private var locationAnalyticsEligibleCount: Int {
        filteredEvents.filter(\.supportsLocationAnalytics).count
    }

    private var swingingStrikeCount: Int {
        activeStats?.swingingStrikeCount ?? filteredEvents.filter(PitchStatsCalculator.isStrikeoutSwinging).count
    }

    private var lookingStrikeCount: Int {
        activeStats?.lookingStrikeCount ?? filteredEvents.filter(PitchStatsCalculator.isStrikeoutLooking).count
    }

    private var swingingStrikeEvents: [PitchEvent] {
        filteredEvents.filter(PitchStatsCalculator.isStrikeoutSwinging)
    }

    private var lookingStrikeEvents: [PitchEvent] {
        filteredEvents.filter(PitchStatsCalculator.isStrikeoutLooking)
    }

    private var wildPitchCount: Int {
        activeStats?.wildPitchCount ?? filteredEvents.filter { $0.wildPitch }.count
    }

    private var passedBallCount: Int {
        activeStats?.passedBallCount ?? filteredEvents.filter { $0.passedBall }.count
    }

    private var walkCount: Int {
        return activeStats?.walkCount ?? filteredEvents.filter(PitchStatsCalculator.isWalk).count
    }

    private var hitCount: Int {
        return filteredEvents.filter(eventCountsAsHit).count
    }

    private func eventCountsAsHit(_ event: PitchEvent) -> Bool {
        pitchEventIsCreditedHit(event)
    }

    private var hitSpotCount: Int {
        activeStats?.hitSpotCount ?? filteredEvents.filter { $0.supportsLocationAnalytics && strictIsLocationMatch($0) }.count
    }

    private var hitSpotEvents: [PitchEvent] {
        filteredEvents.filter { $0.supportsLocationAnalytics && strictIsLocationMatch($0) }
    }

    private var hitSpotPercent: Int {
        statPercent(hitSpotCount, of: locationAnalyticsEligibleCount)
    }

    private var firstPitchStrike: (made: Int, total: Int) {
        sharedFirstPitchStrikeMetrics(for: filteredEvents)
    }

    private var firstPitchStrikePercent: Int {
        statPercent(firstPitchStrike.made, of: firstPitchStrike.total)
    }

    private var hasLocationAnalytics: Bool {
        filteredEvents.contains(where: \.supportsLocationAnalytics)
    }

    private var outcomesSummary: [(label: String, count: Int, jerseys: String)] {
        if let stats = activeStats {
            return stats.outcomeStats.map { key, value in
                let jerseys = value.jerseys.sorted().joined(separator: ", ")
                return (label: key, count: value.count, jerseys: jerseys)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
        }

        var counts: [String: Int] = [:]
        var jerseysByOutcome: [String: Set<String>] = [:]
        for event in filteredEvents {
            if let outcome = event.outcome, !outcome.isEmpty {
                counts[outcome, default: 0] += 1
                if let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
                    jerseysByOutcome[outcome, default: []].insert(jersey)
                }
            }
        }
        return counts.map { key, value in
            let jerseys = jerseysByOutcome[key, default: []].sorted().joined(separator: ", ")
            return (label: key, count: value, jerseys: jerseys)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private var selectedSingleGameIdForSummary: String? {
        if let locked = lockToGameId, !locked.isEmpty { return locked }
        guard scope == .games, selectedGameIds.count == 1 else { return nil }
        return selectedGameIds.first
    }

    private var selectedSingleGameForSummary: Game? {
        guard let gameId = selectedSingleGameIdForSummary else { return nil }
        return games.first(where: { $0.id == gameId })
    }

    private var selectedGameSummaryEvents: [PitchEvent] {
        guard let gameId = selectedSingleGameIdForSummary else { return [] }
        return filterEventsForActivePitcher(combinedGameEvents)
            .filter { ($0.gameId ?? "") == gameId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var heatmapPitchTypes: [String] {
        HeatmapSelection.pitchTypes(filteredEvents)
    }

    private var selectedHeatmapPitchResolved: String? {
        if !selectedHeatmapPitch.isEmpty, heatmapPitchTypes.contains(selectedHeatmapPitch) {
            return selectedHeatmapPitch
        }
        return heatmapPitchTypes.first
    }

    private var heatmapEventsForSelectedPitchFiltered: [PitchEvent] {
        guard let pitch = selectedHeatmapPitchResolved else { return [] }
        let zone: HeatmapSelection.Zone = {
            switch heatmapZoneFilter {
            case .all: return .all
            case .onlyStrikes: return .strikes
            case .onlyBalls: return .balls
            }
        }()
        return HeatmapSelection.events(filteredEvents, pitch: pitch, zone: zone)
    }

    private var heatmapCountByPitch: [String: Int] {
        HeatmapSelection.counts(filteredEvents)
    }

    private var pitchStats: [(name: String, count: Int, hitSpotPct: Int)] {
        if let stats = activeStats {
            let rows = stats.pitchStats.map { key, value in
                let total = value.count
                let hitSpotPct = statPercent(value.hitSpotCount, of: total)
                return (key, total, hitSpotPct)
            }
            return rows
                .filter { $0.0 != "Catcher" }
                .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
        }

        let grouped = Dictionary(grouping: filteredEvents, by: { $0.pitch })
        var rows: [(String, Int, Int)] = []
        for (pitch, events) in grouped {
            let total = events.count
            let eligible = events.filter(\.supportsLocationAnalytics).count
            let hitSpots = events.filter { $0.supportsLocationAnalytics && strictIsLocationMatch($0) }.count
            let hitSpotPct = statPercent(hitSpots, of: eligible)
            rows.append((pitch, total, hitSpotPct))
        }
        return rows
            .filter { $0.0 != "Catcher" }
            .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }

    private func summaryDetailRows(
        for events: [PitchEvent],
        includeJerseyNumbers: Bool
    ) -> [(pitch: String, location: String, count: Int, jerseys: String)] {
        var counts: [String: Int] = [:]
        var jerseysByKey: [String: Set<String>] = [:]
        for event in events {
            let pitch = event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let safePitch = pitch.isEmpty ? "Unknown Pitch" : pitch
            let safeLocation = location.isEmpty ? "Unknown Location" : location
            let key = "\(safePitch)|\(safeLocation)"
            counts[key, default: 0] += 1
            if includeJerseyNumbers, let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
                jerseysByKey[key, default: []].insert(jersey)
            }
        }

        return counts.map { key, count in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let pitch = parts.first ?? "Unknown Pitch"
            let location = parts.count > 1 ? parts[1] : "Unknown Location"
            let jerseys = jerseysByKey[key, default: []].sorted().joined(separator: ", ")
            return (pitch, location, count, jerseys)
        }
        .sorted { lhs, rhs in
            if lhs.pitch == rhs.pitch { return lhs.location < rhs.location }
            return lhs.pitch < rhs.pitch
        }
    }

    private func hitSpotDetailRows() -> [(pitch: String, result: String, called: String, count: Int, isMatch: Bool, callKey: String)] {
        // Hit-Spot detail should list each pitch in sequence.
        var seenEventKeys: Set<String> = []

        let dedupedEvents: [PitchEvent] = filteredEvents.filter { event in
            let key: String
            if let id = event.id, !id.isEmpty {
                key = "id:\(id)"
            } else {
                let calledPitch = event.calledPitch?.pitch ?? ""
                let calledLocation = event.calledPitch?.location ?? ""
                key = [
                    String(event.timestamp.timeIntervalSince1970),
                    event.pitch,
                    event.location,
                    calledPitch,
                    calledLocation,
                    event.pitcherId ?? "",
                    event.gameId ?? ""
                ].joined(separator: "|")
            }

            guard !seenEventKeys.contains(key) else { return false }
            seenEventKeys.insert(key)
            return true
        }
        .sorted { $0.timestamp < $1.timestamp }

        return dedupedEvents.enumerated().map { index, event in
            let pitch = event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            let resultLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let intendedLocation = event.calledPitch?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let safePitch = pitch.isEmpty ? "Unknown Pitch" : pitch
            let safeResult = resultLocation.isEmpty ? "Unknown Location" : resultLocation
            let safeCalled: String = {
                if intendedLocation.isEmpty { return "Unknown Called" }
                if intendedLocation.hasPrefix("Strike ") || intendedLocation.hasPrefix("Ball ") {
                    return intendedLocation
                }
                let prefix = (event.calledPitch?.isStrike ?? false) ? "Strike " : "Ball "
                return prefix + intendedLocation
            }()
            let isMatch = strictIsLocationMatch(event)
            let callKey = "\(safePitch)|\(safeCalled)"
            return (
                pitch: safePitch,
                result: safeResult,
                called: safeCalled,
                count: index + 1,
                isMatch: isMatch,
                callKey: callKey
            )
        }
    }

    private func hitSpotRowColor(forLocation location: String) -> Color {
        if location.lowercased().hasPrefix("hit:") { return .green }
        if location.lowercased().hasPrefix("miss:") { return .red }
        return .secondary
    }

    private var summaryDetailContent: some View {
        let detail = summaryDetail
        let events: [PitchEvent]
        switch detail {
        case .swingK:
            events = swingingStrikeEvents
        case .lookK:
            events = lookingStrikeEvents
        case .hitSpot:
            events = []
        case .none:
            events = []
        }

        let includeJerseyNumbers = detail == .swingK || detail == .lookK
        let includeIntended = detail == .hitSpot
        let allRows: [(id: String, pitch: String, location: String, intended: String?, count: Int, jerseys: String, isMatch: Bool, callKey: String?)] = {
            if detail == .hitSpot {
                return hitSpotDetailRows().map { row in
                    (
                        id: "\(row.pitch)|\(row.result)|\(row.called)|\(row.count)",
                        pitch: row.pitch,
                        location: row.result,
                        intended: row.called,
                        count: row.count,
                        jerseys: "",
                        isMatch: row.isMatch,
                        callKey: row.callKey
                    )
                }
            }
            return summaryDetailRows(for: events, includeJerseyNumbers: includeJerseyNumbers).map { row in
                (
                    id: "\(row.pitch)|\(row.location)|\(row.jerseys)",
                    pitch: row.pitch,
                    location: row.location,
                    intended: nil,
                    count: row.count,
                    jerseys: row.jerseys,
                    isMatch: false,
                    callKey: nil
                    )
            }
        }()
        let hitSpotPitchOptions: [String] = {
            guard includeIntended else { return [] }
            let unique = Set(allRows.map { $0.pitch })
            return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }()
        let rowWidth: CGFloat = includeJerseyNumbers ? 400 : (includeIntended ? 430 : 300)
        let callSuccessByKey: [String: (hits: Int, total: Int)] = {
            var map: [String: (hits: Int, total: Int)] = [:]
            for row in allRows {
                guard includeIntended, let key = row.callKey else { continue }
                var current = map[key] ?? (hits: 0, total: 0)
                current.total += 1
                if row.isMatch { current.hits += 1 }
                map[key] = current
            }
            return map
        }()
        let rows: [(id: String, pitch: String, location: String, intended: String?, count: Int, jerseys: String, isMatch: Bool, callKey: String?)] = {
            guard includeIntended else { return allRows }
            var filtered = allRows
            if hitSpotPitchFilter != "All" {
                filtered = filtered.filter { $0.pitch == hitSpotPitchFilter }
            }
            if hitSpotSuccessFilter == .highestToLowest {
                filtered.sort { lhs, rhs in
                    let l = lhs.callKey.flatMap { callSuccessByKey[$0] } ?? (hits: 0, total: 0)
                    let r = rhs.callKey.flatMap { callSuccessByKey[$0] } ?? (hits: 0, total: 0)
                    let lPct = l.total == 0 ? 0.0 : Double(l.hits) / Double(l.total)
                    let rPct = r.total == 0 ? 0.0 : Double(r.hits) / Double(r.total)
                    if lPct != rPct { return lPct > rPct }
                    if l.total != r.total { return l.total > r.total }
                    if hitSpotOrder == .reverseChronological {
                        return lhs.count > rhs.count
                    }
                    return lhs.count < rhs.count
                }
                // When success sorting is active, repeated exact matches for the same
                // pitch/called/result combination don't add value because the Success
                // column already represents the aggregate.
                var seenMatchedKeys: Set<String> = []
                filtered = filtered.filter { row in
                    guard row.isMatch else { return true }
                    let key = "\(row.pitch)|\(row.intended ?? "")|\(row.location)"
                    guard !seenMatchedKeys.contains(key) else { return false }
                    seenMatchedKeys.insert(key)
                    return true
                }
            } else if hitSpotOrder == .reverseChronological {
                filtered.reverse()
            }
            return filtered
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(detail?.rawValue ?? "Details")
                    .font(.headline)
                Spacer()
                if includeIntended {
                    Menu {
                        Section("Pitch Type") {
                            Button {
                                hitSpotPitchFilter = "All"
                            } label: {
                                Label("All", systemImage: hitSpotPitchFilter == "All" ? "checkmark" : "")
                            }
                            ForEach(hitSpotPitchOptions, id: \.self) { pitch in
                                Button {
                                    hitSpotPitchFilter = pitch
                                } label: {
                                    Label(pitch, systemImage: hitSpotPitchFilter == pitch ? "checkmark" : "")
                                }
                            }
                        }
                        Section("% Success") {
                            ForEach(HitSpotSuccessFilter.allCases) { option in
                                Button {
                                    hitSpotSuccessFilter = option
                                } label: {
                                    Label(option.rawValue, systemImage: hitSpotSuccessFilter == option ? "checkmark" : "")
                                }
                            }
                        }
                        Section("Order") {
                            ForEach(HitSpotOrder.allCases) { option in
                                Button {
                                    hitSpotOrder = option
                                } label: {
                                    Label(option.rawValue, systemImage: hitSpotOrder == option ? "checkmark" : "")
                                }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            Divider()
            if rows.isEmpty {
                Text("No pitches recorded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 2) {
                            if includeIntended {
                                HStack(spacing: 4) {
                                    Text("Success")
                                    if hitSpotSuccessFilter != .all {
                                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                            .font(.caption2)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            }
                            HStack(spacing: 4) {
                                Text("Pitch")
                                if includeIntended && hitSpotPitchFilter != "All" {
                                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                            Text(includeIntended ? "Called" : "Location")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: includeIntended ? 125 : 150, alignment: .leading)
                            if includeIntended {
                                Text("Result")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 125, alignment: .leading)
                            }
                            if includeJerseyNumbers {
                                Text("Batters")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90, alignment: .leading)
                            }
                        }
                        .frame(width: rowWidth, alignment: .center)
                        ForEach(rows, id: \.id) { row in
                            HStack(spacing: 2) {
                                if includeIntended {
                                    let stat = row.callKey.flatMap { callSuccessByKey[$0] } ?? (hits: 0, total: 0)
                                    let pct = statPercent(stat.hits, of: stat.total)
                                    Text("\(pct)% (\(stat.hits)/\(stat.total))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                }
                                Text(row.pitch)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 70, alignment: .leading)
                                Text(includeIntended ? (row.intended ?? "") : row.location)
                                    .font(.subheadline)
                                    .foregroundColor(includeIntended ? .primary : hitSpotRowColor(forLocation: row.location))
                                    .frame(width: includeIntended ? 125 : 150, alignment: .leading)
                                if includeIntended {
                                    Text(row.location.isEmpty ? "—" : row.location)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .frame(width: 125, alignment: .leading)
                                }
                                if includeJerseyNumbers {
                                    Text(row.jerseys.isEmpty ? "—" : row.jerseys)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(
                                includeIntended && row.isMatch
                                ? Color.green.opacity(0.18)
                                : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: rowWidth, alignment: .center)
                        }
                    }
                    .frame(minWidth: rowWidth, alignment: .leading)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 12)
        .padding()
        .presentationDetents([.medium, .large])
        .onChange(of: summaryDetail) { _, newValue in
            guard newValue == .hitSpot else { return }
            hitSpotPitchFilter = "All"
            hitSpotSuccessFilter = .all
            hitSpotOrder = .chronological
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lockToGameId == nil {
                        HStack(alignment: .center, spacing: 12) {
                            Text(activePitcher.name)
                                .font(.title2.weight(.semibold))

                            Spacer(minLength: 8)
                            VStack(spacing: 8) {
                                Picker("Scope", selection: $scope) {
                                    ForEach(StatScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                            .fixedSize()

                                scopeSelectionMenu
                            }
                        }
                        .padding(.horizontal)

                        teamFilterRow

                        if scope == .games {
                            HStack {
                                Spacer()
                                Button {
                                    showGameSummarySheet = true
                                } label: {
                                    Label("Game Summary", systemImage: "doc.text")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedSingleGameIdForSummary == nil)
                                Spacer()
                            }
                            .padding(.horizontal)

                            if selectedSingleGameIdForSummary == nil {
                                Text("Select one game to open the game summary.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal)
                            }
                        }

                        summarySection
                        if shouldShowDatePickerSection {
                            statsPickerSection
                        }
                    } else {
                        HStack(spacing: 0) {
                            Spacer(minLength: 12)

                            HStack(alignment: .center, spacing: 12) {
                                if lockToGameId != nil, selectablePitchers.count > 1 {
                                    ScrollableSelectionMenuButton(
                                        title: "Pitcher",
                                        items: selectablePitchers,
                                        itemTitle: { $0.name },
                                        isSelected: { $0.id == selectedPitcherId },
                                        onSelect: { pitcher in
                                            selectedPitcherId = pitcher.id
                                        }
                                    ) {
                                        Text(
                                            selectedPitcherId.flatMap { id in selectablePitchers.first(where: { $0.id == id })?.name }
                                            ?? activePitcher.name
                                        )
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    }
                                } else {
                                    Text(activePitcher.name)
                                        .font(.title2.weight(.semibold))
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Game")
                                        .font(.headline)
                                    if let lockedGameId = lockToGameId,
                                       let game = games.first(where: { $0.id == lockedGameId }) {
                                        Text("vs. \(game.opponent)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Selected game")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )

                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal)

                        summarySection
                    }
                    pitchBreakdownSection
                    outcomesSection
                    heatMapSection
                    if hasCatcherReads {
                        catcherReadsSection
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Pitcher Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $summaryDetail) { _ in
                summaryDetailContent
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $showGameSummarySheet) {
                if let game = selectedSingleGameForSummary {
                    SettingsGameSummarySheetView(
                        pitcherName: activePitcher.name,
                        game: game,
                        events: selectedGameSummaryEvents
                    )
                    .fixedAppDynamicType()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Select one game to view a game summary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.fraction(0.3)])
                    .fixedAppDynamicType()
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .onAppear {
                initializeSelections()
                loadEvents()
                loadCachedStats()
                startLiveListener()
                startSharedPitcherListener()
            }
            .onChange(of: gameStateSignature) { _, _ in
                initializeSelections()
                loadEvents()
                loadCachedStats()
            }
            .onDisappear {
                stopLiveListener()
                stopSharedPitcherListener()
            }
            .onChange(of: selectedGameIds) { _, _ in
                loadEvents()
                loadCachedStats()
            }
            .onChange(of: selectedTeamIds) { _, _ in
                // Every game of the chosen teams (all games for All).
                selectedGameIds = allGameIds
            }
            .onChange(of: scope) { _, _ in
                if lockToGameId != nil {
                    scope = .games
                }
                loadEvents()
                loadCachedStats()
            }
            .onChange(of: liveId) { _, _ in
                startLiveListener()
            }
            .onChange(of: selectedPitcherId) { _, _ in
                cachedGameIdsWithEvents = []
                loadEvents()
                startSharedPitcherListener()
                loadCachedStats()
                startLiveListener()
            }
        }
    }

    private var statsPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Date Range", selection: $dateFilter) {
                ForEach(DateRangeFilter.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if dateFilter == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                .padding(.horizontal)
            }
        }
    }

    private var heatMapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heat Map")
                .font(.headline)
                .padding(.horizontal)

            if !hasLocationAnalytics {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heat maps hidden for Track Game pitches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 220)
                        .overlay {
                            Text("Coach data needed")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .opacity(0.65)
                }
                .padding(.horizontal)
            } else if heatmapPitchTypes.isEmpty {
                Text("No pitches recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(heatmapPitchTypes, id: \.self) { pitch in
                            let isSelected = (selectedHeatmapPitchResolved == pitch)
                            let pitchCount = heatmapCountByPitch[pitch] ?? 0
                            Button {
                                selectedHeatmapPitch = pitch
                            } label: {
                                Text("\(pitch) \(pitchCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(isSelected ? Color.accentColor : Color(.systemGray6))
                                    )
                                    .overlay(
                                        Capsule().stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Picker("Zone Filter", selection: $heatmapZoneFilter) {
                    ForEach(HeatmapZoneFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                StrikeZoneHeatmapView(events: heatmapEventsForSelectedPitchFiltered)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .padding(.top, 18)
            }
        }
    }

    // MARK: - Catcher Reads

    /// Catcher-mode pitches (the coach watched, not called) within the
    /// current filter scope, regardless of whether an estimate was logged.
    private var catcherModeEvents: [PitchEvent] {
        filteredEvents.filter { $0.pitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher" }
    }

    private var hasCatcherReads: Bool {
        !catcherModeEvents.isEmpty
    }

    /// Catcher-mode pitches where the coach also estimated the opposing
    /// catcher's pitch type/location call (see `CatcherEstimateView`).
    private var catcherReadEvents: [PitchEvent] {
        catcherModeEvents.filter { $0.catcherEstimate != nil }
    }

    /// Location-only match between the coach's estimate and the actual
    /// result. Deliberately ignores pitch name (unlike `strictIsLocationMatch`)
    /// since the estimate's pitch type has no ground truth to check against -
    /// only the guessed target location does.
    private func catcherEstimateLocationMatches(_ event: PitchEvent) -> Bool {
        guard let estimate = event.catcherEstimate else { return false }

        func parse(_ raw: String) -> (type: String?, zone: String) {
            let manager = PitchLabelManager(batterSide: event.batterSide)
            let adjusted = manager.adjustedLabel(from: raw)
            let cleaned = adjusted
                .replacingOccurrences(of: "—", with: " ")
                .replacingOccurrences(of: "–", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if cleaned.hasPrefix("strike ") {
                return ("strike", String(cleaned.dropFirst("strike ".count)).trimmingCharacters(in: .whitespaces))
            } else if cleaned.hasPrefix("ball ") {
                return ("ball", String(cleaned.dropFirst("ball ".count)).trimmingCharacters(in: .whitespaces))
            }
            return (nil, cleaned)
        }

        let estimated = parse(estimate.location)
        let actual = parse(event.location)
        guard estimated.zone == actual.zone else { return false }
        let estimatedType = estimated.type ?? (estimate.isStrike ? "strike" : "ball")
        let actualType = actual.type ?? (event.isStrike ? "strike" : "ball")
        return estimatedType == actualType
    }

    private var catcherReadAccuracyPercent: Int {
        statPercent(catcherReadEvents.filter(catcherEstimateLocationMatches).count, of: catcherReadEvents.count)
    }

    private var catcherEstimatedPitchBreakdown: [(name: String, count: Int)] {
        Dictionary(grouping: catcherReadEvents) { event -> String in
            let name = event.catcherEstimate?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Catcher"
            return name.isEmpty ? "Catcher" : name
        }
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }
    }

    /// Reuses `StrikeZoneHeatmapView`'s existing called-vs-actual plotting by
    /// swapping in the estimate as the "called" pitch for display only.
    private var catcherReadHeatmapEvents: [PitchEvent] {
        catcherReadEvents.map { event in
            var copy = event
            copy.calledPitch = event.catcherEstimate
            return copy
        }
    }

    private var catcherReadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Catcher Reads")
                .font(.headline)
                .padding(.horizontal)

            Text("Your estimate of what the catcher called, logged after each pitch tracked in Catcher mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if catcherReadEvents.isEmpty {
                Text("No estimates logged yet. Choose a pitch type and location on the estimate prompt after a catcher-mode pitch, then tap Done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(catcherReadEvents.count) of \(catcherModeEvents.count)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text("Pitches estimated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(catcherReadAccuracyPercent)%")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text("Estimate matched result")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(catcherEstimatedPitchBreakdown.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Circle()
                                .fill(colorForPitch(item.name))
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.count)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)

                StrikeZoneHeatmapView(
                    events: catcherReadHeatmapEvents,
                    interactionHint: "Estimated call → actual result"
                )
                .frame(maxWidth: .infinity)
                .padding(6)
                .padding(.top, 8)
            }
        }
    }

    private var shouldShowDatePickerSection: Bool {
        guard lockToGameId == nil else { return false }
        // Hide the date picker when a single specific game is selected from the game menu.
        if scope == .games, selectedGameIds.count == 1 {
            return false
        }
        return true
    }

    private var scopeSelectionMenu: some View {
        ScrollableSelectionMenuButton(
            title: "Games",
            items: gamesForSelectedTeams,
            topActions: [
                SelectionSheetAction(
                    title: "All Games",
                    systemImage: selectedGameIds.count == allGameIds.count ? "checkmark" : nil
                ) {
                    selectedGameIds = allGameIds
                }
            ],
            itemTitle: { game in
                "vs \(game.opponent) • \(formattedDate(game.date))\(game.isArchived ? " • Archived" : "")"
            },
            isSelected: { game in
                guard let id = game.id else { return false }
                return selectedGameIds.count == 1 && selectedGameIds.contains(id)
            },
            onSelect: { game in
                if let id = game.id {
                    selectedGameIds = [id]
                }
            }
        ) {
            HStack(spacing: 8) {
                Text(scopeSelectionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal)
    }

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
                .padding(.horizontal)

            Picker("Date Range", selection: $dateFilter) {
                ForEach(DateRangeFilter.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if dateFilter == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                .padding(.horizontal)
            }
        }
    }

    private var lockedGameHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game")
                .font(.headline)
                .padding(.horizontal)
            if let lockedGameId = lockToGameId,
               let game = games.first(where: { $0.id == lockedGameId }) {
                Text("vs. \(game.opponent)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                Text("Selected game")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

        }
    }

    /// Shared with HitterStatsView. Narrowing to teams also narrows the
    /// Games menu and resets the game selection to those teams' games.
    @ViewBuilder
    private var teamFilterRow: some View {
        if !teams.isEmpty {
            TeamFilterChips(teams: teams, selectedTeamIds: $selectedTeamIds)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Total", value: "\(totalCount)")
                statCard(title: "Strike %", value: "\(strikePercent)%")
                statCard(title: "Ball %", value: "\(ballPercent)%")
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    summaryDetail = .swingK
                } label: {
                    statCard(title: "Swing K", value: "\(swingingStrikeCount)")
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    summaryDetail = .lookK
                } label: {
                    statCard(title: "Look ꓘ", value: "\(lookingStrikeCount)")
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)

                Group {
                    if hasLocationAnalytics {
                        Button {
                            summaryDetail = .hitSpot
                        } label: {
                            statCard(title: "Hit-Spot %", value: "\(hitSpotPercent)%")
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "chevron.down")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .padding(10)
                                }
                        }
                        .buttonStyle(.plain)
                    } else {
                        statCard(title: "Hit-Spot %", value: "Coach data")
                            .opacity(0.45)
                    }
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Walks", value: "\(walkCount)")
                statCard(title: "Hits", value: "\(hitCount)")
                statCard(title: "Wild", value: "\(wildPitchCount)")
                statCard(title: "Passed", value: "\(passedBallCount)")
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                statCard(title: "Strikes", value: "\(strikeCount)")
                statCard(title: "Balls", value: "\(ballCount)")
                statCard(title: "1st Pitch Strike", value: "\(firstPitchStrikePercent)%")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes (\(strikeCount)) / Total Pitches (\(totalCount))")
                Text("Ball % = Balls (\(ballCount)) / Total Pitches (\(totalCount))")
                Text("1st Pitch Strike % = Qualified first-pitch strikes (\(firstPitchStrike.made)) / New batter appearances (\(firstPitchStrike.total))")
                if hasLocationAnalytics {
                    Text("Hit-Spot % = Location matches (\(hitSpotCount)) / Coach-mode pitches (\(locationAnalyticsEligibleCount))")
                } else {
                    Text("Location-based metrics hidden for Track Game pitches.")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        }
    }

    private var pitchBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pitch Type Breakdown")
                .font(.headline)
                .padding(.horizontal)

            if pitchStats.isEmpty {
                Text("No pitch data yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Type")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text("Count")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Text("Hit %")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .opacity(hasLocationAnalytics ? 1 : 0.45)
                            .frame(width: 50, alignment: .trailing)
                    }

                    ForEach(Array(pitchStats.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 54, alignment: .leading)
                            Text("\(row.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Text(hasLocationAnalytics ? "\(row.hitSpotPct)%" : "—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .opacity(hasLocationAnalytics ? 1 : 0.45)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal)

            Text("Outcomes")
                .font(.headline)
                .padding(.horizontal)

            if outcomesSummary.isEmpty {
                Text("No outcomes recorded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Type")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text("#")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)
                        Text("Jersey")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 110, alignment: .leading)
                    }

                    ForEach(outcomesSummary, id: \.label) { item in
                        HStack(spacing: 4) {
                            Text(item.label)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 70, alignment: .trailing)
                            Text("\(item.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .center)
                            Text(item.jerseys.isEmpty ? "—" : item.jerseys)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 110, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private func initializeSelections() {
        if let selectedPitcherId,
           selectablePitchers.contains(where: { $0.id == selectedPitcherId }) {
            // keep current selection
        } else {
            selectedPitcherId = selectablePitchers.first?.id
        }

        if let lockedGameId = lockToGameId {
            scope = .games
            selectedGameIds = [lockedGameId]
            return
        }

        cachedGameIdsWithEvents = []

        let ids = sortedGames.compactMap { $0.id }
        selectedGameIds = Set(ids)
    }

    private func loadEvents() {
        let pitcherIds = activePitcherIds
        guard !pitcherIds.isEmpty else { return }
        let requestToken = UUID()
        loadEventsToken = requestToken

        isLoading = true
        hasLoadedEvents = false
        gameEvents = []
        liveEvents = []
        sharedGameEvents = []

        loadCareerEvents(pitcherIds: Array(pitcherIds)) { events in
            guard loadEventsToken == requestToken else { return }

            var sharedGameBucket: [PitchEvent] = []
            var seenIdentities = Set<String>()

            if !events.isEmpty {
                for event in events {
                    if event.mode == .game || (event.gameId?.isEmpty == false) {
                        sharedGameBucket.append(event)
                    }
                }
                seenIdentities = Set(sharedGameBucket.map { $0.identity })

                DispatchQueue.main.async {
                    self.gameEvents = sharedGameBucket
                }
            }

            guard let ownerUid = ownerUserId ?? authManager.user?.uid else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.hasLoadedEvents = true
                }
                return
            }

            let group = DispatchGroup()

            group.enter()
            authManager.loadPitchEvents { events in
                guard loadEventsToken == requestToken else { group.leave(); return }
                let filtered = events.filter {
                    pitcherIds.contains($0.pitcherId ?? "") && ($0.mode == .game || ($0.gameId?.isEmpty == false))
                }
                DispatchQueue.main.async {
                    let unique = filtered.filter { !seenIdentities.contains($0.identity) }
                    seenIdentities.formUnion(unique.map { $0.identity })
                    self.gameEvents.append(contentsOf: unique)
                    group.leave()
                }
            }

            let gameIdsToLoad: [String] = {
                if let lockedGameId = lockToGameId { return [lockedGameId] }
                return selectedGameIds.isEmpty ? sortedGames.compactMap { $0.id } : Array(selectedGameIds)
            }()

            for gameId in gameIdsToLoad {
                group.enter()
                authManager.loadGamePitchEvents(ownerUserId: ownerUid, gameId: gameId) { events in
                    guard loadEventsToken == requestToken else { group.leave(); return }
                    let filtered = events.filter { pitcherIds.contains($0.pitcherId ?? "") }
                    DispatchQueue.main.async {
                        let unique = filtered.filter { !seenIdentities.contains($0.identity) }
                        seenIdentities.formUnion(unique.map { $0.identity })
                        self.gameEvents.append(contentsOf: unique)
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                guard loadEventsToken == requestToken else { return }
                let ids = Set(self.combinedGameEvents.compactMap { $0.gameId })
                if !ids.isEmpty {
                    self.cachedGameIdsWithEvents.formUnion(ids)
                }
                self.isLoading = false
                self.hasLoadedEvents = true
            }
        }
    }

    /// `loadPitcherEvents` for each record, concatenated. Each record's
    /// collection holds different pitches, so there's nothing to dedupe.
    private func loadCareerEvents(pitcherIds: [String], completion: @escaping ([PitchEvent]) -> Void) {
        var collected: [PitchEvent] = []
        let group = DispatchGroup()
        for pitcherId in pitcherIds {
            group.enter()
            authManager.loadPitcherEvents(pitcherId: pitcherId) { events in
                DispatchQueue.main.async {
                    collected.append(contentsOf: events)
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(collected) }
    }

    private var combinedGameEvents: [PitchEvent] {
        mergeUnique([gameEvents, liveEvents, sharedGameEvents]).filter { event in
            if let gid = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines), !gid.isEmpty {
                return validGameIds.contains(gid)
            }
            return lockToGameId != nil && liveId != nil
        }
    }

    private func statsScopeKey() -> (scope: String, scopeId: String)? {
        if let lockedGameId = lockToGameId {
            return ("game", lockedGameId)
        }

        if selectedGameIds.count == 1, let gid = selectedGameIds.first {
            return ("game", gid)
        }

        return nil
    }

    private func loadCachedStats() {
        cachedStats = nil
        // Cached aggregates are per record; with several, wait for events.
        guard activePitcherIds.count == 1, let pitcherId = activePitcherId else { return }
        guard let key = statsScopeKey() else { return }

        let docId: String = {
            switch key.scope {
            case "overall":
                return "overall"
            case "game":
                return "game_\(key.scopeId)"
            case "practice":
                return "practice_\(key.scopeId)"
            default:
                return "overall"
            }
        }()

        let ref = Firestore.firestore()
            .collection("pitchers").document(pitcherId)
            .collection("stats").document(docId)

        ref.getDocument { snap, error in
            if let error {
                debugLog("❌ loadCachedStats error:", error.localizedDescription)
                return
            }
            guard let snap, snap.exists else { return }
            Task { @MainActor in
                do {
                    let doc = try snap.data(as: PitcherStatsDoc.self)
                    self.cachedStats = doc
                } catch {
                    debugLog("❌ decode cached stats failed:", error.localizedDescription)
                }
            }
        }
    }

    private func startLiveListener() {
        stopLiveListener()
        liveEvents = []
        let pitcherIds = activePitcherIds
        guard let liveId, !liveId.isEmpty, !pitcherIds.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        liveEventsListener = ref.addSnapshotListener { snapshot, error in
            if let error {
                debugLog("❌ live stats pitchEvents listener error:", error.localizedDescription)
                return
            }

            let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            } ?? []

            let filtered = events.filter { pitcherIds.contains($0.pitcherId ?? "") }
            DispatchQueue.main.async {
                self.liveEvents = filtered
            }
        }
    }

    private func stopLiveListener() {
        liveEventsListener?.remove()
        liveEventsListener = nil
    }

    private func startSharedPitcherListener() {
        stopSharedPitcherListener()
        sharedGameEvents = []
        sharedEventsByPitcherId = [:]

        for pitcherId in activePitcherIds.sorted() {
            let ref = Firestore.firestore()
                .collection("pitchers").document(pitcherId)
                .collection("pitchEvents")
                .order(by: "timestamp", descending: false)

            let listener = ref.addSnapshotListener { snapshot, error in
                if let error {
                    debugLog("❌ shared pitcherEvents listener error:", error.localizedDescription)
                    return
                }

                let docs = snapshot?.documents ?? []
                debugLog("🧾 shared pitcherEvents snapshot count=\(docs.count) pitcherId=\(pitcherId)")

                let events: [PitchEvent] = docs.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                }

                let sharedGame = events.filter { $0.mode == .game || ($0.gameId?.isEmpty == false) }

                if let sample = events.last {
                    debugLog("🧾 shared pitcherEvents sample gameId=\(sample.gameId ?? "<nil>") mode=\(sample.mode.rawValue) pitcherId=\(sample.pitcherId ?? "<nil>") location=\(sample.location)")
                }

                DispatchQueue.main.async {
                    self.sharedEventsByPitcherId[pitcherId] = sharedGame
                    self.sharedGameEvents = self.sharedEventsByPitcherId.keys.sorted()
                        .flatMap { self.sharedEventsByPitcherId[$0] ?? [] }
                }
            }
            sharedPitcherEventsListeners.append(listener)
        }
    }

    private func stopSharedPitcherListener() {
        sharedPitcherEventsListeners.forEach { $0.remove() }
        sharedPitcherEventsListeners = []
    }

    private func mergeUnique(_ groups: [[PitchEvent]]) -> [PitchEvent] {
        var seen = Set<String>()
        var merged: [PitchEvent] = []
        for group in groups {
            for event in group {
                let key = logicalEventKey(for: event)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                merged.append(event)
            }
        }
        return merged
    }

    // Use a logical key so mirrored copies of the same pitch event (different Firestore doc IDs)
    // are counted once in stats sheets.
    private func logicalEventKey(for event: PitchEvent) -> String {
        let ts = String(format: "%.6f", event.timestamp.timeIntervalSince1970)
        let mode = event.mode.rawValue
        let gameId = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let batterId = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calledPitch = event.calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calledLocation = event.calledPitch?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            ts,
            mode,
            event.pitch,
            event.location,
            calledPitch,
            calledLocation,
            gameId,
            pitcherId,
            batterId,
            jersey
        ].joined(separator: "|")
    }
}


// MARK: - Player archive confirmation

struct PendingPlayerArchive {
    let pitcherIds: [String]
    /// Everyone this hides - normally one name. More than one means the
    /// records are shared between kids, and the dialog says so.
    let names: [String]

    var title: String {
        names.count > 1 ? "Archive \(names.count) Players?" : "Archive \(names.first ?? "Player")?"
    }

    var message: String {
        let effect = "Hidden from your Players list, pitcher pickers, and every game's bench and batter list. Nothing is deleted - stats stay, and you can unarchive anytime (Players → Show Archived, or swipe right on a team roster)."
        guard names.count > 1 else { return effect }
        return "This will hide \(ArchiveScope.sentence(names)) - they share records. If you meant only one of them, cancel and fix the link in Link Profiles first.\n\n" + effect
    }
}

// MARK: - Open game lock

/// While a game is open in the tracker, the players and teams on either
/// side of it can't be archived or taken off a roster - the lineup, bench
/// and batter pickers are using them. Close Game (Home's Games menu, or
/// the button on this dialog) releases the lock. Unarchiving and Restore
/// are never locked.
enum OpenGameLock {
    static let title = "Game in Progress"

    static func teamIds(activeGameId: String?, games: [Game]) -> Set<String> {
        guard let activeGameId, let game = games.first(where: { $0.id == activeGameId }) else { return [] }
        return Set([game.teamId, game.awayTeamId].compactMap { $0 }.filter { !$0.isEmpty })
    }

    static func message(for subject: String, plural: Bool = false, then action: String = "archive") -> String {
        "\(subject) \(plural ? "are" : "is") on a team in the game that's open right now. Close the game first, then \(action)."
    }
}

// MARK: - Archive Game dialog

extension View {
    /// The one place a game gets archived, from Home or the game picker.
    /// Archiving never deletes; the only question is whether this user's
    /// stats keep counting the game (every pitch in it, both teams). The
    /// answer stays changeable from the archived game's menu.
    /// Root of Home (CLAUDE.md, Dialogs): confirms a Disconnect or End
    /// Live Session picked from a game row's ⋯ menu.
    func homeLiveLeaveDialog(pending: Binding<HomeLiveLeave?>, onConfirm: @escaping (HomeLiveLeave) -> Void) -> some View {
        let current = pending.wrappedValue
        return appConfirmationDialog(
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            title: current?.title ?? "",
            message: current?.message ?? "",
            primaryTitle: current?.confirmTitle ?? "OK",
            primaryRole: .destructive,
            primaryAction: {
                if let current { onConfirm(current) }
            },
            secondaryTitle: "Cancel"
        )
    }

    func archiveGameDialog(
        game: Binding<Game?>,
        title: @escaping (Game) -> String,
        onArchive: @escaping (Game, _ keepInStats: Bool) -> Void
    ) -> some View {
        // Captured now: the dialog clears `isPresented` (and so the binding)
        // before it runs the chosen action.
        let current = game.wrappedValue
        let name = current.map(title) ?? ""
        return appConfirmationDialog(
            isPresented: Binding(
                get: { game.wrappedValue != nil },
                set: { if !$0 { game.wrappedValue = nil } }
            ),
            title: "Archive Game?",
            message: (name.isEmpty ? "This game" : "\"\(name)\"")
                + " will be hidden from your games. Nothing is deleted, and you can unarchive it anytime.\n\n"
                + "Should its pitches still count in your players' stats? This covers both teams in this game. You can change it later from the game's menu.",
            primaryTitle: "Archive, Keep Stats",
            primaryAction: {
                if let current { onArchive(current, true) }
            },
            secondaryTitle: "Cancel",
            alternateTitle: "Archive, Remove from Stats",
            alternateAction: {
                if let current { onArchive(current, false) }
            }
        )
    }
}

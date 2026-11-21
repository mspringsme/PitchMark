//
//  TradingCardViews.swift
//  PitchMark
//
//  Trading card screens (2026-11-19): the designer, the team roster's
//  Team Trading Cards section, a team set, and Team Supplies' list of the
//  family's cards. Rules and rendering are in TradingCard.swift.
//

import SwiftUI
import UIKit
import PhotosUI
import FirebaseAuth

private func priceText(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: "USD"))
}

/// The full-screen working overlay (the app's loading convention).
private struct WorkingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(message).foregroundStyle(.white).font(.subheadline)
            }
        }
    }
}

// MARK: - Roster section

struct TeamTradingCardsSection: View {
    let team: Team
    let players: [TeamPlayer]
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var setStore = TeamCardSetStore()
    @StateObject private var designStore = TradingCardDesignStore()
    @State private var showPlayerPicker = false
    @State private var editing: TradingCardDesign? = nil
    @State private var openSet: TeamCardSet? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    var body: some View {
        Section {
            ForEach(setStore.sets) { set in
                Button {
                    openSet = set
                } label: {
                    HStack {
                        Label(set.name, systemImage: "rectangle.stack")
                        Spacer()
                        Text(statusText(set.status)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                showPlayerPicker = true
            } label: {
                Label("Make a Trading Card", systemImage: "person.crop.rectangle")
            }
            .accessibilityIdentifier("team.makeCard")
            if !setStore.sets.contains(where: { $0.status == .open }) {
                Button {
                    startSet()
                } label: {
                    Label("Start a Team Card Set", systemImage: "rectangle.stack.badge.plus")
                }
                .accessibilityIdentifier("team.startCardSet")
            }
        } header: {
            Text("Team Trading Cards")
        } footer: {
            Text("Each family makes their player's card. A team set gives every family one card of every player - one order, shipped to the organizer to hand out.")
        }
        .onAppear {
            setStore.start(teamId: team.id)
            designStore.start(uid: authManager.user?.uid)
        }
        .appSheet(isPresented: $showPlayerPicker, chrome: .handle) {
            NavigationStack {
                List(players, id: \.id) { player in
                    Button(player.name) {
                        showPlayerPicker = false
                        let existing = designStore.designs.first { $0.teamPlayerId == player.id && $0.teamId == team.id }
                        let design = existing ?? TradingCardDesign.forPlayer(player, team: team)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editing = design }
                    }
                }
                .navigationTitle("Whose card?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPlayerPicker = false } } }
            }
            .fixedAppDynamicType()
        }
        .appSheet(item: $editing, chrome: .handle) { design in
            NavigationStack { TradingCardDesignerView(design: design) }
                .fixedAppDynamicType()
        }
        .appSheet(item: $openSet, chrome: .handle) { set in
            NavigationStack { TeamCardSetView(team: team, setId: set.id, store: setStore, players: players) }
                .fixedAppDynamicType()
        }
        .appConfirmationDialog(
            isPresented: $showError,
            title: "Something went wrong",
            message: errorMessage ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
    }

    private func statusText(_ status: TeamCardSet.Status) -> String {
        switch status {
        case .open: return "Gathering cards"
        case .locked: return "Locked"
        case .ordered: return "Ordered"
        }
    }

    private func startSet() {
        guard let teamId = team.id else { return }
        let year = Calendar.current.component(.year, from: Date())
        Task {
            do {
                try await TradingCardOrders.startSet(teamId: teamId, name: "\(team.name) \(year) Cards")
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Designer

struct TradingCardDesignerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var authManager: AuthManager
    @State var design: TradingCardDesign
    @StateObject private var setStore = TeamCardSetStore()
    @State private var photo: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showBack = false
    @State private var preview: UIImage? = nil
    @State private var working: String? = nil
    @State private var loadingStats = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var pendingPack: TradingCardProduct.FamilyPack? = nil
    @State private var showPackDialog = false
    @State private var pendingSet: TeamCardSet? = nil
    @State private var showConsentDialog = false
    @State private var submittedMessage: String? = nil
    @State private var showSubmitted = false

    private var openSets: [TeamCardSet] { setStore.sets.filter { $0.status == .open } }

    var body: some View {
        Form {
            Section {
                Picker("Side", selection: $showBack) {
                    Text("Front").tag(false)
                    Text("Back").tag(true)
                }
                .pickerStyle(.segmented)
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("card.preview")
                }
            }

            Section("Template") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(TradingCardTemplate.allCases) { template in
                            Button(template.displayName) { design.templateId = template.rawValue }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(design.templateId == template.rawValue
                                                           ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
                                .foregroundStyle(design.templateId == template.rawValue ? Color.white : Color.primary)
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("card.template.\(template.rawValue)")
                        }
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photo == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                }
            }

            Section("Player") {
                limitedField("Name", text: $design.playerName, max: TradingCardDesign.nameMax)
                limitedField("Number", text: $design.jerseyNumber, max: 4)
                limitedField("Position", text: $design.position, max: TradingCardDesign.shortMax)
                limitedField("Team", text: $design.teamName, max: TradingCardDesign.nameMax)
                limitedField("Bats / Throws", text: $design.batsThrows, max: TradingCardDesign.shortMax)
                limitedField("Favorite player", text: $design.favoritePlayer, max: TradingCardDesign.shortMax)
                limitedField("Fun fact", text: $design.funFact, max: TradingCardDesign.funFactMax)
            }

            Section {
                if !design.hitterId.isEmpty {
                    Button(design.stats.isEmpty ? "Add Career Stats" : "Refresh Stats") { loadStats() }
                        .disabled(loadingStats)
                }
                if !design.stats.isEmpty {
                    Text(design.stats.map { "\($0.label) \($0.value)" }.joined(separator: "  "))
                        .font(.caption.monospaced())
                    Button("Remove Stats", role: .destructive) {
                        design.stats = []
                        design.statsLabel = ""
                    }
                }
            } header: {
                Text("Stats on the back")
            } footer: {
                if design.hitterId.isEmpty { Text("Make the card from a roster player to add their stats.") }
            }

            Section {
                ForEach(TradingCardProduct.FamilyPack.allCases) { pack in
                    Button("Order Family Pack of \(pack.rawValue) - \(priceText(pack.priceCents))") {
                        pendingPack = pack
                        showPackDialog = true
                    }
                    .accessibilityIdentifier("card.order.\(pack.rawValue)")
                }
            } header: {
                Text("For your family")
            }

            if !openSets.isEmpty {
                Section("Team set") {
                    ForEach(openSets) { set in
                        Button("Add to \(set.name)") {
                            pendingSet = set
                            showConsentDialog = true
                        }
                        .accessibilityIdentifier("card.submit")
                    }
                }
            }
        }
        .navigationTitle("Trading Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    TradingCardDesignStore.save(design)
                    dismiss()
                }
            }
        }
        .onAppear {
            photo = TradingCardPhotos.load(for: design.id)
            setStore.start(teamId: design.teamId.isEmpty ? nil : design.teamId)
            render()
        }
        .onChange(of: design) { _, _ in render() }
        .onChange(of: showBack) { _, _ in render() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                    TradingCardPhotos.save(image, for: design.id)
                    render()
                }
            }
        }
        .overlay { if let working { WorkingOverlay(message: working) } }
        .appConfirmationDialog(
            isPresented: $showPackDialog,
            title: "Order \(pendingPack?.rawValue ?? 12) cards?",
            message: "\(pendingPack?.rawValue ?? 12) copies of this card, front and back, shipped to you. Check the name and spelling first.",
            primaryTitle: "Continue to Checkout",
            primaryAction: { if let pendingPack { orderPack(pendingPack) } },
            secondaryTitle: "Cancel"
        )
        .appConfirmationDialog(
            isPresented: $showConsentDialog,
            title: "Add this card to the team set?",
            message: "I'm this player's parent or guardian. I agree that this card - photo, name, number and stats - is printed for every family on \(design.teamName). You can take it back until the organizer locks the set.",
            primaryTitle: "I Agree - Add Card",
            primaryAction: { if let pendingSet { submit(to: pendingSet) } },
            secondaryTitle: "Cancel"
        )
        .appConfirmationDialog(
            isPresented: $showSubmitted,
            title: "Card added",
            message: submittedMessage ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
        .appConfirmationDialog(
            isPresented: $showError,
            title: "Something went wrong",
            message: errorMessage ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
    }

    private func limitedField(_ title: String, text: Binding<String>, max: Int) -> some View {
        TextField(title, text: text)
            .onChange(of: text.wrappedValue) { _, new in
                if new.count > max { text.wrappedValue = String(new.prefix(max)) }
            }
    }

    private func render() {
        preview = showBack ? TradingCardRenderer.renderBack(design) : TradingCardRenderer.renderFront(design, photo: photo)
    }

    private func loadStats() {
        loadingStats = true
        TradingCardStats.load(hitterId: design.hitterId, authManager: authManager) { stats in
            design.stats = stats
            design.statsLabel = "Career"
            loadingStats = false
        }
    }

    private func orderPack(_ pack: TradingCardProduct.FamilyPack) {
        TradingCardDesignStore.save(design)
        working = "Making your cards…"
        Task {
            do {
                let url = try await TradingCardOrders.orderFamilyPack(design, photo: photo, pack: pack)
                working = nil
                openURL(url)
            } catch {
                working = nil
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func submit(to set: TeamCardSet) {
        TradingCardDesignStore.save(design)
        working = "Adding your card…"
        Task {
            do {
                try await TradingCardOrders.submit(design, photo: photo, teamId: design.teamId, setId: set.id)
                working = nil
                submittedMessage = "Your card is in \(set.name). Have another player on the team? Make their card too. You can take a card back from the set until it's locked."
                showSubmitted = true
            } catch {
                working = nil
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Team set

struct TeamCardSetView: View {
    let team: Team
    let setId: String
    @ObservedObject var store: TeamCardSetStore
    let players: [TeamPlayer]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var entriesStore = TeamCardEntriesStore()
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var sets = 1
    @State private var didSetCount = false
    @State private var working: String? = nil
    @State private var previewURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var currentSet: TeamCardSet? { store.sets.first { $0.id == setId } }
    private var uid: String? { Auth.auth().currentUser?.uid }
    private var isOrganizer: Bool { currentSet?.organizerUid == uid && uid != nil }
    private var entries: [TeamCardEntry] {
        let sorted = TeamCardSetPlan.sorted(entriesStore.entries.map(\.planCard)).map(\.id)
        return sorted.compactMap { id in entriesStore.entries.first { $0.id == id } }
    }

    /// Roster players with no card yet (matched by number, else name).
    private var missing: [TeamPlayer] {
        players.filter { player in
            !entries.contains { entry in
                if let number = player.jerseyNumber, !number.isEmpty, number == entry.jerseyNumber { return true }
                return entry.playerName.localizedCaseInsensitiveCompare(player.name) == .orderedSame
            }
        }
    }

    var body: some View {
        List {
            if let set = currentSet {
                Section {
                    Text(statusLine(set)).font(.subheadline)
                }

                Section("Cards (\(entries.count))") {
                    if entries.isEmpty {
                        Text("No cards yet. Each family adds theirs from Make a Trading Card.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        HStack(spacing: 12) {
                            Group {
                                if let image = thumbnails[entry.id] {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15))
                                }
                            }
                            .frame(width: 44, height: 60)
                            VStack(alignment: .leading) {
                                Text(entry.playerName).font(.headline)
                                if !entry.jerseyNumber.isEmpty {
                                    Text("#\(entry.jerseyNumber)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .task(id: entry.frontPath) {
                            thumbnails[entry.id] = await TradingCardOrders.downloadArt(entry.frontPath)
                        }
                        .swipeActions {
                            if set.status == .open && (isOrganizer || entry.ownerUid == uid) {
                                Button(entry.ownerUid == uid ? "Take Back" : "Remove", role: .destructive) {
                                    run("Removing…") {
                                        try await TradingCardOrders.withdraw(teamId: team.id ?? "", setId: setId, entry: entry)
                                    }
                                }
                            }
                        }
                    }
                }

                if !missing.isEmpty && set.status == .open {
                    Section("Still waiting on") {
                        ForEach(missing, id: \.id) { player in
                            Text(player.name).foregroundStyle(.secondary)
                        }
                    }
                }

                if isOrganizer {
                    organizerSection(set)
                }
            }
        }
        .navigationTitle(currentSet?.name ?? "Team Cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear {
            if let teamId = team.id { entriesStore.start(teamId: teamId, setId: setId) }
        }
        .onChange(of: entriesStore.entries.count) { _, count in
            if !didSetCount, count > 0 {
                sets = min(max(count, TradingCardProduct.minSets), TradingCardProduct.maxSets)
                didSetCount = true
            }
        }
        .overlay { if let working { WorkingOverlay(message: working) } }
        .appSheet(item: Binding(get: { previewURL.map { PreviewFile(url: $0) } }, set: { previewURL = $0?.url })) { file in
            ShareLink(item: file.url) { Label("Share Set PDF", systemImage: "square.and.arrow.up") }
                .padding()
                .presentationDetents([.fraction(0.2)])
        }
        .appConfirmationDialog(
            isPresented: $showError,
            title: "Something went wrong",
            message: errorMessage ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
    }

    @ViewBuilder
    private func organizerSection(_ set: TeamCardSet) -> some View {
        Section {
            switch set.status {
            case .open:
                Button("Lock the Set") {
                    run("Locking…") { try await TradingCardOrders.setLocked(true, teamId: team.id ?? "", setId: setId) }
                }
                .disabled(entries.count < TradingCardProduct.minPlayers)
                .accessibilityIdentifier("cardSet.lock")
            case .locked:
                Stepper("Sets to order: \(sets)", value: $sets, in: TradingCardProduct.minSets...TradingCardProduct.maxSets)
                Text("\(sets) sets × \(entries.count) cards · \(priceText(TradingCardProduct.teamSetPriceCents(sets: sets)))")
                    .font(.headline)
                Button("Order Team Set") {
                    run("Starting checkout…") {
                        let url = try await TradingCardOrders.orderTeamSet(teamId: team.id ?? "", setId: setId, sets: sets)
                        openURL(url)
                    }
                }
                .accessibilityIdentifier("cardSet.order")
                Button("Preview Set PDF") { previewPDF() }
                Button("Reopen for Changes") {
                    run("Reopening…") { try await TradingCardOrders.setLocked(false, teamId: team.id ?? "", setId: setId) }
                }
            case .ordered:
                Text("Ordered. The sets ship to you to hand out.")
                Button("Preview Set PDF") { previewPDF() }
            }
        } header: {
            Text("Organizer")
        } footer: {
            if set.status == .open {
                Text("Lock the set when every family's card is in. Nobody can change a card once it's locked; you can reopen it until you order. One set per family, each with one card of every player, \(priceText(TradingCardProduct.teamSetPriceCents)) a set.")
            }
        }
    }

    private func statusLine(_ set: TeamCardSet) -> String {
        switch set.status {
        case .open: return "Gathering cards. Each family adds their player's card with their consent."
        case .locked: return "Locked - ready to order."
        case .ordered: return "Ordered."
        }
    }

    private func run(_ message: String, _ action: @escaping () async throws -> Void) {
        working = message
        Task {
            do {
                try await action()
                working = nil
            } catch {
                working = nil
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func previewPDF() {
        let cards = entries
        let count = sets
        run("Making the PDF…") {
            var art: [String: (front: UIImage, back: UIImage)] = [:]
            for entry in cards {
                if let front = await TradingCardOrders.downloadArt(entry.frontPath),
                   let back = await TradingCardOrders.downloadArt(entry.backPath) {
                    art[entry.id] = (front, back)
                }
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("team-cards-\(setId).pdf")
            try TeamCardSetPlan.writePDF(cards.map(\.planCard), sets: count, art: art, to: url)
            previewURL = url
        }
    }
}

private struct PreviewFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

// MARK: - Team Supplies

/// Team Supplies → Keepsakes → Trading Cards: the family's saved cards.
struct TradingCardsLibraryView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var store = TradingCardDesignStore()
    @State private var editing: TradingCardDesign? = nil

    var body: some View {
        List {
            Section {
                Text("Make your player's card from your team's roster (Home → Teams → your team → Make a Trading Card). Order a Family Pack here, or add it to your team's set.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !store.designs.isEmpty {
                Section("Your cards") {
                    ForEach(store.designs) { design in
                        Button {
                            editing = design
                        } label: {
                            VStack(alignment: .leading) {
                                Text(design.playerName.isEmpty ? "#\(design.jerseyNumber)" : design.playerName).font(.headline)
                                Text(design.teamName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Prices") {
                ForEach(TradingCardProduct.FamilyPack.allCases) { pack in
                    LabeledContent("Family Pack of \(pack.rawValue)", value: priceText(pack.priceCents))
                }
                LabeledContent("Team Set, per family", value: priceText(TradingCardProduct.teamSetPriceCents))
            }
        }
        .navigationTitle("Trading Cards")
        .onAppear { store.start(uid: authManager.user?.uid) }
        .appSheet(item: $editing, chrome: .handle) { design in
            NavigationStack { TradingCardDesignerView(design: design) }
                .fixedAppDynamicType()
        }
    }
}

//
//  LineupScanSheet.swift
//  PitchMark
//
//  Scan Opponent Lineup: pick screenshots (or use the camera), read them,
//  then review before anything is written. The sheet never writes - the
//  presenter does, through `onConfirm`, and reports back.
//

import SwiftUI
import PhotosUI

struct LineupScanSheet: View {
    let teamName: String
    /// The opponent's roster, for matching. Nil while it loads.
    let roster: [TeamPlayer]?
    /// Hitter ids already in this game's lineup (shown, then skipped).
    var alreadyInLineup: Set<String> = []
    var confirmTitle: String = "Add to Game"
    /// Hands over the reviewed batters; call `done(nil)` when written
    /// (the sheet closes) or `done(message)` to show what went wrong.
    var onConfirm: (_ decisions: [LineupScanDecision], _ done: @escaping (String?) -> Void) -> Void
    var onCancel: () -> Void

    private enum Stage { case pick, review }

    @State private var stage: Stage = .pick
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isReading = false
    @State private var isSaving = false
    @State private var list = LineupReviewList(rows: [])
    @State private var showOthers = false
    @State private var message: String? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationView {
            Group {
                switch stage {
                case .pick: pickView
                case .review: reviewView
                }
            }
            .navigationTitle("Scan Opponent Lineup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                if stage == .review {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
        .overlay {
            if isReading || isSaving {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text(isReading ? "Reading lineup…" : "Adding players…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            LineupScanCamera(
                onFinish: { images in
                    showCamera = false
                    read(images)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            loadPhotos(items)
        }
    }

    // MARK: Pick

    private var pickView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a screenshot of \(teamName)'s lineup, or take a photo of the screen it's on. Long lineups can take more than one screenshot - pick them in order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    Label("Choose Screenshots", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pitchMarkActiveGray)
                .controlSize(.large)
                .accessibilityIdentifier("lineupScan.photos")

                if LineupScanCamera.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take a Photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    list = LineupReviewList(rows: [])
                    list.addBlank()
                    stage = .review
                } label: {
                    Text("Type it in instead")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("The image is read on this phone and isn't saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        isReading = true
        message = nil
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            await MainActor.run {
                photoItems = []
                read(images)
            }
        }
    }

    private func read(_ images: [UIImage]) {
        guard !images.isEmpty else {
            isReading = false
            message = "Couldn't open that image."
            return
        }
        isReading = true
        message = nil
        Task {
            let scanned = await LineupScanReader.rows(from: images)
            await MainActor.run {
                isReading = false
                guard !scanned.isEmpty else {
                    message = "No lineup found in that image. Try a closer screenshot, or type it in."
                    return
                }
                list = LineupReviewList(rows: scanned)
                showOthers = list.kept.isEmpty
                stage = .review
            }
        }
    }

    // MARK: Review

    private func scanRow(_ item: LineupReviewItem) -> LineupScanRow {
        let name = item.name.trimmingCharacters(in: .whitespaces)
        let jersey = item.jersey.trimmingCharacters(in: .whitespaces)
        return LineupScanRow(order: nil, jersey: jersey.isEmpty ? nil : jersey, name: name.isEmpty ? nil : name, needsCheck: item.readCheck)
    }

    private var rosterEntries: [LineupRosterEntry] {
        (roster ?? []).compactMap { player in
            guard let id = player.id else { return nil }
            return LineupRosterEntry(rowId: id, name: player.name, jersey: player.jerseyNumber, archived: player.archivedAt != nil)
        }
    }

    /// Matching over the kept rows only, each row's manual choice laid
    /// over it. Keyed by row id.
    private var matches: [UUID: LineupMatch] {
        let kept = list.kept
        let auto = LineupRosterMatch.match(kept.map(scanRow), roster: rosterEntries)
        var result: [UUID: LineupMatch] = [:]
        for (item, match) in zip(kept, auto) {
            switch item.choice {
            case .player(let id): result[item.id] = LineupMatch(rowId: id, suggestedRowId: nil, needsCheck: false)
            case .new: result[item.id] = LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: false)
            case nil: result[item.id] = match
            }
        }
        return result
    }

    private func rosterPlayer(_ rowId: String?) -> TeamPlayer? {
        guard let rowId else { return nil }
        return roster?.first(where: { $0.id == rowId })
    }

    private func rosterLabel(_ player: TeamPlayer) -> String {
        if let jersey = player.jerseyNumber, !jersey.isEmpty, NumberOnlyName.number(in: player.name) == nil {
            return "#\(jersey) \(player.name)"
        }
        return player.name
    }

    private func binding(_ id: UUID) -> Binding<LineupReviewItem> {
        Binding(
            get: { list.item(id) ?? LineupReviewItem(id: id, readIndex: 0, jersey: "", name: "", readCheck: false, keep: false) },
            set: { list.update($0) }
        )
    }

    private var reviewView: some View {
        let matches = self.matches
        let kept = list.kept
        let others = list.others
        return VStack(spacing: 0) {
            List {
                Section {
                    ForEach(Array(kept.enumerated()), id: \.element.id) { index, item in
                        reviewRow(binding(item.id), number: index + 1, match: matches[item.id])
                    }
                    .onDelete { list.deleteKept(atOffsets: $0) }
                    .onMove { list.moveKept(fromOffsets: $0, toOffset: $1) }

                    Button {
                        list.addBlank()
                    } label: {
                        Label("Add Batter", systemImage: "plus")
                    }
                } header: {
                    Text("\(teamName) · batting order")
                } footer: {
                    Text(roster == nil
                         ? "Loading the roster to find players you've seen before…"
                         : "Untick a row to leave it out. Players already on \(teamName)'s roster keep their history; new ones are added to it.")
                }

                if !others.isEmpty {
                    Section {
                        Button {
                            withAnimation { showOthers.toggle() }
                        } label: {
                            HStack {
                                Text("Other text found (\(others.count))")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(showOthers ? 0 : -90))
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lineupScan.others")

                        if showOthers {
                            ForEach(others) { item in
                                otherRow(item)
                            }
                        }
                    } footer: {
                        Text("Not added. Tick anything that's really a batter.")
                    }
                }
            }
            .listStyle(.insetGrouped)

            VStack(spacing: 8) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    confirm(matches)
                } label: {
                    Text(confirmButtonTitle(matches))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pitchMarkActiveGray)
                .controlSize(.large)
                .disabled(decisions(matches).isEmpty || roster == nil || isSaving)
                .accessibilityIdentifier("lineupScan.confirm")
            }
            .padding()
            .background(.bar)
        }
    }

    private func confirmButtonTitle(_ matches: [UUID: LineupMatch]) -> String {
        let count = decisions(matches).count
        return count == 0 ? confirmTitle : "\(confirmTitle) (\(count))"
    }

    private func keepBox(_ item: LineupReviewItem) -> some View {
        Button {
            withAnimation { list.setKeep(item.id, !item.keep) }
        } label: {
            Image(systemName: item.keep ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(item.keep ? Color.pitchMarkActiveGray : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.keep ? "Kept" : "Not kept")
    }

    private func otherRow(_ item: LineupReviewItem) -> some View {
        HStack(spacing: 10) {
            keepBox(item)
            Text([item.jersey.isEmpty ? nil : "#\(item.jersey)", item.name.isEmpty ? nil : item.name]
                    .compactMap { $0 }.joined(separator: " "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func reviewRow(_ row: Binding<LineupReviewItem>, number: Int, match: LineupMatch?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                keepBox(row.wrappedValue)
                Text("\(number)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                TextField("#", text: row.jersey)
                    .keyboardType(.numberPad)
                    .frame(width: 44)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: row.wrappedValue.jersey) { _ in row.wrappedValue.choice = nil }
                TextField("Name (optional)", text: row.name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: row.wrappedValue.name) { _ in row.wrappedValue.choice = nil }
            }
            if let match {
                matchLabel(row: row, match: match)
                    .padding(.leading, 62)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func matchLabel(row binding: Binding<LineupReviewItem>, match: LineupMatch) -> some View {
        let row = binding.wrappedValue
        let isEmpty = row.jersey.trimmingCharacters(in: .whitespaces).isEmpty && row.name.trimmingCharacters(in: .whitespaces).isEmpty
        if isEmpty {
            Text("Needs a number or a name")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let player = rosterPlayer(match.rowId) {
            HStack(spacing: 6) {
                if match.needsCheck { checkTag }
                Label("Matches \(rosterLabel(player))", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hitterId = player.hitterId, alreadyInLineup.contains(hitterId) {
                    Text("· already batting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Not them") { binding.wrappedValue.choice = .new }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        } else if let suggested = rosterPlayer(match.suggestedRowId), let id = suggested.id {
            HStack(spacing: 6) {
                checkTag
                Text("Roster has \(rosterLabel(suggested))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Same player") { binding.wrappedValue.choice = .player(id) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: 6) {
                if match.needsCheck { checkTag }
                Text("New player")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var checkTag: some View {
        Text("Check this")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    /// Kept rows only, in batting order.
    private func decisions(_ matches: [UUID: LineupMatch]) -> [LineupScanDecision] {
        list.kept.compactMap { item in
            let row = scanRow(item)
            guard row.jersey != nil || row.name != nil else { return nil }
            let player = rosterPlayer(matches[item.id]?.rowId)
            return LineupScanDecision(
                name: row.savedName,
                jersey: row.jersey,
                existingRowId: player?.id,
                existingHitterId: player?.hitterId
            )
        }
    }

    private func confirm(_ matches: [UUID: LineupMatch]) {
        let chosen = decisions(matches)
        guard !chosen.isEmpty else { return }
        isSaving = true
        message = nil
        onConfirm(chosen) { error in
            isSaving = false
            if let error { message = error }
        }
    }
}

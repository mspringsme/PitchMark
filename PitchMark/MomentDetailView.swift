//
//  MomentDetailView.swift
//  PitchMark
//
//  Phase 7a - the real Moment detail/edit screen. Replaces
//  MomentsLibraryView's old behavior of opening VideoPlayer directly on
//  tap; this view owns playback plus everything editable about a Moment.
//  "Capture now, create later" extends to editing too: nothing here is
//  required, every field commits immediately on its own rather than
//  needing a separate Save step. Deliberately kept out of the Pitchmark
//  Display target's membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import AVKit
import PhotosUI
import FirebaseFirestore

private struct FullScreenPhoto: Identifiable {
    let id: Int
    let image: UIImage
}

struct MomentDetailView: View {
    let moment: Moment
    /// All the user's Moments, newest first (already loaded by
    /// MomentsLibraryView) - used only to suggest "Copy from N min ago"
    /// when this Moment has no game info yet.
    let allMoments: [Moment]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isFavorite: Bool
    @State private var opponent: String
    @State private var score: String
    @State private var inningText: String
    @State private var gameInfoUpdatedAt: Date?

    @State private var photoCount: Int
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var fullScreenPhoto: FullScreenPhoto? = nil

    init(moment: Moment, allMoments: [Moment]) {
        self.moment = moment
        self.allMoments = allMoments
        _isFavorite = State(initialValue: moment.isFavorite ?? false)
        _opponent = State(initialValue: moment.opponent ?? "")
        _score = State(initialValue: moment.score ?? "")
        _inningText = State(initialValue: moment.inning.map(String.init) ?? "")
        _gameInfoUpdatedAt = State(initialValue: moment.gameInfoUpdatedAt)
        _photoCount = State(initialValue: moment.photoCount ?? 0)
    }

    private var momentId: String { moment.id ?? "" }

    private var copySuggestion: (source: Moment, minutesAgo: Int)? {
        guard opponent.isEmpty, score.isEmpty, inningText.isEmpty else { return nil }
        guard let source = allMoments.first(where: {
            $0.id != moment.id && ($0.opponent != nil || $0.score != nil || $0.inning != nil)
        }) else { return nil }
        let referenceDate = source.gameInfoUpdatedAt ?? source.createdAt
        let minutes = max(0, Int(Date().timeIntervalSince(referenceDate) / 60))
        return (source, minutes)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    playbackSection
                    gameInfoSection
                    photosSection
                }
                .padding()
            }
            .navigationTitle(moment.playerName ?? "Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $fullScreenPhoto) { photo in
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .background(Color.black)
                .ignoresSafeArea()
        }
        .onChange(of: photoSelections) { _, items in
            guard !items.isEmpty else { return }
            addPhotos(items)
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        if let url = localMomentVideoURL(for: momentId) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var gameInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game Info")
                .font(.headline)

            if let suggestion = copySuggestion {
                Button {
                    applyCopySuggestion(suggestion.source)
                } label: {
                    Text("Copy from \(suggestion.source.playerName ?? "last Moment"), \(suggestion.minutesAgo) min ago")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            TextField("Opponent", text: $opponent)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitGameInfo() }

            HStack {
                TextField("Score (e.g. 4-2)", text: $score)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitGameInfo() }
                TextField("Inning", text: $inningText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 90)
                    .onSubmit { commitGameInfo() }
            }

            Button("Update") { commitGameInfo() }

            if let gameInfoUpdatedAt {
                Text("Last updated \(gameInfoUpdatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $photoSelections, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                }
            }

            if photoCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<photoCount, id: \.self) { index in
                            photoThumbnail(index: index)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photoThumbnail(index: Int) -> some View {
        if let url = localMomentPhotoURL(momentId: momentId, index: index),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            Button {
                fullScreenPhoto = FullScreenPhoto(id: index, image: image)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        authManager.updateMomentFields(momentId: momentId, fields: ["isFavorite": isFavorite]) { _ in }
    }

    private func applyCopySuggestion(_ source: Moment) {
        opponent = source.opponent ?? ""
        score = source.score ?? ""
        inningText = source.inning.map(String.init) ?? ""
        commitGameInfo()
    }

    private func commitGameInfo() {
        let now = Date()
        gameInfoUpdatedAt = now
        var fields: [String: Any] = ["gameInfoUpdatedAt": Timestamp(date: now)]
        fields["opponent"] = opponent.isEmpty ? NSNull() : opponent
        fields["score"] = score.isEmpty ? NSNull() : score
        fields["inning"] = Int(inningText) ?? NSNull()
        authManager.updateMomentFields(momentId: momentId, fields: fields) { _ in }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        var nextIndex = photoCount
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                saveLocalMomentPhoto(data, momentId: momentId, index: nextIndex)
                nextIndex += 1
            }
            await MainActor.run {
                photoCount = nextIndex
                photoSelections = []
                authManager.updateMomentFields(momentId: momentId, fields: ["photoCount": photoCount]) { _ in }
            }
        }
    }
}

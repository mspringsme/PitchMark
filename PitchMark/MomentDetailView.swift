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
    @State private var title: String
    @State private var opponent: String
    @State private var score: String
    @State private var inningText: String
    @State private var gameInfoUpdatedAt: Date?

    @State private var photoCount: Int
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var fullScreenPhoto: FullScreenPhoto? = nil
    /// Decoded once and cached, same reasoning as `player` below: every
    /// re-render of this view (e.g. a keystroke in Opponent/Score) used
    /// to call photoThumbnail(index:), which re-read the file and ran
    /// UIImage(data:) fresh each time - reported as a "pulsating"/
    /// flashing artifact on the thumbnails. Loaded once in onAppear and
    /// whenever photoCount changes, not decoded inline in the view body.
    @State private var photoImages: [Int: UIImage] = [:]

    @State private var showTrimEditor = false
    @State private var trimErrorMessage: String? = nil
    /// Created once and reused, never rebuilt inline in the view body -
    /// on-device testing showed the video "flash the first frame, only
    /// play about a second" when it was constructed inline
    /// (`VideoPlayer(player: AVPlayer(url: url))` directly in a computed
    /// property): SwiftUI re-evaluates that property on every body
    /// re-render (e.g. every keystroke in the Opponent/Score fields
    /// below), and each re-render built a brand-new AVPlayer pointed at
    /// the same URL, discarding playback position back to frame 0. Only
    /// reloaded explicitly, when the underlying file actually changes.
    @State private var player: AVPlayer? = nil

    init(moment: Moment, allMoments: [Moment]) {
        self.moment = moment
        self.allMoments = allMoments
        _isFavorite = State(initialValue: moment.isFavorite ?? false)
        _title = State(initialValue: moment.title ?? "")
        _opponent = State(initialValue: moment.opponent ?? "")
        _score = State(initialValue: moment.score ?? "")
        _inningText = State(initialValue: moment.inning.map(String.init) ?? "")
        _gameInfoUpdatedAt = State(initialValue: moment.gameInfoUpdatedAt)
        _photoCount = State(initialValue: moment.photoCount ?? 0)
    }

    private var momentId: String { moment.id ?? "" }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (moment.playerName ?? "Moment") : trimmed
    }

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
                    nameSection
                    playbackSection
                    trimSection
                    gameInfoSection
                    photosSection
                }
                .padding()
            }
            .navigationTitle(displayTitle)
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
        .fullScreenCover(isPresented: $showTrimEditor) {
            if let path = localMomentVideoURL(for: momentId)?.path {
                MomentTrimEditor(videoPath: path) { editedPath in
                    showTrimEditor = false
                    if let editedPath {
                        saveTrimResult(editedPath)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            reloadPlayer()
            loadPhotoImages()
        }
        // commitTitle() only fired from the TextField's onSubmit (return
        // key), so tapping Done - or swiping the sheet away - with an
        // edited title still in the field and the keyboard still up
        // dismissed without ever saving it. onDisappear fires for both
        // exit paths, not just Done, so it's the one place that reliably
        // flushes whatever's currently in the field.
        .onDisappear { commitTitle() }
    }

    @ViewBuilder
    private var playbackSection: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.headline)
            TextField(moment.playerName ?? "Moment", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitTitle() }
        }
    }

    @ViewBuilder
    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trim")
                .font(.headline)

            Button("Trim Video") {
                startTrimEditor()
            }

            if let trimErrorMessage {
                Text(trimErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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
        if let image = photoImages[index] {
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

    private func loadPhotoImages() {
        var images: [Int: UIImage] = [:]
        for index in 0..<max(photoCount, 0) {
            if let url = localMomentPhotoURL(momentId: momentId, index: index),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                images[index] = image
            }
        }
        photoImages = images
    }

    private func startTrimEditor() {
        trimErrorMessage = nil
        guard let path = localMomentVideoURL(for: momentId)?.path,
              UIVideoEditorController.canEditVideo(atPath: path) else {
            trimErrorMessage = "This video can't be trimmed on this device."
            return
        }
        showTrimEditor = true
    }

    /// Native trim already produces a finished, playable file - copied
    /// straight to the edited slot, no separate "Apply" step needed now
    /// that there's nothing left to composite on top of it.
    private func saveTrimResult(_ editedPath: String) {
        guard let destination = localMomentEditedVideoURL(for: momentId) else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: editedPath), to: destination)
            reloadPlayer()
        } catch {
            trimErrorMessage = "Couldn't save the trimmed video: \(error.localizedDescription)"
        }
    }

    private func reloadPlayer() {
        guard let url = resolvedMomentVideoURL(for: momentId) else {
            player = nil
            return
        }
        player = AVPlayer(url: url)
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        authManager.updateMomentFields(momentId: momentId, fields: ["isFavorite": isFavorite]) { _ in }
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        authManager.updateMomentFields(momentId: momentId, fields: ["title": trimmed.isEmpty ? NSNull() : trimmed]) { _ in }
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
                loadPhotoImages()
                authManager.updateMomentFields(momentId: momentId, fields: ["photoCount": photoCount]) { _ in }
            }
        }
    }
}

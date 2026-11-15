//
//  GameCaptionSheet.swift
//  PitchMark
//
//  The game caption's sheet and its bake (MomentGameCaption.swift has the
//  rules). Asked right after a clip or photo is captured while a game is
//  open, and from a Moment's Game Info button any time after.
//

import SwiftUI
import AVFoundation
import FirebaseFirestore

/// Bakes (or removes) a Moment's game caption through the same frozen
/// overlay base the Overlays editor uses, so the two never stack.
enum GameCaptionApplier {
    static func apply(
        momentId: String,
        context: MomentGameContext,
        options: GameCaptionOptions?,
        authManager: AuthManager,
        completion: @escaping (Error?) -> Void
    ) {
        guard let source = resolvedMomentVideoURL(for: momentId),
              FileManager.default.fileExists(atPath: source.path) else {
            completion(NSError(domain: "GameCaption", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "This Moment's video isn't on this phone."]))
            return
        }
        let base = overlayBaseVideoURL(momentId: momentId, sourceVideoURL: source)
        authManager.loadMoment(momentId: momentId) { fresh in
            let existing = fresh?.overlays ?? []
            Task {
                let duration = (try? await AVURLAsset(url: base).load(.duration).seconds) ?? 0
                await MainActor.run {
                    let caption = options.flatMap { GameCaption.overlay(context: context, options: $0, clipDuration: duration) }
                    let overlays = GameCaption.replacingCaption(in: existing, with: caption)
                    // Image overlays need their pictures to be baked again.
                    authManager.loadLibraryAssets { assets in
                        exportMomentWithOverlays(
                            sourceURL: base,
                            overlays: overlays,
                            resolveImage: { id in assets.first(where: { $0.id == id })?.image }
                        ) { result in
                            switch result {
                            case .failure(let error):
                                completion(error)
                            case .success(let tempURL):
                                guard let destination = localMomentEditedVideoURL(for: momentId) else {
                                    completion(NSError(domain: "GameCaption", code: -2,
                                                       userInfo: [NSLocalizedDescriptionKey: "Couldn't save the video."]))
                                    return
                                }
                                do {
                                    try? FileManager.default.removeItem(at: destination)
                                    try FileManager.default.copyItem(at: tempURL, to: destination)
                                    try? FileManager.default.removeItem(at: tempURL)
                                } catch {
                                    completion(error)
                                    return
                                }
                                invalidateOtherFrozenBases(momentId: momentId, except: [.overlay])
                                var fields: [String: Any] = [:]
                                if let options, let encoded = try? Firestore.Encoder().encode(options) {
                                    fields["gameCaption"] = encoded
                                } else {
                                    fields["gameCaption"] = FieldValue.delete()
                                }
                                if let encoded = try? Firestore.Encoder().encode(context) {
                                    fields["gameContext"] = encoded
                                }
                                authManager.updateMomentOverlays(momentId: momentId, overlays: overlays) { error in
                                    authManager.updateMomentFields(momentId: momentId, fields: fields) { _ in
                                        refreshFadeIfNeeded(momentId: momentId, authManager: authManager) {
                                            completion(error)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Which game items to show at the bottom of the video, for how long.
struct GameCaptionSheet: View {
    let context: MomentGameContext
    /// More than one when a capture made several Moments.
    var momentCount: Int = 1
    /// The Moment already has a caption: offer Remove.
    var canRemove: Bool = false
    let onApply: (GameCaptionOptions) -> Void
    let onRemove: () -> Void
    let onSkip: () -> Void

    @State private var options: GameCaptionOptions

    init(
        context: MomentGameContext,
        initialOptions: GameCaptionOptions?,
        momentCount: Int = 1,
        canRemove: Bool = false,
        onApply: @escaping (GameCaptionOptions) -> Void,
        onRemove: @escaping () -> Void = {},
        onSkip: @escaping () -> Void
    ) {
        self.context = context
        self.momentCount = momentCount
        self.canRemove = canRemove
        self.onApply = onApply
        self.onRemove = onRemove
        self.onSkip = onSkip
        _options = State(initialValue: initialOptions ?? GameCaptionOptions())
    }

    private var lines: (line1: String, line2: String)? {
        GameCaption.lines(context: context, options: options)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(momentCount > 1
                         ? "Shown along the bottom of all \(momentCount) new Moments. You can change it later from Game Info."
                         : "Shown along the bottom of the video. You can change or remove it later from Game Info.")
                }

                Section("Show") {
                    ForEach(GameCaption.items(for: context)) { item in
                        Toggle(isOn: Binding(
                            get: { GameCaption.isOn(item.id, in: options) && item.value != nil },
                            set: { GameCaption.set(item.id, $0, in: &options) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                Text(item.value ?? "Not recorded for this game")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(item.value == nil)
                        .accessibilityIdentifier("gameCaption.item.\(item.id)")
                    }
                }

                Section("Display") {
                    Picker("Show for", selection: $options.seconds) {
                        ForEach(GameCaptionOptions.durationChoices, id: \.self) { seconds in
                            Text(seconds == 0 ? "Whole clip" : "\(Int(seconds)) sec").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Fade out", isOn: $options.fadeOut)
                }

                if canRemove {
                    Section {
                        Button("Remove Game Text", role: .destructive, action: onRemove)
                    }
                }
            }
            .navigationTitle("Add Game Info?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(canRemove ? "Cancel" : "Skip", action: onSkip)
                        .accessibilityIdentifier("gameCaption.skip")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(canRemove ? "Update" : "Add") { onApply(options) }
                        .fontWeight(.semibold)
                        .disabled(lines == nil)
                        .accessibilityIdentifier("gameCaption.add")
                }
            }
        }
    }

    /// Roughly how it will look on the video.
    private var preview: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(white: 0.35), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 3) {
                if let lines {
                    Text(lines.line1)
                        .font(.system(size: 15, weight: .heavy))
                    Rectangle().fill(Color.white).frame(width: 140, height: 2)
                    if !lines.line2.isEmpty {
                        Text(lines.line2)
                            .font(.system(size: 12, weight: .medium))
                    }
                } else {
                    Text("Pick something to show")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: 150)
    }
}

/// The full-screen black spinner every Moments editor uses while it works.
struct GameCaptionWorkingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

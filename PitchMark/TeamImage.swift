//
//  TeamImage.swift
//  PitchMark
//
//  The circle in the middle of each team row on Home: the team's initials by
//  default (same look as a player without a portrait in the Players list),
//  or a photo the coach picked and cropped.
//
//  Stored on this device only, exactly like pitcher portraits
//  (Utilities.swift) - a PNG per team id under Application Support. The crop
//  step is Moments' own asset cropper (`AssetCropView`, AssetCreationFlow
//  .swift), so it behaves identically: circle/square/rounded shapes,
//  pan/zoom, Smart Cutout.
//
//  Not in the Pitchmark Display target - nothing there shows teams.
//

import SwiftUI
import PhotosUI

extension Notification.Name {
    static let teamImageDidChange = Notification.Name("teamImageDidChange")
}

// MARK: - Storage

private func localTeamImageURL(for teamId: String) -> URL? {
    guard !teamId.isEmpty,
          let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base
        .appendingPathComponent("PitchMark/TeamImages", isDirectory: true)
        .appendingPathComponent("\(teamId).png")
}

func localTeamImage(for teamId: String) -> UIImage? {
    guard let url = localTeamImageURL(for: teamId),
          let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}

@discardableResult
func saveLocalTeamImage(_ image: UIImage, teamId: String) -> Bool {
    guard let url = localTeamImageURL(for: teamId) else { return false }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.normalizedUpOrientation().pngData() else { return false }
        try data.write(to: url, options: [.atomic])
        NotificationCenter.default.post(name: .teamImageDidChange, object: teamId)
        return true
    } catch {
        debugLog("❌ saveLocalTeamImage failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalTeamImage(teamId: String) {
    guard let url = localTeamImageURL(for: teamId) else { return }
    try? FileManager.default.removeItem(at: url)
    NotificationCenter.default.post(name: .teamImageDidChange, object: teamId)
}

// MARK: - Avatar

/// Photo if one was set, otherwise initials on a gray circle - the same
/// fallback `PlayerDirectoryAvatar` uses for a player without a portrait.
struct TeamAvatarView: View {
    let team: Team
    var size: CGFloat = 40
    @State private var refreshToken = UUID()

    var body: some View {
        ZStack {
            Circle().fill(Color(.systemGray3))
            if let id = team.id, let image = localTeamImage(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        // Re-reads the file when this team's image is saved or removed.
        .id(refreshToken)
        .onReceive(NotificationCenter.default.publisher(for: .teamImageDidChange)) { notification in
            guard let changed = notification.object as? String, changed == team.id else { return }
            refreshToken = UUID()
        }
    }

    /// "14U Gold" → "1G", "Bombers" → "B".
    private var initials: String {
        let parts = team.name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

// MARK: - Edit flow

/// What the crop screen is cropping, and for which team.
struct TeamImageCropTarget: Identifiable {
    let teamId: String
    let image: UIImage
    var id: String { teamId }
}

/// Everything after a tap on the circle: "change it?" dialog → Photos →
/// Moments' cropper → saved. Attach once, at the root of the screen that
/// shows team rows (see CLAUDE.md on where dialogs attach), and drive it by
/// setting `team`.
struct TeamImageEditor: ViewModifier {
    @Binding var team: Team?

    @State private var showOptions = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var pickingForTeamId: String? = nil
    @State private var cropTarget: TeamImageCropTarget? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var hasImage: Bool {
        guard let id = team?.id else { return false }
        return localTeamImage(for: id) != nil
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: team?.id) { _, newValue in
                if newValue != nil { showOptions = true }
            }
            // Dismissed by tapping outside: clear the target too, or tapping
            // the same team's circle again wouldn't register as a change.
            .onChange(of: showOptions) { _, isShowing in
                if !isShowing { DispatchQueue.main.async { team = nil } }
            }
            .confirmationDialog(
                hasImage ? "Change the \(team?.name ?? "team") photo?" : "Add a photo for \(team?.name ?? "this team")?",
                isPresented: $showOptions,
                titleVisibility: .visible
            ) {
                Button(hasImage ? "Choose New Photo" : "Choose Photo") {
                    pickingForTeamId = team?.id
                    team = nil
                    // Let the dialog finish dismissing before Photos presents.
                    DispatchQueue.main.async { showPhotoPicker = true }
                }
                if hasImage {
                    Button("Remove Photo", role: .destructive) {
                        if let id = team?.id { removeLocalTeamImage(teamId: id) }
                        team = nil
                    }
                }
                Button("Cancel", role: .cancel) { team = nil }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                loadPicked(item)
            }
            .fullScreenCover(item: $cropTarget) { target in
                AssetCropView(
                    sourceImage: target.image,
                    onSave: { cropped in
                        if !saveLocalTeamImage(cropped, teamId: target.teamId) {
                            errorMessage = "Couldn't save that photo."
                        }
                        cropTarget = nil
                    },
                    onCancel: { cropTarget = nil }
                )
            }
            .onChange(of: errorMessage) { _, message in
                showError = message != nil
            }
            .appConfirmationDialog(
                isPresented: $showError,
                title: "Team Photo",
                message: errorMessage ?? "",
                primaryTitle: "OK",
                primaryAction: { errorMessage = nil },
                secondaryTitle: "Cancel",
                secondaryAction: { errorMessage = nil }
            )
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        let teamId = pickingForTeamId
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                photoSelection = nil
                pickingForTeamId = nil
                guard let teamId, let data, let image = UIImage(data: data) else {
                    errorMessage = "Couldn't load that photo."
                    return
                }
                cropTarget = TeamImageCropTarget(teamId: teamId, image: image)
            }
        }
    }
}

extension View {
    /// See `TeamImageEditor`.
    func teamImageEditor(team: Binding<Team?>) -> some View {
        modifier(TeamImageEditor(team: team))
    }
}

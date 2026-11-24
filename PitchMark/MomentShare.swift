//
//  MomentShare.swift
//  PitchMark
//
//  The system share sheet for a Moment (2026-11-02): its video as it
//  plays (fade and edits included - `resolvedMomentPlaybackURL`) plus its
//  photos. Files are copied under the Moment's title first, so a text or
//  AirDrop shows "Juju's Double.mov" rather than an internal id.
//

import Foundation

struct MomentShareRequest: Identifiable {
    let id = UUID()
    /// The clip and photo copies.
    let files: [URL]

    /// What the share sheet gets: just the file (2026-11-24, user's call).
    /// The "Get PitchMark" line and link are off until it comes back a
    /// different way (`MomentShare.getPitchMarkLine` is kept for that).
    var items: [Any] { files }
}

enum MomentShare {
    static let appStoreURL = "https://apps.apple.com/app/id6791446420"
    static let getPitchMarkLine = "Get PitchMark: \(appStoreURL)"

    /// A file name from a Moment's title: path separators and other
    /// characters a file name can't hold become spaces; empty falls back
    /// to "Moment".
    static func fileStem(for title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines).union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { banned.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? "Moment" : String(collapsed.prefix(80))
    }

    /// What to share: ONE file (2026-11-24, user's call - a clip and its
    /// still arrived as two copies of the same moment). A video Moment
    /// sends its video; a photo Moment (its "video" is the photo held
    /// still) sends its photo. With no video on this phone, the first
    /// photo. `exists` is injectable so the choice can be tested.
    static func sourceFiles(
        momentId: String,
        photoCount: Int,
        isPhotoMoment: Bool = false,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [URL] {
        let video = resolvedMomentPlaybackURL(for: momentId).flatMap { exists($0) ? $0 : nil }
        let firstPhoto = (0..<max(0, photoCount)).lazy
            .compactMap { localMomentPhotoURL(momentId: momentId, index: $0) }
            .first(where: exists)
        let pick = isPhotoMoment ? (firstPhoto ?? video) : (video ?? firstPhoto)
        return pick.map { [$0] } ?? []
    }

    /// Copies the files into a fresh temporary folder under the Moment's
    /// title ("Title.mov", "Title 1.jpg", ...). Nil when there's nothing
    /// on this device to share.
    static func prepare(_ moment: Moment) -> MomentShareRequest? {
        guard let id = moment.id else { return nil }
        let sources = sourceFiles(momentId: id, photoCount: moment.photoCount ?? 0,
                                  isPhotoMoment: moment.momentKind == .photoCreation)
        guard !sources.isEmpty else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentShare", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = fileStem(for: moment.displayTitle)
        var photoNumber = 0
        let copies: [URL] = sources.compactMap { source in
            let ext = source.pathExtension
            let name: String
            if ext.lowercased() == "jpg" {
                photoNumber += 1
                name = "\(stem) \(photoNumber).\(ext)"
            } else {
                name = "\(stem).\(ext)"
            }
            let target = folder.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: source, to: target)
                return target
            } catch {
                debugLog("⚠️ MomentShare copy failed:", error.localizedDescription)
                return source
            }
        }
        return MomentShareRequest(files: copies)
    }
}

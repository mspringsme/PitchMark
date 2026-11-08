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
    let items: [URL]
}

enum MomentShare {
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

    /// What to share, in order: the video, then each photo that exists.
    /// `exists` is injectable so the choice can be tested without files.
    static func sourceFiles(
        momentId: String,
        photoCount: Int,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [URL] {
        var files: [URL] = []
        if let video = resolvedMomentPlaybackURL(for: momentId), exists(video) {
            files.append(video)
        }
        for index in 0..<max(0, photoCount) {
            if let photo = localMomentPhotoURL(momentId: momentId, index: index), exists(photo) {
                files.append(photo)
            }
        }
        return files
    }

    /// Copies the files into a fresh temporary folder under the Moment's
    /// title ("Title.mov", "Title 1.jpg", ...). Nil when there's nothing
    /// on this device to share.
    static func prepare(_ moment: Moment) -> MomentShareRequest? {
        guard let id = moment.id else { return nil }
        let sources = sourceFiles(momentId: id, photoCount: moment.photoCount ?? 0)
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
        return MomentShareRequest(items: copies)
    }
}

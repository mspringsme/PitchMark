//
//  ClipShare.swift
//  PitchMark
//
//  Interim clip sharing (2026-11-24, clip brief section 2c): a parent who
//  is scoring records a clip from the game screen and sends it to a few
//  people (say two grandparents) without leaving the game. Clips go
//  through iOS Messages - the user always taps Send; an app can't send
//  silently and gets no delivery receipt.
//
//  Forward-compatible with the cloud clip feed: each queued clip names its
//  game, inning, half, batter and pitch, and the people it's for. Messages
//  is just this phase's delivery channel; the Quick Send list becomes the
//  approved-recipient list later.
//
//  Plain rules here; the screens are ClipShareViews.swift.
//  - Quick Send list: `users/{uid}/meta/quickSend` (meta rule, no rules
//    change), cached on the phone so it works with no signal.
//  - The send queue: on this phone only, like the clips themselves.
//

import Foundation
import Combine
import AVFoundation
import FirebaseFirestore

/// Someone the parent sends clips to. Typed in by hand (no Contacts
/// prompt): a phone number or an email address Messages can reach.
struct QuickSendRecipient: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var address: String

    var isEmail: Bool { address.contains("@") }
}

enum QuickSendRules {
    static let nameMax = 40
    static let maxRecipients = 12

    /// A cleaned recipient, or nil when the name is empty or the address
    /// isn't a phone number (7+ digits) or an email address.
    static func recipient(name: String, address: String, id: String = UUID().uuidString) -> QuickSendRecipient? {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameMax))
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, isValidAddress(cleanAddress) else { return nil }
        return QuickSendRecipient(id: id, name: cleanName, address: cleanAddress)
    }

    static func isValidAddress(_ address: String) -> Bool {
        if address.contains("@") {
            let parts = address.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
                && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".") && !address.contains(" ")
        }
        let allowed = CharacterSet(charactersIn: "0123456789+-(). ")
        guard address.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return address.filter(\.isNumber).count >= 7
    }

    /// The same person typed twice: same email ignoring case, or same
    /// phone digits.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        if a.contains("@") || b.contains("@") { return a.lowercased() == b.lowercased() }
        let da = a.filter(\.isNumber), db = b.filter(\.isNumber)
        // A leading US country code doesn't make a different person.
        func trimmed(_ d: String) -> String { d.count == 11 && d.hasPrefix("1") ? String(d.dropFirst()) : d }
        return trimmed(da) == trimmed(db)
    }

    /// Adds or replaces (same id) a recipient. Refuses a second entry for
    /// an address already on the list, and a list past the limit.
    static func upserting(_ r: QuickSendRecipient, into list: [QuickSendRecipient]) -> [QuickSendRecipient]? {
        if list.contains(where: { $0.id != r.id && sameAddress($0.address, r.address) }) { return nil }
        if let i = list.firstIndex(where: { $0.id == r.id }) {
            var copy = list
            copy[i] = r
            return copy
        }
        guard list.count < maxRecipients else { return nil }
        return list + [r]
    }
}

/// Which half of which inning - the break that offers the send.
struct HalfInningKey: Codable, Equatable, Hashable {
    var inning: Int
    /// "home"/"away": the side pitching.
    var pitchingSide: String
}

/// A clip waiting to go (or gone) to the people picked when it was recorded.
struct QueuedClip: Codable, Identifiable, Equatable {
    /// The Moment's id - the clip itself lives in Moments.
    var id: String
    var gameId: String
    var half: HalfInningKey
    var batterName: String?
    /// The latest pitch when the clip was recorded - the play it belongs to.
    var pitchEventId: String?
    var recipientIds: [String]
    var queuedAt: Date
    var sentAt: [String: Date] = [:]

    func isPending(for recipientId: String) -> Bool {
        recipientIds.contains(recipientId) && sentAt[recipientId] == nil
    }

    var isFullySent: Bool { recipientIds.allSatisfy { sentAt[$0] != nil } }

    /// "Inning 3 · #12 Juju" - what the tray and the message say.
    var label: String {
        let batter = batterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return batter.isEmpty ? "Inning \(half.inning)" : "Inning \(half.inning) · \(batter)"
    }
}

/// One Messages sheet: a person and every clip waiting for them.
struct PendingClipMessage: Identifiable, Equatable {
    var recipient: QuickSendRecipient
    var clipIds: [String]
    var id: String { recipient.id }
}

enum ClipSendQueue {
    /// One message per person with clips waiting, in Quick Send order;
    /// clips oldest first. `onlyClipId` = Send Now for one clip. People
    /// removed from the list since are skipped.
    static func pendingMessages(clips: [QueuedClip], recipients: [QuickSendRecipient],
                                onlyClipId: String? = nil) -> [PendingClipMessage] {
        let ordered = clips.sorted { $0.queuedAt < $1.queuedAt }
            .filter { onlyClipId == nil || $0.id == onlyClipId }
        return recipients.compactMap { r in
            let ids = ordered.filter { $0.isPending(for: r.id) }.map(\.id)
            return ids.isEmpty ? nil : PendingClipMessage(recipient: r, clipIds: ids)
        }
    }

    static func markSent(_ clips: [QueuedClip], clipIds: [String], recipientId: String, at date: Date) -> [QueuedClip] {
        clips.map { clip in
            guard clipIds.contains(clip.id), clip.recipientIds.contains(recipientId) else { return clip }
            var copy = clip
            copy.sentAt[recipientId] = date
            return copy
        }
    }

    static func pendingCount(_ clips: [QueuedClip], recipients: [QuickSendRecipient]) -> Int {
        let ids = Set(recipients.map(\.id))
        return clips.filter { clip in clip.recipientIds.contains { ids.contains($0) && clip.sentAt[$0] == nil } }.count
    }

    /// The between-innings banner shows when the half-inning changes and
    /// something is waiting. Not on the first look at a game (no previous
    /// half) - opening a game isn't a break.
    static func shouldOfferSend(previous: HalfInningKey?, current: HalfInningKey, pendingCount: Int) -> Bool {
        guard let previous, previous != current else { return false }
        return pendingCount > 0
    }

    /// Clips kept on the queue: this game's, plus any not yet fully sent
    /// from the last 3 days. Everything else drops off.
    static func pruned(_ clips: [QueuedClip], currentGameId: String?, now: Date) -> [QueuedClip] {
        clips.filter { clip in
            clip.gameId == currentGameId
                || (!clip.isFullySent && now.timeIntervalSince(clip.queuedAt) < 3 * 86_400)
        }
    }

    /// The message's words: "Juju's game: Inning 3 · #12, Inning 5".
    static func messageBody(gameName: String?, clips: [QueuedClip]) -> String {
        let name = gameName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let labels = clips.map(\.label).joined(separator: ", ")
        if name.isEmpty { return labels }
        return labels.isEmpty ? name : "\(name): \(labels)"
    }
}

/// The Quick Send list, who's picked, and the send queue. One per app.
@MainActor
final class ClipShareStore: ObservableObject {
    static let shared: ClipShareStore = {
        // UI tests start from an empty list every launch.
        if ProcessInfo.processInfo.arguments.contains("-UITestDemo"),
           let fresh = UserDefaults(suiteName: "uitest.clipShare") {
            fresh.removePersistentDomain(forName: "uitest.clipShare")
            return ClipShareStore(defaults: fresh)
        }
        return ClipShareStore()
    }()

    @Published private(set) var recipients: [QuickSendRecipient] = []
    /// Who new clips go to. Empty = Just me (the clip stays in Moments).
    @Published private(set) var selectedIds: Set<String> = []
    @Published private(set) var queue: [QueuedClip] = []

    private let defaults: UserDefaults
    private var uid: String?
    private static let listKey = "clipShare.quickSend"
    private static let queueKey = "clipShare.queue"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadLocal()
    }

    private struct StoredList: Codable {
        var recipients: [QuickSendRecipient]
        var selectedIds: [String]
    }

    private func loadLocal() {
        if let data = defaults.data(forKey: Self.listKey),
           let stored = try? JSONDecoder().decode(StoredList.self, from: data) {
            recipients = stored.recipients
            selectedIds = Set(stored.selectedIds).intersection(stored.recipients.map(\.id))
        }
        if let data = defaults.data(forKey: Self.queueKey),
           let stored = try? JSONDecoder().decode([QueuedClip].self, from: data) {
            queue = stored
        }
    }

    /// Reads the account's list once signed in. The account copy wins when
    /// it exists; otherwise the phone's list is saved up to it.
    func signedIn(uid: String?) {
        guard let uid, uid != self.uid else { return }
        self.uid = uid
        Firestore.firestore().collection("users").document(uid).collection("meta").document("quickSend")
            .getDocument { [weak self] snapshot, _ in
                let data = snapshot?.data()
                Task { @MainActor in
                    guard let self else { return }
                    if let raw = data?["recipients"] as? [[String: Any]] {
                        let list = raw.compactMap { item -> QuickSendRecipient? in
                            guard let id = item["id"] as? String, let name = item["name"] as? String,
                                  let address = item["address"] as? String else { return nil }
                            return QuickSendRecipient(id: id, name: name, address: address)
                        }
                        let picked = Set(data?["selectedIds"] as? [String] ?? [])
                        self.recipients = list
                        self.selectedIds = picked.intersection(list.map(\.id))
                        self.saveLocal()
                    } else if !self.recipients.isEmpty {
                        self.saveRemote()
                    }
                }
            }
    }

    func signedOut() { uid = nil }

    // MARK: Quick Send list

    /// False when the address is already on the list or the list is full.
    @discardableResult
    func save(_ recipient: QuickSendRecipient) -> Bool {
        guard let list = QuickSendRules.upserting(recipient, into: recipients) else { return false }
        let isNew = !recipients.contains { $0.id == recipient.id }
        recipients = list
        if isNew { selectedIds.insert(recipient.id) }
        persistList()
        return true
    }

    func remove(_ id: String) {
        recipients.removeAll { $0.id == id }
        selectedIds.remove(id)
        persistList()
    }

    func toggle(_ id: String) {
        guard recipients.contains(where: { $0.id == id }) else { return }
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
        persistList()
    }

    private func persistList() {
        saveLocal()
        saveRemote()
    }

    private func saveLocal() {
        let stored = StoredList(recipients: recipients, selectedIds: Array(selectedIds))
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.listKey) }
    }

    private func saveRemote() {
        guard let uid else { return }
        let data: [String: Any] = [
            "recipients": recipients.map { ["id": $0.id, "name": $0.name, "address": $0.address] },
            "selectedIds": Array(selectedIds),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        Firestore.firestore().collection("users").document(uid).collection("meta").document("quickSend")
            .setData(data) { error in
                if let error { debugLog("⚠️ quickSend save failed:", error.localizedDescription) }
            }
    }

    // MARK: Queue

    /// A new clip, for whoever is picked right now. Nobody picked = Just
    /// me: nothing is queued.
    func enqueue(momentId: String, gameId: String, half: HalfInningKey, batterName: String?,
                 pitchEventId: String?, now: Date = Date()) {
        let picked = recipients.map(\.id).filter { selectedIds.contains($0) }
        guard !picked.isEmpty, !queue.contains(where: { $0.id == momentId }) else { return }
        queue.append(QueuedClip(id: momentId, gameId: gameId, half: half, batterName: batterName,
                                pitchEventId: pitchEventId, recipientIds: picked, queuedAt: now))
        saveQueue()
    }

    func markSent(clipIds: [String], to recipientId: String, at date: Date = Date()) {
        queue = ClipSendQueue.markSent(queue, clipIds: clipIds, recipientId: recipientId, at: date)
        saveQueue()
    }

    /// Takes a clip off the tray without sending it (the clip stays in Moments).
    func removeFromQueue(_ clipId: String) {
        queue.removeAll { $0.id == clipId }
        saveQueue()
    }

    func prune(currentGameId: String?, now: Date = Date()) {
        let kept = ClipSendQueue.pruned(queue, currentGameId: currentGameId, now: now)
        guard kept != queue else { return }
        queue = kept
        saveQueue()
    }

    func clips(forGame gameId: String?) -> [QueuedClip] {
        queue.filter { $0.gameId == gameId }.sorted { $0.queuedAt > $1.queuedAt }
    }

    var pendingCount: Int { ClipSendQueue.pendingCount(queue, recipients: recipients) }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) { defaults.set(data, forKey: Self.queueKey) }
    }
}

/// Makes the files a message carries: each clip as it plays, made 720p
/// for sending (a 30 s clip is about 9 MB), named after the clip.
enum ClipShareExporter {
    static func files(for momentIds: [String], titles: [String: String]) async -> [URL] {
        var urls: [URL] = []
        for id in momentIds {
            if let url = await file(for: id, title: titles[id] ?? "Clip") { urls.append(url) }
        }
        return urls
    }

    static func file(for momentId: String, title: String) async -> URL? {
        guard let source = resolvedMomentPlaybackURL(for: momentId),
              FileManager.default.fileExists(atPath: source.path) else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShare", isDirectory: true)
            .appendingPathComponent(momentId, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(MomentShare.fileStem(for: title)).appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: target.path) { return target }

        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            return source
        }
        do {
            try await export.export(to: target, as: .mp4)
            return target
        } catch {
            debugLog("⚠️ clip export failed, sending the original:", error.localizedDescription)
            return source
        }
    }
}

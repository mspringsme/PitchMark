//
//  ClipShareViews.swift
//  PitchMark
//
//  The game screen's clip bar (2026-11-24, clip brief 2c): Clip records
//  (60 s cap, Discard & Restart), the chips pick who new clips go to with
//  one tap, and the tray holds what's waiting. When the half-inning turns
//  over with clips waiting, a banner offers to send them: one Messages
//  sheet per person, every waiting clip attached, so it's one tap each.
//
//  A modifier struct, so the tracker's own type doesn't grow (see the
//  PitchTrackerView stack-size notes in CLAUDE.md). Rules: ClipShare.swift.
//

import SwiftUI
import MessageUI
import FirebaseAuth

/// What the tracker hands the clip bar.
struct GameClipContext {
    var isActive: Bool
    var gameId: String?
    var gameName: String?
    var half: HalfInningKey
    var batterName: String?
}

struct GameClipBarModifier: ViewModifier {
    let clip: GameClipContext
    /// The game as it stands when recording stops (score, inning, batter).
    let snapshot: () -> MomentGameContext?
    /// The latest pitch's id when recording stops.
    let latestPitchEventId: () -> String?

    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var store = ClipShareStore.shared
    @ObservedObject private var flags = AppFeatureFlagStore.shared

    @State private var showCamera = false
    @State private var showRecipients = false
    @State private var sendRequest: ClipSendRequest?
    @State private var showBanner = false
    @State private var lastHalf: HalfInningKey?
    @State private var saveError: String?

    private var isShown: Bool {
        clip.isActive && clip.gameId != nil && flags.flags.isOn(.interimClipSharing)
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isShown {
                    VStack(spacing: 6) {
                        if showBanner { banner }
                        GameClipBar(
                            store: store,
                            pendingCount: ClipSendQueue.pendingCount(store.clips(forGame: clip.gameId), recipients: store.recipients),
                            onClip: { showCamera = true },
                            onEditRecipients: { showRecipients = true },
                            onTray: { sendRequest = ClipSendRequest(onlyClipId: nil) }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .onAppear {
                store.signedIn(uid: authManager.user?.uid)
                store.prune(currentGameId: clip.gameId)
                lastHalf = clip.half
            }
            .onChange(of: clip.gameId) { _, gameId in
                store.prune(currentGameId: gameId)
                lastHalf = nil
                showBanner = false
            }
            .onChange(of: clip.half) { _, half in
                let pending = ClipSendQueue.pendingCount(store.clips(forGame: clip.gameId), recipients: store.recipients)
                if ClipSendQueue.shouldOfferSend(previous: lastHalf, current: half, pendingCount: pending) {
                    withAnimation { showBanner = true }
                }
                lastHalf = half
            }
            .appSheet(isPresented: $showCamera, chrome: .none) {
                MomentCameraPicker(gameClipMode: true) { url, duration, _ in
                    showCamera = false
                    guard let url else { return }
                    saveClip(url: url, duration: duration)
                }
                .ignoresSafeArea()
            }
            .appSheet(isPresented: $showRecipients, chrome: .handle) {
                QuickSendListSheet(store: store)
            }
            .appSheet(item: $sendRequest) { request in
                ClipSendSheet(store: store, gameId: clip.gameId, gameName: clip.gameName,
                              onlyClipId: request.onlyClipId)
            }
            .appConfirmationDialog(
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } }),
                title: "Clip Not Saved",
                message: saveError ?? "",
                primaryTitle: "OK",
                primaryAction: {},
                secondaryTitle: "Cancel"
            )
    }

    private var banner: some View {
        let count = ClipSendQueue.pendingCount(store.clips(forGame: clip.gameId), recipients: store.recipients)
        return HStack(spacing: 10) {
            Image(systemName: "paperplane.fill")
            Text("\(count) clip\(count == 1 ? "" : "s") ready to send")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Button("Send") {
                showBanner = false
                sendRequest = ClipSendRequest(onlyClipId: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pitchMarkActiveGray)
            .accessibilityIdentifier("clipBar.banner.send")
            Button {
                withAnimation { showBanner = false }
            } label: {
                Image(systemName: "xmark").frame(width: 32, height: 32)
            }
            .accessibilityLabel("Not now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .accessibilityIdentifier("clipBar.banner")
    }

    /// Saves the take as a Moment with the game on it, then queues it for
    /// whoever is picked.
    private func saveClip(url: URL, duration: Double?) {
        guard let gameId = clip.gameId else { return }
        let context = snapshot()
        let pitchId = latestPitchEventId()
        let half = clip.half
        let batter = context?.batterName ?? clip.batterName
        var moment = Moment(createdAt: Date(), durationSeconds: duration, photoCount: 0)
        moment.gameContext = context
        authManager.saveMoment(moment) { result in
            switch result {
            case .success(let saved):
                guard let id = saved.id else { return }
                _ = saveLocalMomentVideo(from: url, momentId: id, autoBackupToPhotos: true)
                Task { @MainActor in
                    store.enqueue(momentId: id, gameId: gameId, half: half, batterName: batter,
                                  pitchEventId: pitchId)
                    PlayerMomentsIndex.shared.refresh(authManager, force: true)
                }
            case .failure(let error):
                Task { @MainActor in
                    saveError = "Sign in to keep clips in Moments. (\(error.localizedDescription))"
                }
            }
        }
    }
}

struct ClipSendRequest: Identifiable {
    let id = UUID()
    var onlyClipId: String?
}

/// Clip button, who-gets-it chips, and the tray.
struct GameClipBar: View {
    @ObservedObject var store: ClipShareStore
    let pendingCount: Int
    let onClip: () -> Void
    let onEditRecipients: () -> Void
    let onTray: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClip) {
                Label("Clip", systemImage: "video.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.red))
            }
            .accessibilityIdentifier("clipBar.clip")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if store.recipients.isEmpty {
                        Button(action: onEditRecipients) {
                            Label("Who gets clips?", systemImage: "person.badge.plus")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
                                .foregroundStyle(Color.primary)
                        }
                        .accessibilityIdentifier("clipBar.addRecipients")
                    } else {
                        ForEach(store.recipients) { person in
                            let isOn = store.selectedIds.contains(person.id)
                            Button { store.toggle(person.id) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    Text(person.name).lineLimit(1)
                                }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .foregroundStyle(isOn ? Color.white : Color.primary)
                                .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
                            }
                            .accessibilityIdentifier("clipBar.chip.\(person.name)")
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                        Button(action: onEditRecipients) {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.primary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .accessibilityLabel("Edit Quick Send list")
                        .accessibilityIdentifier("clipBar.editRecipients")
                    }
                }
            }

            Button(action: onTray) {
                Image(systemName: pendingCount > 0 ? "tray.full.fill" : "tray")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 36)
                    .overlay(alignment: .topTrailing) {
                        if pendingCount > 0 {
                            Text("\(pendingCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .accessibilityLabel(pendingCount > 0 ? "\(pendingCount) clips waiting to send" : "Clip tray")
            .accessibilityIdentifier("clipBar.tray")
        }
    }
}

/// Everything waiting, one Send per person; this game's clips below with
/// Send Now each.
struct ClipSendSheet: View {
    @ObservedObject var store: ClipShareStore
    let gameId: String?
    let gameName: String?
    let onlyClipId: String?

    @State private var composing: ComposeRequest?
    @State private var isPreparing = false
    @State private var scopedClipId: String?
    @State private var missingCount = 0

    struct ComposeRequest: Identifiable {
        let id = UUID()
        var message: PendingClipMessage
        var files: [URL]
        var body: String
    }

    private var gameClips: [QueuedClip] { store.clips(forGame: gameId) }

    private var messages: [PendingClipMessage] {
        ClipSendQueue.pendingMessages(clips: gameClips, recipients: store.recipients,
                                      onlyClipId: scopedClipId ?? onlyClipId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if messages.isEmpty {
                        Text(gameClips.isEmpty ? "No clips yet this game. Tap Clip to record one."
                                               : "Everything has been sent.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(messages) { message in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.recipient.name).font(.body.weight(.semibold))
                                Text("\(message.clipIds.count) clip\(message.clipIds.count == 1 ? "" : "s")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Send") { compose(message) }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.pitchMarkActiveGray)
                                .accessibilityIdentifier("clipSend.send.\(message.recipient.name)")
                        }
                    }
                } header: {
                    Text(scopedClipId == nil ? "Send" : "Send This Clip")
                } footer: {
                    Text("Messages opens with the clips attached. Tap Send there - iOS doesn't let apps send for you.")
                }

                if !gameClips.isEmpty {
                    Section("This Game's Clips") {
                        ForEach(gameClips) { clip in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(clip.label).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if !clip.isFullySent {
                                        Button("Send Now") { scopedClipId = clip.id }
                                            .font(.footnote.weight(.semibold))
                                            .buttonStyle(.bordered)
                                    }
                                }
                                Text(status(of: clip)).font(.footnote).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { store.removeFromQueue(clip.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if scopedClipId != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("All Clips") { scopedClipId = nil }
                    }
                }
            }
        }
        .overlay {
            if isPreparing {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Getting clips ready…").foregroundStyle(.white).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .appSheet(item: $composing, chrome: .none) { request in
            ClipMessageComposer(recipient: request.message.recipient, files: request.files, body: request.body) { sent in
                if sent { store.markSent(clipIds: request.message.clipIds, to: request.message.recipient.id) }
                composing = nil
            }
            .ignoresSafeArea()
        }
        .appConfirmationDialog(
            isPresented: Binding(get: { missingCount > 0 }, set: { if !$0 { missingCount = 0 } }),
            title: "Clip Not on This Phone",
            message: "\(missingCount) clip\(missingCount == 1 ? " isn't" : "s aren't") on this phone any more, so \(missingCount == 1 ? "it" : "they") can't be sent.",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Cancel"
        )
    }

    private func status(of clip: QueuedClip) -> String {
        let names = store.recipients.reduce(into: [String: String]()) { $0[$1.id] = $1.name }
        let sent = clip.recipientIds.filter { clip.sentAt[$0] != nil }.compactMap { names[$0] }
        let waiting = clip.recipientIds.filter { clip.sentAt[$0] == nil }.compactMap { names[$0] }
        var parts: [String] = []
        if !sent.isEmpty { parts.append("Sent to \(sent.joined(separator: ", "))") }
        if !waiting.isEmpty { parts.append("waiting for \(waiting.joined(separator: ", "))") }
        let line = parts.joined(separator: ", ")
        return line.isEmpty ? "Just me" : line.prefix(1).uppercased() + line.dropFirst()
    }

    private func compose(_ message: PendingClipMessage) {
        isPreparing = true
        let clips = gameClips.filter { message.clipIds.contains($0.id) }
        let titles = clips.reduce(into: [String: String]()) { $0[$1.id] = "\(gameName ?? "Clip") \($1.label)" }
        Task {
            let files = await ClipShareExporter.files(for: message.clipIds, titles: titles)
            await MainActor.run {
                isPreparing = false
                let missing = message.clipIds.count - files.count
                if missing > 0 { missingCount = missing }
                guard !files.isEmpty else { return }
                composing = ComposeRequest(message: message, files: files,
                                           body: ClipSendQueue.messageBody(gameName: gameName, clips: clips))
            }
        }
    }
}

/// Messages with the person filled in and the clips attached. Falls back
/// to the share sheet where Messages can't send (no SIM, simulator).
struct ClipMessageComposer: UIViewControllerRepresentable {
    let recipient: QuickSendRecipient
    let files: [URL]
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIViewController {
        if MFMessageComposeViewController.canSendText(), MFMessageComposeViewController.canSendAttachments() {
            let composer = MFMessageComposeViewController()
            composer.messageComposeDelegate = context.coordinator
            composer.recipients = [recipient.address]
            composer.body = body
            for file in files {
                composer.addAttachmentURL(file, withAlternateFilename: file.lastPathComponent)
            }
            return composer
        }
        let share = UIActivityViewController(activityItems: files, applicationActivities: nil)
        share.completionWithItemsHandler = { _, completed, _, _ in
            context.coordinator.onFinish(completed)
        }
        return share
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}

/// Add, edit and remove the people clips go to.
struct QuickSendListSheet: View {
    @ObservedObject var store: ClipShareStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingId: String?
    @State private var name = ""
    @State private var address = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.recipients.isEmpty {
                        Text("Nobody yet. Add the people you send clips to - a grandparent, say.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.recipients) { person in
                        Button {
                            editingId = person.id
                            name = person.name
                            address = person.address
                            error = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).foregroundStyle(.primary)
                                Text(person.address).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { store.remove(person.id) }
                        }
                    }
                } header: {
                    Text("Quick Send")
                } footer: {
                    Text("Tap a name on the game screen to pick who new clips go to. Nobody picked keeps a clip in Moments, just for you.")
                }

                Section(editingId == nil ? "Add Someone" : "Edit") {
                    TextField("Name (Grandma)", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("quickSend.name")
                    TextField("Phone number or email", text: $address)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quickSend.address")
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button(editingId == nil ? "Add" : "Save") { saveEntry() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || address.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("quickSend.save")
                    if editingId != nil {
                        Button("Cancel Edit") { clearEntry() }
                    }
                }
            }
            .navigationTitle("Who Gets Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func saveEntry() {
        guard let person = QuickSendRules.recipient(name: name, address: address, id: editingId ?? UUID().uuidString) else {
            error = "Enter a name and a phone number or email address."
            return
        }
        guard store.save(person) else {
            error = store.recipients.count >= QuickSendRules.maxRecipients && editingId == nil
                ? "The list holds \(QuickSendRules.maxRecipients) people."
                : "That number or email is already on the list."
            return
        }
        clearEntry()
    }

    private func clearEntry() {
        editingId = nil
        name = ""
        address = ""
        error = nil
    }
}

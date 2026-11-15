//
//  MomentCompareView.swift
//  PitchMark
//
//  Compare two Moments side by side (2026-11-15) - this week's swing next
//  to last month's, two pitchers' release. The coach picks two clips,
//  lines each one up on its own (scrub, step a frame, Set Sync Here -
//  say, the frame the front foot lands), frames each one (pinch to zoom,
//  drag to move), then plays them together locked at those points,
//  slowed down or a frame at a time - and can save it as a new Moment
//  (MomentCompareExporter.swift), from a chosen start to end.
//

import SwiftUI
import AVFoundation
import Combine

/// The two clips' clocks relative to their sync points, apart from the
/// view so it can be tested. Joint time 0 is both sync points.
struct CompareTimeline: Equatable {
    var durationA: Double
    var durationB: Double
    var syncA: Double = 0
    var syncB: Double = 0
    /// Whether the coach has set each clip's sync point (Set Sync Here is
    /// a toggle). Unset means the clip's start.
    var isSyncSetA = false
    var isSyncSetB = false
    /// The coach's Start / End, in joint time; nil = as far as both go.
    var trimStart: Double? = nil
    var trimEnd: Double? = nil

    /// How far both clips can play together, before and after the sync
    /// points - until the first one runs out either way.
    var jointRange: ClosedRange<Double> {
        let lower = -min(syncA, syncB)
        let upper = min(durationA - syncA, durationB - syncB)
        return lower...max(lower, upper)
    }

    /// What plays and what's saved: the joint range cut to Start / End.
    var playRange: ClosedRange<Double> {
        let joint = jointRange
        let lower = min(max(trimStart ?? joint.lowerBound, joint.lowerBound), joint.upperBound)
        let upper = min(max(trimEnd ?? joint.upperBound, lower), joint.upperBound)
        return lower...upper
    }

    /// Each clip's own time at joint time `t`.
    func times(at t: Double) -> (a: Double, b: Double) {
        let t = min(max(t, jointRange.lowerBound), jointRange.upperBound)
        return (min(max(syncA + t, 0), durationA), min(max(syncB + t, 0), durationB))
    }

    func jointTime(fromA a: Double) -> Double { a - syncA }

    /// Moving a sync point moves what joint time means, so Start / End
    /// are cleared.
    mutating func setSync(a: Double? = nil, b: Double? = nil) {
        if let a { syncA = min(max(a, 0), durationA); isSyncSetA = true }
        if let b { syncB = min(max(b, 0), durationB); isSyncSetB = true }
        trimStart = nil
        trimEnd = nil
    }

    /// Back to the clip's start, not set.
    mutating func clearSync(a: Bool = false, b: Bool = false) {
        if a { syncA = 0; isSyncSetA = false }
        if b { syncB = 0; isSyncSetB = false }
        trimStart = nil
        trimEnd = nil
    }

    mutating func setStart(_ t: Double) {
        trimStart = t
        if let end = trimEnd, end <= t { trimEnd = nil }
    }

    mutating func setEnd(_ t: Double) {
        trimEnd = t
        if let start = trimStart, start >= t { trimStart = nil }
    }
}

final class MomentCompareController: ObservableObject {
    let playerA: AVPlayer
    let playerB: AVPlayer
    @Published var timeline = CompareTimeline(durationA: 0, durationB: 0)
    @Published var timeA: Double = 0
    @Published var timeB: Double = 0
    @Published var jointTime: Double = 0
    @Published var isPlaying = false
    @Published var rate: Float = 0.5
    @Published var loop = true
    @Published var framingA = ComparePaneFraming()
    @Published var framingB = ComparePaneFraming()
    @Published var soundOn = false {
        didSet { playerA.isMuted = !soundOn }
    }

    private var observer: Any?

    init(urlA: URL, urlB: URL) {
        playerA = AVPlayer(url: urlA)
        playerB = AVPlayer(url: urlB)
        for player in [playerA, playerB] {
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
        }
        playerA.isMuted = true
        playerB.isMuted = true
        Task { @MainActor in
            let a = (try? await playerA.currentItem?.asset.load(.duration).seconds) ?? 0
            let b = (try? await playerB.currentItem?.asset.load(.duration).seconds) ?? 0
            timeline = CompareTimeline(durationA: a.isFinite ? a : 0, durationB: b.isFinite ? b : 0)
        }
        observer = playerA.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            self?.tick(time.seconds)
        }
    }

    deinit {
        if let observer { playerA.removeTimeObserver(observer) }
    }

    /// True from the End point until playback restarts at Start. The
    /// time observer keeps firing during that jump; without this guard
    /// each tick started another jump and another play, and the loop
    /// wedged (2026-11-15).
    private var isRestartingLoop = false

    private func tick(_ a: Double) {
        timeA = a
        timeB = playerB.currentTime().seconds
        guard isPlaying, !isRestartingLoop else { return }
        jointTime = timeline.jointTime(fromA: a)
        let range = timeline.playRange
        if jointTime >= range.upperBound - 0.02 {
            guard loop else {
                pause()
                return
            }
            isRestartingLoop = true
            playerA.pause()
            playerB.pause()
            seekTogether(to: range.lowerBound) { [weak self] in
                guard let self else { return }
                self.isRestartingLoop = false
                // Paused or Done while it jumped: stay stopped.
                guard self.isPlaying else { return }
                self.startTogether()
            }
        }
    }

    func framing(_ which: Which) -> ComparePaneFraming { which == .a ? framingA : framingB }

    func setFraming(_ framing: ComparePaneFraming, for which: Which) {
        var clamped = framing
        clamped.zoom = min(max(framing.zoom, ComparePaneFraming.zoomRange.lowerBound), ComparePaneFraming.zoomRange.upperBound)
        if which == .a { framingA = clamped } else { framingB = clamped }
    }

    // MARK: Lining up one clip

    func seek(_ which: Which, to seconds: Double) {
        pause()
        let player = which == .a ? playerA : playerB
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if which == .a { timeA = seconds } else { timeB = seconds }
    }

    func step(_ which: Which, by frames: Int) {
        pause()
        let player = which == .a ? playerA : playerB
        player.currentItem?.step(byCount: frames)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.timeA = self.playerA.currentTime().seconds
            self.timeB = self.playerB.currentTime().seconds
        }
    }

    func isSyncSet(_ which: Which) -> Bool {
        which == .a ? timeline.isSyncSetA : timeline.isSyncSetB
    }

    /// Set Sync Here is a toggle: on marks this frame, off clears it.
    func toggleSync(_ which: Which) {
        if isSyncSet(which) {
            timeline.clearSync(a: which == .a, b: which == .b)
        } else if which == .a {
            timeline.setSync(a: playerA.currentTime().seconds)
        } else {
            timeline.setSync(b: playerB.currentTime().seconds)
        }
        jointTime = 0
    }

    func resetSync() {
        timeline.clearSync(a: true, b: true)
        seekTogether(to: 0)
    }

    // MARK: Together

    func seekTogether(to t: Double, then: (() -> Void)? = nil) {
        let times = timeline.times(at: t)
        jointTime = t
        timeA = times.a
        timeB = times.b
        let group = DispatchGroup()
        group.enter()
        playerA.seek(to: CMTime(seconds: times.a, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        group.enter()
        playerB.seek(to: CMTime(seconds: times.b, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        group.notify(queue: .main) { then?() }
    }

    func stepTogether(by frames: Int) {
        pause()
        playerA.currentItem?.step(byCount: frames)
        playerB.currentItem?.step(byCount: frames)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.timeA = self.playerA.currentTime().seconds
            self.timeB = self.playerB.currentTime().seconds
            self.jointTime = self.timeline.jointTime(fromA: self.timeA)
        }
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            let range = timeline.playRange
            var start = jointTime
            if start < range.lowerBound || start >= range.upperBound - 0.05 { start = range.lowerBound }
            isPlaying = true
            seekTogether(to: start) { [weak self] in
                guard let self, self.isPlaying else { return }
                self.startTogether()
            }
        }
    }

    /// Both start on the same host-clock tick from the exact times the
    /// joint clock says, so they stay locked.
    private func startTogether() {
        let times = timeline.times(at: jointTime)
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 10))
        playerA.setRate(rate, time: CMTime(seconds: times.a, preferredTimescale: 600), atHostTime: host)
        playerB.setRate(rate, time: CMTime(seconds: times.b, preferredTimescale: 600), atHostTime: host)
        isPlaying = true
    }

    func pause() {
        playerA.pause()
        playerB.pause()
        isPlaying = false
    }

    // MARK: Start / End (toggles, like Set Sync Here)

    func toggleStart() {
        if timeline.trimStart != nil {
            timeline.trimStart = nil
        } else {
            timeline.setStart(jointTime)
        }
    }

    func toggleEnd() {
        if timeline.trimEnd != nil {
            timeline.trimEnd = nil
        } else {
            timeline.setEnd(jointTime)
        }
    }

    enum Which { case a, b }
}

struct MomentCompareView: View {
    let momentA: Moment
    let momentB: Moment
    let urlA: URL
    let urlB: URL
    let onClose: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @StateObject private var controller: MomentCompareController
    @State private var mode: Mode = .lineUp
    @State private var sideBySide = false
    @State private var isSaving = false
    @State private var saveMessage: String? = nil

    enum Mode: Hashable { case lineUp, together }

    init(momentA: Moment, momentB: Moment, urlA: URL, urlB: URL, onClose: @escaping () -> Void) {
        self.momentA = momentA
        self.momentB = momentB
        self.urlA = urlA
        self.urlB = urlB
        self.onClose = onClose
        _controller = StateObject(wrappedValue: MomentCompareController(urlA: urlA, urlB: urlB))
    }

    private var layout: CompareLayout { sideBySide ? .sideBySide : .stacked }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                videos
                Picker("Mode", selection: $mode) {
                    Text("Line Up").tag(Mode.lineUp)
                    Text("Play Together").tag(Mode.together)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newMode in
                    controller.pause()
                    if newMode == .together { controller.seekTogether(to: 0) }
                }
                .accessibilityIdentifier("compare.mode")

                if let saveMessage {
                    Text(saveMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    if mode == .lineUp {
                        VStack(spacing: 14) {
                            Text("Find the same instant in each clip - say, the front foot landing - and tap Set Sync Here on both. Pinch a video to zoom in, drag to move it, double-tap to reset.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            lineUpControls(.a, title: momentA.displayTitle, time: controller.timeA,
                                           duration: controller.timeline.durationA, sync: controller.timeline.syncA)
                            lineUpControls(.b, title: momentB.displayTitle, time: controller.timeB,
                                           duration: controller.timeline.durationB, sync: controller.timeline.syncB)
                        }
                    } else {
                        togetherControls
                    }
                }
            }
            .padding()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        controller.pause()
                        onClose()
                    }
                    .accessibilityIdentifier("compare.done")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        sideBySide.toggle()
                    } label: {
                        Image(systemName: sideBySide ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    }
                    .accessibilityLabel(sideBySide ? "Stack" : "Side by Side")
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("compare.save")
                }
            }
        }
        .overlay {
            if isSaving {
                GameCaptionWorkingOverlay(text: "Saving compare…")
            }
        }
        .onDisappear { controller.pause() }
    }

    // MARK: Videos

    @ViewBuilder
    private var videos: some View {
        let stack = sideBySide ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        stack {
            videoCard(.a, player: controller.playerA, title: momentA.displayTitle)
            videoCard(.b, player: controller.playerB, title: momentB.displayTitle)
        }
        .frame(maxHeight: sideBySide ? 300 : 420)
    }

    /// Shaped like its pane in the saved video, so what's framed here is
    /// what's saved.
    private func videoCard(_ which: MomentCompareController.Which, player: AVPlayer, title: String) -> some View {
        ComparePane(
            player: player,
            framing: Binding(get: { controller.framing(which) }, set: { controller.setFraming($0, for: which) })
        )
        .aspectRatio(layout.paneAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("\(which == .a ? "A" : "B") · \(title)")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            let zoom = controller.framing(which).zoom
            if zoom > 1.01 {
                Text(String(format: "%.1f×", zoom))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Controls

    private func lineUpControls(_ which: MomentCompareController.Which, title: String, time: Double, duration: Double, sync: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(which == .a ? "A" : "B") · \(title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.2fs", time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { time }, set: { controller.seek(which, to: $0) }),
                in: 0...max(duration, 0.01)
            )
            .tint(Color.pitchMarkActiveGray)
            HStack(spacing: 10) {
                frameButton("backward.frame.fill", label: "Back one frame") { controller.step(which, by: -1) }
                frameButton("forward.frame.fill", label: "Forward one frame") { controller.step(which, by: 1) }
                Spacer()
                syncToggle(which, sync: sync)
            }
            zoomRow(which)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    /// Outlined "Set Sync Here" when off; filled "Synced 1.23s" with a
    /// check when on - tap again to clear.
    private func syncToggle(_ which: MomentCompareController.Which, sync: Double) -> some View {
        let isOn = controller.isSyncSet(which)
        return Button {
            controller.toggleSync(which)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "flag")
                Text(isOn ? String(format: "Synced %.2fs", sync) : "Set Sync Here")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : Color.pitchMarkActiveGray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color.clear)
            )
            .overlay(
                Capsule().stroke(Color.pitchMarkActiveGray, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Synced. Tap to clear the sync point." : "Set Sync Here")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("compare.sync.\(which == .a ? "a" : "b")")
    }

    /// Zoom by slider too - pinching a small video is fiddly.
    private func zoomRow(_ which: MomentCompareController.Which) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { controller.framing(which).zoom },
                    set: { var f = controller.framing(which); f.zoom = $0; controller.setFraming(f, for: which) }
                ),
                in: ComparePaneFraming.zoomRange
            )
            .tint(Color.pitchMarkActiveGray)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
            Button("Reset") { controller.setFraming(ComparePaneFraming(), for: which) }
                .font(.caption.weight(.semibold))
                .disabled(controller.framing(which) == ComparePaneFraming())
        }
    }

    private var togetherControls: some View {
        let joint = controller.timeline.jointRange
        let play = controller.timeline.playRange
        return VStack(spacing: 14) {
            Slider(
                value: Binding(get: { controller.jointTime }, set: { controller.pause(); controller.seekTogether(to: $0) }),
                in: joint.lowerBound...max(joint.upperBound, joint.lowerBound + 0.01)
            )
            .tint(Color.pitchMarkActiveGray)
            .background(alignment: .center) { rangeBar(joint: joint, play: play) }
            HStack(spacing: 18) {
                frameButton("backward.frame.fill", label: "Both back one frame") { controller.stepTogether(by: -1) }
                Button {
                    controller.togglePlay()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.pitchMarkActiveGray)
                }
                .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("compare.play")
                frameButton("forward.frame.fill", label: "Both forward one frame") { controller.stepTogether(by: 1) }
            }

            // Start / End: what plays on loop and what Save keeps. Big
            // toggles, like Set Sync Here - small text buttons were easy
            // to forget (2026-11-15).
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Clip Length")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1fs", play.upperBound - play.lowerBound))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
                HStack(spacing: 10) {
                    markToggle(
                        isOn: controller.timeline.trimStart != nil,
                        offTitle: "Start Here",
                        onTitle: String(format: "Start %.2fs", controller.timeline.trimStart ?? 0),
                        icon: "arrow.right.to.line",
                        identifier: "compare.start"
                    ) { controller.toggleStart() }
                    markToggle(
                        isOn: controller.timeline.trimEnd != nil,
                        offTitle: "End Here",
                        onTitle: String(format: "End %.2fs", controller.timeline.trimEnd ?? 0),
                        icon: "arrow.left.to.line",
                        identifier: "compare.end"
                    ) { controller.toggleEnd() }
                }
                Text("Play to a spot, then tap Start Here or End Here. Tap again to clear. Loop and Save use this stretch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            Picker("Speed", selection: $controller.rate) {
                Text("¼×").tag(Float(0.25))
                Text("½×").tag(Float(0.5))
                Text("1×").tag(Float(1))
            }
            .pickerStyle(.segmented)
            .onChange(of: controller.rate) { _, _ in
                if controller.isPlaying { controller.pause(); controller.togglePlay() }
            }
            Toggle("Loop", isOn: $controller.loop)
            Toggle("Sound (clip A)", isOn: $controller.soundOn)
            Text("Save keeps the framing, the layout, Start to End and this speed. Sound is saved only at 1×.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Reset Sync Points") { controller.resetSync() }
                .font(.footnote)
        }
    }

    /// The Start-End stretch shaded under the timeline.
    private func rangeBar(joint: ClosedRange<Double>, play: ClosedRange<Double>) -> some View {
        GeometryReader { proxy in
            let span = max(joint.upperBound - joint.lowerBound, 0.001)
            let x0 = (play.lowerBound - joint.lowerBound) / span * proxy.size.width
            let x1 = (play.upperBound - joint.lowerBound) / span * proxy.size.width
            if controller.timeline.trimStart != nil || controller.timeline.trimEnd != nil {
                Capsule()
                    .fill(Color.pitchMarkActiveGray.opacity(0.3))
                    .frame(width: max(x1 - x0, 4), height: 14)
                    .position(x: (x0 + x1) / 2, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// Outlined when off, filled with a check when on - same as Sync.
    private func markToggle(isOn: Bool, offTitle: String, onTitle: String, icon: String,
                            identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                Text(isOn ? onTitle : offTitle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline)
            .foregroundStyle(isOn ? Color.white : Color.pitchMarkActiveGray)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color.clear))
            .overlay(Capsule().stroke(Color.pitchMarkActiveGray, lineWidth: 2))
            .animation(.easeInOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func frameButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Save

    private func save() {
        controller.pause()
        isSaving = true
        saveMessage = nil
        let settings = MomentCompareExporter.Settings(
            timeline: controller.timeline,
            framingA: controller.framingA,
            framingB: controller.framingB,
            layout: layout,
            rate: Double(controller.rate),
            includeSound: controller.soundOn
        )
        MomentCompareExporter.export(urlA: urlA, urlB: urlB, settings: settings) { result in
            switch result {
            case .failure(let error):
                isSaving = false
                saveMessage = "Couldn't save: \(error.localizedDescription)"
            case .success(let fileURL):
                let range = settings.timeline.playRange
                var moment = Moment(durationSeconds: (range.upperBound - range.lowerBound) / max(settings.rate, 0.01))
                moment.title = "\(momentA.displayTitle) vs \(momentB.displayTitle)"
                let tags = Array(Set((momentA.playerTags ?? []) + (momentB.playerTags ?? [])))
                moment.playerTags = tags.isEmpty ? nil : tags
                authManager.saveMoment(moment) { saved in
                    isSaving = false
                    switch saved {
                    case .success(let new):
                        if let id = new.id { saveLocalMomentVideo(from: fileURL, momentId: id) }
                        saveMessage = "Saved to Moments as \u{201C}\(moment.title ?? "Compare")\u{201D}."
                    case .failure(let error):
                        saveMessage = "Couldn't save: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

/// One clip in its pane: pinch to zoom, drag to move, double-tap to reset.
/// The gestures sit on a clear layer above the video - an AVPlayerLayer
/// view doesn't pass touches to SwiftUI gestures reliably (see the note
/// in MomentZoomEditorView).
private struct ComparePane: View {
    let player: AVPlayer
    @Binding var framing: ComparePaneFraming

    @State private var pinchStart: Double? = nil
    @State private var dragStart: CGSize? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.black
                PlayerContainerView(player: player)
                    .scaleEffect(framing.zoom)
                    .offset(x: framing.offset.width * size.width, y: framing.offset.height * size.height)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let start = pinchStart ?? framing.zoom
                                pinchStart = start
                                framing.zoom = start * Double(value)
                            }
                            .onEnded { _ in pinchStart = nil }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { value in
                                        let start = dragStart ?? framing.offset
                                        dragStart = start
                                        framing.offset = CGSize(
                                            width: start.width + value.translation.width / max(size.width, 1),
                                            height: start.height + value.translation.height / max(size.height, 1)
                                        )
                                    }
                                    .onEnded { _ in dragStart = nil }
                            )
                    )
                    .onTapGesture(count: 2) { framing = ComparePaneFraming() }
            }
            .clipped()
        }
    }
}

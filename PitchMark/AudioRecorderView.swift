//
//  AudioRecorderView.swift
//  PitchMark
//
//  2026-09-28: records a new audio library asset. Deliberately simple -
//  record/stop + an elapsed-time label, no waveform/scrubbing/trim,
//  matching "capture now" simplicity already established for Moments
//  (MomentsLibraryView's own header comment). NSMicrophoneUsageDescription
//  already exists in Info.plist (added in Phase 6 for Moments recording);
//  no new permission string needed.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

enum AudioRecordingAuthorization {
    case ready
    case denied
}

/// Mirrors requestAssetCameraAccess's shape (AssetCreationFlow.swift)
/// but for microphone access via the modern (iOS 17+) AVAudioApplication
/// API rather than the older AVAudioSession.recordPermission.
func requestAudioRecordingAccess(completion: @escaping (AudioRecordingAuthorization) -> Void) {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
        completion(.ready)
    case .undetermined:
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted ? .ready : .denied)
            }
        }
    case .denied:
        completion(.denied)
    @unknown default:
        completion(.denied)
    }
}

struct AudioRecorderView: View {
    var onSave: () -> Void
    var onCancel: () -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var recordedURL: URL?
    @State private var assetName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(formattedTime(elapsed))
                .font(.system(size: 48, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? .red : .primary)

            Button {
                toggleRecording()
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 84))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            if recordedURL != nil, !isRecording {
                VStack(spacing: 12) {
                    TextField("Name", text: $assetName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 40)

                    HStack(spacing: 20) {
                        Button("Record Again") {
                            recordedURL = nil
                            elapsed = 0
                        }
                        .buttonStyle(.bordered)

                        Button(isSaving ? "Saving…" : "Save") {
                            saveRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Cancel") { onCancel() }
                .disabled(isSaving)
        }
        .padding()
        .onDisappear {
            recorder?.stop()
            stopTimer()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            newRecorder.record()
            recorder = newRecorder
            recordedURL = tempURL
            elapsed = 0
            isRecording = true
            startTimer()
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        recorder?.stop()
        isRecording = false
        stopTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsed += 0.1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func saveRecording() {
        guard let recordedURL else { return }
        isSaving = true
        errorMessage = nil
        let trimmedName = assetName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? "New Audio" : trimmedName
        let fallbackDuration = elapsed

        Task {
            let asset = AVURLAsset(url: recordedURL)
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : fallbackDuration

            await MainActor.run {
                authManager.saveAudioAsset(AudioAssetItem(name: finalName, durationSeconds: seconds)) { result in
                    isSaving = false
                    switch result {
                    case .success(let saved):
                        if let id = saved.id {
                            saveLocalAudioAsset(from: recordedURL, assetId: id)
                        }
                        onSave()
                    case .failure(let error):
                        errorMessage = "Couldn't save: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

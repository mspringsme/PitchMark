//
//  AudioWaveform.swift
//  PitchMark
//
//  2026-09-28: a lightweight visual waveform for the audio editor - the
//  Moment's own original audio (always shown) and whichever overlay
//  clip is currently selected (shown only then, extracted per asset id
//  and cached so re-selecting the same clip doesn't redecode it).
//
//  `bucketPeaks` (pure - verified standalone) turns a raw PCM sample
//  array into a small, fixed-size peak-per-bucket array cheap enough to
//  draw as a fixed number of SwiftUI bars regardless of clip length.
//  `extractWaveformPeaks` (impure - AVAssetReader, can't be verified in
//  this sandbox per the project's no-audio-decoding constraint) is the
//  only piece that turns a real audio file into those raw samples.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

/// Downsamples `samples` into `bucketCount` peak-amplitude values,
/// normalized so the loudest bucket is 1.0 (a shape/rhythm cue for
/// editing, not a calibrated level meter - matches how every waveform
/// UI in a video/audio editor is actually used). The last bucket
/// absorbs any remainder from integer division so no trailing samples
/// are silently dropped.
func bucketPeaks(samples: [Float], bucketCount: Int) -> [Float] {
    guard bucketCount > 0, !samples.isEmpty else { return [] }
    let samplesPerBucket = max(1, samples.count / bucketCount)
    var peaks: [Float] = []
    peaks.reserveCapacity(bucketCount)
    for bucket in 0..<bucketCount {
        let start = bucket * samplesPerBucket
        let end = bucket == bucketCount - 1 ? samples.count : min(start + samplesPerBucket, samples.count)
        guard start < end else {
            peaks.append(0)
            continue
        }
        var peak: Float = 0
        for i in start..<end {
            peak = max(peak, abs(samples[i]))
        }
        peaks.append(peak)
    }
    let maxPeak = peaks.max() ?? 0
    guard maxPeak > 0 else { return peaks }
    return peaks.map { $0 / maxPeak }
}

enum WaveformError: Error {
    case noAudioTrack
    case readFailed
}

/// Reads every PCM sample from `url`'s audio track and reduces it to
/// `bucketCount` peaks via `bucketPeaks`. Runs off the main thread -
/// short Moments clips only, so reading the whole track into memory as
/// Floats is fine; this isn't built to scale to long-form audio.
func extractWaveformPeaks(from url: URL, bucketCount: Int, completion: @escaping (Result<[Float], Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            DispatchQueue.main.async { completion(.failure(WaveformError.noAudioTrack)) }
            return
        }

        do {
            let reader = try AVAssetReader(asset: asset)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            reader.startReading()

            var samples: [Float] = []
            while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.size)
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
                samples.reserveCapacity(samples.count + data.count)
                for value in data {
                    samples.append(Float(value) / Float(Int16.max))
                }
            }

            guard reader.status == .completed else {
                DispatchQueue.main.async { completion(.failure(WaveformError.readFailed)) }
                return
            }

            let peaks = bucketPeaks(samples: samples, bucketCount: bucketCount)
            DispatchQueue.main.async { completion(.success(peaks)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}

/// Fixed-count bars spanning the available width - no GeometryReader
/// needed since `peaks` is already a fixed size (`bucketPeaks`' job),
/// each bar just takes an equal `.frame(maxWidth: .infinity)` share.
struct WaveformView: View {
    let peaks: [Float]
    var color: Color = Color.white.opacity(0.6)

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(peaks.enumerated()), id: \.offset) { _, peak in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(CGFloat(peak) * 32, 2))
            }
        }
        .frame(height: 32)
    }
}

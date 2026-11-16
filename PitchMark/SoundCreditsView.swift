//
//  SoundCreditsView.swift
//  PitchMark
//
//  2026-09-29: a courtesy credits list for the bundled sound pack. CC0
//  doesn't legally require attribution, but several sources logged in
//  ~/Documents/Art Created/PitchMarkAudio/license-log.csv "request
//  optional credit." Reads straight from `bundledAudioAssets`
//  (AudioAssetItem.swift), which already carries author/license/
//  sourceURL merged in from that CSV at pack-assembly time - nothing
//  here re-parses or duplicates that sourcing data.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

struct SoundCreditsView: View {
    /// The full MIT notice shipped with the icons.
    private var licenseText: String? {
        Bundle.main.url(forResource: "PHOSPHOR-LICENSE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    var body: some View {
        List {
            // The built-in overlay icons (OverlayIcons.swift) - MIT asks
            // for the notice to travel with them (2026-11-15).
            Section("Icons") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phosphor Icons")
                        .font(.subheadline.weight(.semibold))
                    Text("Copyright (c) 2023 Phosphor Icons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MIT License")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: "https://phosphoricons.com") {
                        Link("phosphoricons.com", destination: url)
                            .font(.caption2)
                    }
                    if let licenseText {
                        Text(licenseText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 2)
            }

            if !bundledAudioAssets.isEmpty {
            Section("Sounds") {
            ForEach(bundledAudioAssets) { asset in
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.subheadline.weight(.semibold))
                    if let author = asset.author {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let license = asset.license {
                        Text(license)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let sourceURL = asset.sourceURL, let url = URL(string: sourceURL) {
                        Link("View source", destination: url)
                            .font(.caption2)
                    }
                }
                .padding(.vertical, 2)
            }
            }
            }
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

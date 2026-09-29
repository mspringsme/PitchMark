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
    var body: some View {
        List {
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
        .navigationTitle("Sound Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

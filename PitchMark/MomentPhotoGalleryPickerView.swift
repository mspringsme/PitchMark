//
//  MomentPhotoGalleryPickerView.swift
//  PitchMark
//
//  2026-10-07 - lets MomentDetailView's Photos section pull in a photo
//  that already lives in PitchMark's own Moments catalog (a photo-only
//  Moment, or a photo already attached to some other Moment), as a
//  second source alongside the system PhotosPicker (the phone's camera
//  roll). These are two different photo sources with no overlap, so
//  they get two distinct entry points rather than one merged picker.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI

private struct MomentPhotoRef: Identifiable, Hashable {
    let momentId: String
    let index: Int
    var id: String { "\(momentId)-\(index)" }
}

struct MomentPhotoGalleryPickerView: View {
    let moments: [Moment]
    let excludingMomentId: String?
    let onAdd: ([Data]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<MomentPhotoRef> = []
    @State private var thumbnails: [MomentPhotoRef: UIImage] = [:]

    private var photoRefs: [MomentPhotoRef] {
        moments
            .filter { $0.id != nil && $0.id != excludingMomentId }
            .flatMap { moment -> [MomentPhotoRef] in
                guard let id = moment.id, let count = moment.photoCount, count > 0 else { return [] }
                return (0..<count).map { MomentPhotoRef(momentId: id, index: $0) }
            }
    }

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        NavigationView {
            Group {
                if photoRefs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No photos in your Moments library yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(photoRefs) { ref in
                                cell(for: ref)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Moments Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add (\(selected.count))") {
                        addSelected()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for ref: MomentPhotoRef) -> some View {
        let isSelected = selected.contains(ref)
        Button {
            if isSelected {
                selected.remove(ref)
            } else {
                selected.insert(ref)
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = thumbnails[ref] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            guard thumbnails[ref] == nil,
                  let url = localMomentPhotoURL(momentId: ref.momentId, index: ref.index) else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { thumbnails[ref] = image }
            }
        }
    }

    private func addSelected() {
        let datas: [Data] = selected.compactMap { ref in
            guard let url = localMomentPhotoURL(momentId: ref.momentId, index: ref.index) else { return nil }
            return try? Data(contentsOf: url)
        }
        onAdd(datas)
        dismiss()
    }
}

import SwiftUI
import AVKit

struct LearnPitchMarkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTutorial = TutorialVideo.allCases[0]
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(TutorialVideo.allCases) { tutorial in
                        tutorialButton(for: tutorial)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else {
                        ContentUnavailableView(
                            "Video Not Found",
                            systemImage: "video.slash",
                            description: Text("Make sure the tutorial videos are included in the PitchMark target.")
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Learn PitchMark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadSelectedVideo)
            .onChange(of: selectedTutorial) { _, _ in
                loadSelectedVideo()
            }
            .onDisappear {
                player?.pause()
            }
        }
    }

    private func tutorialButton(for tutorial: TutorialVideo) -> some View {
        let isSelected = selectedTutorial == tutorial

        return Button {
            selectedTutorial = tutorial
        } label: {
            Text(tutorial.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.16))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.9 : 0.34), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func loadSelectedVideo() {
        player?.pause()
        guard let url = selectedTutorial.url else {
            player = nil
            return
        }
        player = AVPlayer(url: url)
    }
}

private enum TutorialVideo: String, CaseIterable, Identifiable {
    case tutorial1
    case tutorial2
    case tutorial3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tutorial1: "Tutorial 1"
        case .tutorial2: "Tutorial 2"
        case .tutorial3: "Tutorial 3"
        }
    }

    private var fileName: String {
        switch self {
        case .tutorial1: "Tutorial 1 in Wrapper --"
        case .tutorial2: "Tutorial 2 in wrapper --"
        case .tutorial3: "Tutorial 3 in Wrapper --"
        }
    }

    var url: URL? {
        Bundle.main.url(
            forResource: fileName,
            withExtension: "mp4",
            subdirectory: "Tutorial finished vids"
        ) ?? Bundle.main.url(forResource: fileName, withExtension: "mp4")
    }
}

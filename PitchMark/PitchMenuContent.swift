import SwiftUI

struct PitchMenuContent: View {
    let adjustedLabel: String
    let tappedPoint: CGPoint
    let location: PitchLocation
    let setLastTapped: (CGPoint?) -> Void
    let setCalledPitch: (PitchCall?) -> Void
    let selectedPitches: Set<String>
    let pitchCodeAssignments: [PitchCodeAssignment]
    let lastTappedPosition: CGPoint?
    let calledPitch: PitchCall?
    let setSelectedPitch: (String) -> Void
    let isEncryptedMode: Bool

    var body: some View {
        Group {
            if selectedPitches.isEmpty {
                Button("Select pitches first") {}.disabled(true)
            } else {
                let orderedSelected: [String] = {
                    let base = pitchOrder.filter { selectedPitches.contains($0) }
                    let extras = Array(selectedPitches.subtracting(Set(pitchOrder))).sorted()
                    return base + extras
                }()

                ForEach(orderedSelected, id: \.self) { pitch in
                    let assignedCodes = pitchCodeAssignments
                        .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                        .map(\.code)

                    let codeSuffix = assignedCodes.isEmpty
                        ? "     --"
                        : "   \(assignedCodes.joined(separator: ", "))"

                    Button("\(pitch)\(codeSuffix)") {
                        withAnimation {
                            setSelectedPitch(pitch)

                            let newCall = PitchCall(
                                pitch: pitch,
                                location: adjustedLabel,
                                isStrike: location.isStrike,
                                codes: assignedCodes
                            )

                            if lastTappedPosition == tappedPoint,
                               let currentCall = calledPitch,
                               currentCall.location == newCall.location,
                               currentCall.pitch == newCall.pitch {
                                setLastTapped(nil)
                                setCalledPitch(nil)
                            } else {
                                setLastTapped(tappedPoint)
                                setCalledPitch(newCall)
                            }
                        }
                    }
                }
            }
        }
    }
}

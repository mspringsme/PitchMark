//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
enum BatterSide: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left-Handed Batter"
        case .right: return "Right-Handed Batter"
        }
    }
}
struct PitchCall {
    let type: String      // "Strike" or "Ball"
    let pitch: String     // e.g. "Curve"
    let location: String  // e.g. "High and Inside"
}
struct PitchLocation {
    let label: String
    let isStrike: Bool
}
struct GridLocation: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let label: String
}
let strikeGrid: [GridLocation] = [
    .init(row: 0, col: 0, label: "Strike: High outer half"),
    .init(row: 0, col: 1, label: "Strike: High in zone"),
    .init(row: 0, col: 2, label: "Strike: High inner half"),
    .init(row: 1, col: 0, label: "Strike: outer half"),
    .init(row: 1, col: 1, label: "Strike: Down the Middle"),
    .init(row: 1, col: 2, label: "Strike: inner half"),
    .init(row: 2, col: 0, label: "Strike: Low outer half"),
    .init(row: 2, col: 1, label: "Strike: low in zone"),
    .init(row: 2, col: 2, label: "Strike: Low inner half")
]
struct PitchLabelManager {
    let batterSide: BatterSide

    func adjustedLabel(from rawLabel: String) -> String {
        guard batterSide == .left else { return rawLabel }

        return rawLabel
            .replacingOccurrences(of: "Inside", with: "TEMP")
            .replacingOccurrences(of: "Outside", with: "Inside")
            .replacingOccurrences(of: "TEMP", with: "Outside")
    }

    func parse(label: String, pitch: String) -> PitchCall? {
        let adjusted = adjustedLabel(from: label)
        let parts = adjusted.components(separatedBy: ": ")
        guard parts.count == 2 else { return nil }

        return PitchCall(type: parts[0], pitch: pitch, location: parts[1])
    }
}

struct PitchTrackerView: View {
    @State private var pitcherName: String = ""
    @State private var selectedPitches: Set<String> = []
    @State private var calledPitch: PitchCall? = nil
    @FocusState private var isPitcherFieldFocused: Bool
    @State private var lastTappedPosition: CGPoint? = nil
    @State private var batterSide: BatterSide = .right
    
    let allPitches = ["2 Seam", "4 Seam", "Curve", "Screw", "Change", "Drop", "Rise"]
    let buttonSize: CGFloat = 30
    
    
    func adjustedLabel(for location: PitchLocation, batterSide: BatterSide) -> String {
        guard batterSide == .left else { return location.label }

        return location.label
            .replacingOccurrences(of: "Inside", with: "TEMP")
            .replacingOccurrences(of: "Outside", with: "Inside")
            .replacingOccurrences(of: "TEMP", with: "Outside")
    }
    
    func pitchButton(
        x: CGFloat,
        y: CGFloat,
        location: PitchLocation,
        labelManager: PitchLabelManager,
        lastTappedPosition: CGPoint?,
        setLastTapped: @escaping (CGPoint?) -> Void,
        setCalledPitch: @escaping (PitchCall?) -> Void,
        buttonSize: CGFloat  // 👈 Add this
    ) -> some View {
        let isSelected = lastTappedPosition == CGPoint(x: x, y: y)

        return Menu {
            if selectedPitches.isEmpty {
                    Button("Select pitches first") {}
                        .disabled(true)
                } else {
                    ForEach(Array(selectedPitches), id: \.self) { pitch in
                        Button(pitch) {
                            withAnimation {
                                let tappedPoint = CGPoint(x: x, y: y)
                                let newCall = labelManager.parse(label: location.label, pitch: pitch)

                                if lastTappedPosition == tappedPoint,
                                   let currentCall = calledPitch,
                                   let newCall = newCall,
                                   currentCall.location == newCall.location,
                                   currentCall.pitch == newCall.pitch {
                                    // Toggle off
                                    setLastTapped(nil)
                                    setCalledPitch(nil)
                                } else if let newCall = newCall {
                                    // Select new pitch
                                    setLastTapped(tappedPoint)
                                    setCalledPitch(newCall)
                                }
                            }
                        }
                    }
                }
        } label: {
            Group {
                if location.isStrike {
                    Circle()
                        .fill(isSelected ? Color.green.opacity(0.6) : Color.green)
                        .overlay(Circle().stroke(Color.black, lineWidth: isSelected ? 3 : 0))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.red.opacity(0.6) : Color.red)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: isSelected ? 3 : 0))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .position(x: x, y: y)
        .zIndex(1)
    }
    
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(spacing: 4) {
                        // 🧑‍✈️ Pitcher Name
                        TextField("Pitcher Name", text: $pitcherName)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.default)
                            .focused($isPitcherFieldFocused)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        
                        // 🧩 Toggle Chips for Pitch Selection
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allPitches, id: \.self) { pitch in
                                    ToggleChip(pitch: pitch, selectedPitches: $selectedPitches)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                        }
                        
                        Divider()
                            .padding(.bottom, 4)
                        HStack(spacing: 16) {
//                            // 🔄 Reset Button
//                            Button {
//                                withAnimation {
//                                    lastTappedPosition = nil
//                                    calledPitch = nil
//                                }
//                            } label: {
//                                Image(systemName: "arrow.triangle.2.circlepath")
//                                    .font(.body)
//                                    .foregroundColor(.red)
//                                    .padding(6)
//                                    .background(Color.gray.opacity(0.2))
//                                    .clipShape(Circle())
//                            }
//                            .accessibilityLabel("Reset pitch selection")
                            
                            // 🧍‍♂️ Batter Side Buttons
                            Button("L Batter") {
                                batterSide = .left
                            }
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(batterSide == .left ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            
                            Button("R Batter") {
                                batterSide = .right
                            }
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(batterSide == .right ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center) // optional for text alignment
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        Divider()
                        
                        GeometryReader { geo in
                            let zoneWidth = geo.size.width * 0.4
                            let zoneHeight = geo.size.height * 0.5
                            let cellWidth = zoneWidth / 3
                            let cellHeight = zoneHeight / 3
                            let buttonSize = min(cellWidth, cellHeight) * 0.6
                            let originX = geo.size.width / 2 - zoneWidth / 2
                            let originY = geo.size.height / 2 - zoneHeight / 2
                            let labelManager = PitchLabelManager(batterSide: batterSide)

                            ZStack {
                                // 🟥 Strike zone outline
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 2)
                                    .frame(width: zoneWidth, height: zoneHeight)
                                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                                // 🟢 Strike buttons (grid-based)
                                ForEach(strikeGrid) { loc in
                                    let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                                    let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2

                                    pitchButton(x: x, y: y,
                                                location: .init(label: loc.label, isStrike: true),
                                                labelManager: labelManager,
                                                lastTappedPosition: lastTappedPosition,
                                                setLastTapped: { lastTappedPosition = $0 },
                                                setCalledPitch: { calledPitch = $0 },
                                                buttonSize: buttonSize)
                                }

                                // 🔴 Ball buttons (optional: offset-based)
                                pitchButton(x: originX - buttonSize * 1.2, y: originY - buttonSize * 1.2,
                                            location: .init(label: "Ball: High and Outside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX + zoneWidth / 2, y: originY - buttonSize * 1.5,
                                            location: .init(label: "Ball: High", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX + zoneWidth + buttonSize * 1.2, y: originY - buttonSize * 1.2,
                                            location: .init(label: "Ball: High and Inside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX - buttonSize * 1.5, y: originY + zoneHeight / 2,
                                            location: .init(label: "Ball: Outside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX + zoneWidth + buttonSize * 1.5, y: originY + zoneHeight / 2,
                                            location: .init(label: "Ball: Inside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX - buttonSize * 1.2, y: originY + zoneHeight + buttonSize * 1.2,
                                            location: .init(label: "Ball: Low and Outside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX + zoneWidth / 2, y: originY + zoneHeight + buttonSize * 1.5,
                                            location: .init(label: "Ball: Low", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)

                                pitchButton(x: originX + zoneWidth + buttonSize * 1.2, y: originY + zoneHeight + buttonSize * 1.2,
                                            location: .init(label: "Ball: Low and Inside", isStrike: false),
                                            labelManager: labelManager,
                                            lastTappedPosition: lastTappedPosition,
                                            setLastTapped: { lastTappedPosition = $0 },
                                            setCalledPitch: { calledPitch = $0 },
                                            buttonSize: buttonSize)
                            }
                            
                        }
                        .frame(height: geo.size.height * 0.55)
                        
                        
                        Divider()
                        
                        // 📝 Called Pitch Display
                        if let call = calledPitch {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Called Pitch:")
                                    Text(call.type)
                                        .bold()
                                        .foregroundColor(call.type == "Strike" ? .green : .red)
                                }
                                Text("\(call.pitch) (\(call.location))")
                                    .foregroundColor(.primary)
                            }
                            .font(.headline)
                            .padding(.horizontal)
                            .transition(.opacity)
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.vertical)
                }
                Button {
                    withAnimation {
                        lastTappedPosition = nil
                        calledPitch = nil
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body)
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Reset pitch selection")
                .position(x: 30, y: geo.size.height * 0.72) // adjust Y to match divider
                // ✅ Batter icon overlay
                Group {
                    let iconSize: CGFloat = 28
                    let dividerY = geo.size.height * 0.2 // Adjust this ratio to match your layout
                    
                    if batterSide == .left {
                        Image("rightBatterIcon")
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                            .offset(x: 12, y: dividerY)
                    } else if batterSide == .right {
                        Image("leftBatterIcon")
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                            .offset(x: geo.size.width - iconSize - 12, y: dividerY)
                    }
                }
            }
        }
    }
    
}

// 🧩 Toggle Chip Component
struct ToggleChip: View {
    let pitch: String
    @Binding var selectedPitches: Set<String>

    var isSelected: Bool {
        selectedPitches.contains(pitch)
    }

    var body: some View {
        Text(pitch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2))
            .foregroundColor(.white)
            .cornerRadius(16)
            .onTapGesture {
                if isSelected {
                    selectedPitches.remove(pitch)
                } else {
                    selectedPitches.insert(pitch)
                }
            }
    }
}


#Preview {
    PitchTrackerView()
}

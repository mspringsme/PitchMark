//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI

struct PitchTrackerView: View {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var showCodeAssignmentSheet = false
    @State private var pitcherName: String = ""
    @State private var selectedPitches: Set<String> = []
    @State private var calledPitch: PitchCall? = nil
    @State private var lastTappedPosition: CGPoint? = nil
    @State private var batterSide: BatterSide = .right
    @State private var pitchCodeAssignments: [PitchCodeAssignment] = []
    @State private var selectedCode: String = ""
    @State private var selectedPitch: String = ""
    @State private var selectedLocation: String = ""
    @State private var gameIsActive: Bool = false
    @State private var showSettings = false
    @State private var showProfile = false
    @State private var templates: [PitchTemplate] = []
    @EnvironmentObject var authManager: AuthManager
    @State private var showProfileSheet = false
    @State private var showSignOutConfirmation = false
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplateEditor = false

    
    var body: some View {
        GeometryReader { geo in
            
            // 🟦 Scrollable top section
            //ScrollView {
            
            ZStack {
                VStack(spacing: 4) {
                    HStack {
                        Text(selectedTemplate?.name ?? "Select a template")
                                .font(.headline)
                                .foregroundColor(templates.isEmpty ? .gray : .primary)

                            Menu {
                                ForEach(templates, id: \.self) { template in
                                    Button(template.name) {
                                        selectedTemplate = template
                                        selectedPitches = Set(template.pitches)
                                        pitchCodeAssignments = template.codeAssignments
                                        // 🧹 Reset strike zone and called pitch state
                                        lastTappedPosition = nil
                                        calledPitch = nil
                                        
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                                    .imageScale(.large)
                                    .foregroundColor(templates.isEmpty ? .gray : .blue)
                            }
                            .disabled(templates.isEmpty) // ✅ disables interaction
                        Spacer() // 👈 Pushes content to the trailing edge
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                        }
                        Button(action: {
                            showSignOutConfirmation = true
                        }) {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(.green)
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Sign Out")
                        .confirmationDialog(
                            "Are you sure you want to sign out of \(authManager.userEmail)?",
                            isPresented: $showSignOutConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Sign Out", role: .destructive) {
                                authManager.signOut()
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6) // 👈 Optional: reduce top spacing
                    .padding(.bottom, 12)
                    
                    Divider()
                    // 🧩 Toggle Chips for Pitch Selection
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allPitches, id: \.self) { pitch in
                                ToggleChip(
                                    pitch: pitch,
                                    selectedPitches: $selectedPitches,
                                    template: selectedTemplate,
                                    codeAssignments: pitchCodeAssignments
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        .padding(.top, 10)
                    }
                    
                    Divider()
                        .padding(.bottom, 4)
                    
                    // 🧍‍♂️ Batter Side Buttons
                    HStack(spacing: 16) {
                        
                        Button("L Batter") {
                            withAnimation {
                                batterSide = .left
                            }
                        }
                        .font(.body)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(batterSide == .left ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        
                        Button("R Batter") {
                            withAnimation {
                                batterSide = .right
                            }
                        }
                        .font(.body)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(batterSide == .right ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    
                    Divider()
                    
                    VStack {
                        if let selectedTemplate = selectedTemplate {
                            Text("")
                        StrikeZoneView(
                            geo: geo,
                            batterSide: batterSide,
                            lastTappedPosition: lastTappedPosition,
                            setLastTapped: { lastTappedPosition = $0 },
                            calledPitch: calledPitch,
                            setCalledPitch: { calledPitch = $0 },
                            selectedPitches: selectedPitches,
                            gameIsActive: gameIsActive,
                            selectedPitch: selectedPitch,
                            pitchCodeAssignments: pitchCodeAssignments
                        )
                        } else {
                            ZStack{
                                StrikeZoneView(
                                    geo: geo,
                                    batterSide: batterSide,
                                    lastTappedPosition: lastTappedPosition,
                                    setLastTapped: { lastTappedPosition = $0 },
                                    calledPitch: calledPitch,
                                    setCalledPitch: { calledPitch = $0 },
                                    selectedPitches: selectedPitches,
                                    gameIsActive: gameIsActive,
                                    selectedPitch: selectedPitch,
                                    pitchCodeAssignments: pitchCodeAssignments
                                )
                                Text("Choose a template")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .frame(height: geo.size.height * 0.7, alignment: .top)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(20)
                                    .padding(.top, 8)
                                
                            }
                        }
                    }
                    .frame(height: geo.size.height * 0.7) // ✅ Prevents overlap
                    .clipped()
                    .padding(.top, 8)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                
                BatterIconOverlay(batterSide: batterSide, geo: geo)
                
                ResetPitchButton(geo: geo) {
                    lastTappedPosition = nil
                    calledPitch = nil
                }
                
                // 📝 Called Pitch Display
                if let call = calledPitch {
                    CalledPitchView(call: call,
                                    pitchCodeAssignments: pitchCodeAssignments,
                                    batterSide: batterSide)
                        .frame(maxWidth: geo.size.width * 0.9)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 4)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.85)
                        .transition(.opacity)
                }
            } // end of z stack
            
        }
        .sheet(isPresented: $showCodeAssignmentSheet) {
            CodeAssignmentSettingsView(
                selectedPitch: $selectedPitch,
                selectedLocation: $selectedLocation,
                pitchCodeAssignments: $pitchCodeAssignments,
                allPitches: allPitches,
                allLocations: allLocationsFromGrid()
            )
            .padding()
        }
        .onAppear {
                    if authManager.isSignedIn {
                        authManager.loadTemplates { loadedTemplates in
                            self.templates = loadedTemplates
                        }
                    }
                }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                templates: $templates,
                allPitches: allPitches,
                selectedTemplate: $selectedTemplate
            )
            .environmentObject(authManager)
        }
    }
}

@ViewBuilder
func menuContent(
    for adjustedLabel: String,
    tappedPoint: CGPoint,
    location: PitchLocation,
    setLastTapped: @escaping (CGPoint?) -> Void,
    setCalledPitch: @escaping (PitchCall?) -> Void,
    selectedPitches: Set<String>,
    pitchCodeAssignments: [PitchCodeAssignment],
    lastTappedPosition: CGPoint?,
    calledPitch: PitchCall?
) -> some View {
    if selectedPitches.isEmpty {
        Button("Select pitches first") {}.disabled(true)
    } else {
        ForEach(Array(selectedPitches), id: \.self) { pitch in
            let assignedCodes = pitchCodeAssignments
                .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                .map(\.code)

            let codeSuffix = assignedCodes.isEmpty
                ? "     --"
                : "   \(assignedCodes.joined(separator: ", "))"

            Button("\(pitch)\(codeSuffix)") {
                withAnimation {
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

struct BatterIconOverlay: View {
    let batterSide: BatterSide
    let geo: GeometryProxy
    let iconSize: CGFloat = 28
    
    var body: some View {
        Group {
            if batterSide == .left {
                Image("rightBatterIcon")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .position(x: 30, y: geo.size.height * 0.25)
            } else {
                Image("leftBatterIcon")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .position(x: geo.size.width - 30, y: geo.size.height * 0.25)
            }
        }
    }
}

struct ResetPitchButton: View {
    let geo: GeometryProxy
    let resetAction: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation {
                resetAction()
            }
        }) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundColor(.red)
                .padding(6)
                .background(Color.gray.opacity(0.2))
                .clipShape(Circle())
        }
        .position(x: 30, y: geo.size.height * 0.65)
        .accessibilityLabel("Reset pitch selection")
//        .padding(.top, 12)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .offset(x: 0, y: geo.size.height * 0.1)
//        .padding(.leading, 12)
    }
}

struct CalledPitchView: View {
    let call: PitchCall
    let pitchCodeAssignments: [PitchCodeAssignment]
    let batterSide: BatterSide

    var body: some View {
        let labelManager = PitchLabelManager(batterSide: batterSide)
        let normalized = normalizedLabel(call.location.replacingOccurrences(of: "Strike ", with: "").replacingOccurrences(of: "Ball ", with: ""))
        let adjusted = labelManager.adjustedLabel(from: normalized)
        let prefix = labelManager.adjustedCallPrefix(for: normalized, isStrike: call.isStrike)
        let displayLocation = "\(prefix) \(adjusted)"

        let assignedCodes = pitchCodeAssignments
            .filter { $0.pitch == call.pitch && $0.location == displayLocation }
            .map(\.code)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Called Pitch:")
                Text(call.type)
                    .bold()
                    .foregroundColor(call.type == "Strike" ? .green : .red)
            }

            Text("\(call.pitch) (\(displayLocation))")
                .foregroundColor(.primary)

            if !assignedCodes.isEmpty {
                Text("Calls: \(assignedCodes.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else {
                Text("No assigned Calls for pitch/location")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .font(.headline)
        .padding(.horizontal)
        .transition(.opacity)
    }
}

struct LocationImageView: View {
    let location: String
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Base grid or strike zone
            Image("locationGrid") // your base image
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)

            // Highlight overlay
            if isSelected {
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(location)
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// 🧩 Toggle Chip Component
struct ToggleChip: View {
    let pitch: String
    @Binding var selectedPitches: Set<String>
    var template: PitchTemplate?
    var codeAssignments: [PitchCodeAssignment] = []

    var isSelected: Bool {
        selectedPitches.contains(pitch)
    }

    var isInTemplate: Bool {
        template?.pitches.contains(pitch) == true
    }

    var assignedCodeCount: Int {
        codeAssignments.filter { $0.pitch == pitch }.count
    }

    var body: some View {
        Text(pitch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (pitchColors[pitch] ?? .gray)
                    .opacity(isSelected ? 0.8 : 0.2)
            )
            .foregroundColor(.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isInTemplate ? Color.green : Color.clear, lineWidth: 2)
            )
            .overlay(
                Group {
                    if assignedCodeCount > 0 {
                        Text("\(assignedCodeCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .offset(x: 1, y: -12)
                    }
                },
                alignment: .topTrailing
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? pitchColors[pitch] ?? .gray : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? pitchColors[pitch]?.opacity(0.4) ?? .gray : .clear, radius: 2)
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

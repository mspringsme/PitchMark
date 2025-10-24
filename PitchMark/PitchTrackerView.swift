//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

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
    @State private var isRecordingResult = false
    @State private var activeCalledPitchId: String? = nil
    @State private var actualLocationRecorded: String? = nil
    @State private var resultVisualState: String? = nil
    @State private var pendingResultLabel: String? = nil
    @State private var showResultConfirmation = false
    @State private var isGameMode: Double = 1
    @StateObject var sessionManager = PitchSessionManager()
    @State private var modeSliderValue: Double = 0 // 0 = practice, 1 = game
    @State private var pitchEvents: [PitchEvent] = []
    @State private var showPitchResults = false
    @State private var filterMode: PitchMode? = nil
    @State private var showTemplateStatsSheet = false
    @State private var menuSelectedStatsTemplate: PitchTemplate?
    @State private var showConfirmSheet = false
    @State private var isStrikeSwinging = false
    @State private var isWildPitch = false
    @State private var isPassedBall = false
    
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
                            ForEach(pitchOrder, id: \.self) { pitch in
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
                    
                    let iconSize: CGFloat = 36

                    HStack {
                        // Left Batter Button (Leading)
                        Button(action: {
                            withAnimation {
                                batterSide = .left
                            }
                        }) {
                            Image("rightBatterIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: iconSize, height: iconSize)
                                .foregroundColor(batterSide == .left ? .primary : .gray.opacity(0.4))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.clear)
                        .cornerRadius(6)
                        .buttonStyle(.plain)

                        Spacer()

                        VStack(spacing: 4) {
                            Text("Mode")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Mode", selection: $sessionManager.currentMode) {
                                Text("Practice").tag(PitchMode.practice)
                                Text("Game").tag(PitchMode.game)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: sessionManager.currentMode) { oldValue, newValue in
                                sessionManager.switchMode(to: newValue)
                            }
                        }
                        .frame(width: 160)

                        Spacer()

                        // Right Batter Button (Trailing)
                        Button(action: {
                            withAnimation {
                                batterSide = .right
                            }
                        }) {
                            Image("leftBatterIcon")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: iconSize, height: iconSize)
                                .foregroundColor(batterSide == .right ? .primary : .gray.opacity(0.4))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.clear)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    
                    VStack {
                        //                        if let selectedTemplate = selectedTemplate {
                        //                            Text("")
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
                            pitchCodeAssignments: pitchCodeAssignments,
                            isRecordingResult: isRecordingResult,
                            setIsRecordingResult: { isRecordingResult = $0 },
                            setActualLocation: { actualLocationRecorded = $0 },
                            actualLocationRecorded: actualLocationRecorded,
                            setSelectedPitch: { selectedPitch = $0 },
                            resultVisualState: resultVisualState,
                            setResultVisualState: { resultVisualState = $0 },
                            pendingResultLabel: $pendingResultLabel,
                            showResultConfirmation: $showResultConfirmation,
                            showConfirmSheet: $showConfirmSheet
                        )
                        //
                    }
                    .frame(height: geo.size.height * 0.7) // ✅ Prevents overlap
                    .clipped()
                    .padding(.top, 8)
                    
                    // "Choose a Pitch Result" pop up text
                    let shouldShowChooseResultText = isRecordingResult && pendingResultLabel == nil
                    if shouldShowChooseResultText {
                        Text("Choose a Pitch Result")
                            .opacity(shouldShowChooseResultText ? 1 : 0)
                            .scaleEffect(shouldShowChooseResultText ? 1.05 : 1)
                            .shadow(color: .yellow.opacity(shouldShowChooseResultText ? 0.3 : 0), radius: 4)
                            .animation(.easeInOut(duration: 0.3), value: shouldShowChooseResultText)
                            //.position(x: geo.size.width / 2, y: geo.size.height * 0.78)
                    }
                        
                    
                }
                .frame(maxHeight: .infinity, alignment: .top)
                
                ResetPitchButton(geo: geo) {
                    isRecordingResult = false
                    
                    // ✅ Reset pitch and location selection
                    selectedPitch = ""
                    selectedLocation = ""
                    
                    // ✅ Reset tapped position and called pitch display
                    lastTappedPosition = nil
                    calledPitch = nil
                    
                    // ✅ Clear visual override state
                    resultVisualState = nil
                    actualLocationRecorded = nil
                    
                    pendingResultLabel = nil
                }
                
                ShowPitchLog(
                    geo: geo,
                    showLog: {
                        authManager.loadPitchEvents { events in
                            pitchEvents = events
                            showPitchResults = true
                            print("🔥 ", pitchEvents)
                        }
                    }
                )
                
                let sortedTemplates: [PitchTemplate] = {
                    guard let activeID = selectedTemplate?.id else {
                        return templates.sorted { $0.name < $1.name }
                    }
                    let others = templates.filter { $0.id != activeID }.sorted { $0.name < $1.name }
                    if let active = templates.first(where: { $0.id == activeID }) {
                        return [active] + others
                    }
                    return others
                }()
                ShowPitchLogTemplates(
                    geo: geo,
                    sortedTemplates: sortedTemplates,
                    onSelectTemplate: { template in
                        menuSelectedStatsTemplate = template
                        showTemplateStatsSheet = true
                    }
                )
                
                
                // 📝 Called Pitch Display
                Group {
                    if isRecordingResult && activeCalledPitchId == nil {
                         if let call = calledPitch {
                            CalledPitchView(
                                isRecordingResult: $isRecordingResult,
                                activeCalledPitchId: $activeCalledPitchId,
                                call: call,
                                pitchCodeAssignments: pitchCodeAssignments,
                                batterSide: batterSide
                            )
                            .frame(maxWidth: geo.size.width * 0.9)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.85)
                            .transition(.opacity)
                        }
                    } else if let call = calledPitch {
                        CalledPitchView(
                            isRecordingResult: $isRecordingResult,
                            activeCalledPitchId: $activeCalledPitchId,
                            call: call,
                            pitchCodeAssignments: pitchCodeAssignments,
                            batterSide: batterSide
                        )
                        .frame(maxWidth: geo.size.width * 0.9)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 4)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.85)
                        .transition(.opacity)
                    }
                }
                if selectedTemplate == nil {
                    Text("")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .frame(height: geo.size.height * 0.88, alignment: .top)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(20)
                        .padding(.top, 8)
                }
                
            } // end of z stack
            .sheet(isPresented: $showConfirmSheet) {
                VStack(spacing: 20) {
                    Text("Confirm Result")
                        .font(.title2)
                        .bold()

                    if let label = pendingResultLabel {
                        Text("Location: \(label)")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose any that apply:")
                            .font(.subheadline)
                        Toggle("Strike Swinging", isOn: $isStrikeSwinging)
                        Toggle("Wild Pitch", isOn: $isWildPitch)
                        Toggle("Passed Ball", isOn: $isPassedBall)
                    }
                    .padding(.horizontal)

                    Divider()

                    Button("Save Pitch Event") {
                        guard let label = pendingResultLabel,
                              let pitch = calledPitch?.pitch,
                              let codes = calledPitch?.codes else {
                            showConfirmSheet = false
                            return
                        }

                        let event = PitchEvent(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            pitch: pitch,
                            location: label,
                            codes: codes,
                            isStrike: label.starts(with: "Strike"),
                            mode: sessionManager.currentMode,
                            calledPitch: calledPitch,
                            batterSide: batterSide,
                            templateId: selectedTemplate?.id.uuidString,
                            strikeSwinging: isStrikeSwinging,
                            wildPitch: isWildPitch,
                            passedBall: isPassedBall
                        )

                        authManager.savePitchEvent(event)
                        sessionManager.incrementCount()
                        pitchEvents.append(event)

                        authManager.loadPitchEvents { events in
                            self.pitchEvents = events
                        }

                        // Reset state
                        resultVisualState = label
                        activeCalledPitchId = UUID().uuidString
                        isRecordingResult = false
                        selectedPitch = ""
                        selectedLocation = ""
                        lastTappedPosition = nil
                        calledPitch = nil
                        resultVisualState = nil
                        actualLocationRecorded = nil
                        pendingResultLabel = nil
                        isStrikeSwinging = false
                        isWildPitch = false
                        isPassedBall = false
                        showConfirmSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)

                    Button("Cancel", role: .cancel) {
                        showConfirmSheet = false
                    }
                    .padding(.bottom)
                }
                .padding()
                .presentationDetents([.medium])
            }
//            .confirmationDialog(
//                "Confirm result location: \(pendingResultLabel ?? "")?",
//                isPresented: $showResultConfirmation,
//                titleVisibility: .visible
//            ) {
//                Button("Confirm", role: .none) {
//                    if let label = pendingResultLabel {
//                        actualLocationRecorded = label
//                        
//                        if let pitch = calledPitch?.pitch,
//                           let codes = calledPitch?.codes {
//
//                            let event = PitchEvent(
//                                id: UUID().uuidString,
//                                timestamp: Date(),
//                                pitch: pitch,
//                                location: label, // ✅ use label directly
//                                codes: codes,
//                                isStrike: label.starts(with: "Strike"),
//                                mode: sessionManager.currentMode,
//                                calledPitch: calledPitch,
//                                batterSide: batterSide,
//                                templateId: selectedTemplate?.id.uuidString
//                            )
//                            
//                            authManager.savePitchEvent(event)
//                            sessionManager.incrementCount()
//                            
//                            // Optional: append locally for instant UI updates
//                            pitchEvents.append(event)
//
//                            // Optional: reload from Firestore if you want to sync latest
//                            // (but not necessary immediately after saving unless you're expecting external changes)
//                            authManager.loadPitchEvents { events in
//                                self.pitchEvents = events
//                            }
//                        }
//                        
//                        resultVisualState = label
//                        activeCalledPitchId = UUID().uuidString
//                        isRecordingResult = false
//                        // ✅ Reset pitch and location selection
//                        selectedPitch = ""
//                        selectedLocation = ""
//                        
//                        // ✅ Reset tapped position and called pitch display
//                        lastTappedPosition = nil
//                        calledPitch = nil
//                        
//                        // ✅ Clear visual override state
//                        resultVisualState = nil
//                        actualLocationRecorded = nil
//                        pendingResultLabel = nil
//                    }
//                    pendingResultLabel = nil
//                }
//            }
            
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

                authManager.loadPitchEvents { events in
                    self.pitchEvents = events
                    if !events.isEmpty {
                    }
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
        .sheet(isPresented: $showPitchResults) {
            if selectedTemplate != nil {
                PitchResultSheet(
                    allEvents: pitchEvents,
                    templates: templates,
                    filterMode: $filterMode
                )
                .environmentObject(authManager)
            } else {
                Text("No template selected.")
                    .font(.headline)
                    .padding()
            }
        }
        .sheet(item: $menuSelectedStatsTemplate) { template in
            TemplateSuccessSheet(template: template)
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
    calledPitch: PitchCall?,
    setSelectedPitch: @escaping (String) -> Void
) -> some View {
    if selectedPitches.isEmpty {
        Button("Select pitches first") {}.disabled(true)
    } else {
        ForEach(pitchOrder.filter { selectedPitches.contains($0) }, id: \.self) { pitch in
            let assignedCodes = pitchCodeAssignments
                .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                .map(\.code)
            
            let codeSuffix = assignedCodes.isEmpty
            ? "     --"
            : "   \(assignedCodes.joined(separator: ", "))"
            
            Button("\(pitch)\(codeSuffix)") {
                withAnimation {
                    setSelectedPitch(pitch) // ✅ This sets the selected pitch
                    
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

struct ShowPitchLog: View {
    let geo: GeometryProxy
    let showLog: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation {
                showLog()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "baseball")
                    .font(.body)
                    .foregroundColor(.green)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                
                Text("Cards")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .position(x: geo.size.width - 30, y: geo.size.height * 0.6)
        .accessibilityLabel("Show pitches.")
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
    }
}

struct CalledPitchView: View {
    @State private var showResultOverlay = false
    @State private var selectedActualLocation: String?
    @Binding var isRecordingResult: Bool
    @Binding var activeCalledPitchId: String?
    let call: PitchCall
    let pitchCodeAssignments: [PitchCodeAssignment]
    let batterSide: BatterSide
    
    var body: some View {
        let displayLocation = call.location.trimmingCharacters(in: .whitespaces)
        let assignedCodes = pitchCodeAssignments
            .filter {
                $0.pitch == call.pitch &&
                $0.location.trimmingCharacters(in: .whitespacesAndNewlines) == displayLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map(\.code)
        
        print("Looking for: \(call.pitch) @ \(displayLocation)")
        print("Available: \(pitchCodeAssignments.map { "\($0.pitch) @ \($0.location)" })")
        
        return HStack(alignment: .center) {
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
            
            Spacer()
            
            Button(action: {
                isRecordingResult = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                    Text("🥎")
                        .font(.title)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
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
                    .opacity(isSelected ? 1.0 : 0.2)
            )
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: isSelected ? pitchColors[pitch]?.opacity(0.4) ?? .gray : .clear, radius: 2)
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
            .onTapGesture {
                if isSelected {
                    selectedPitches.remove(pitch)
                } else {
                    selectedPitches.insert(pitch)
                }
            }
    }
}

//#Preview {
//    PitchTrackerView()
//}

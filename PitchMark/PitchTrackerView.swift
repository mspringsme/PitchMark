//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UniformTypeIdentifiers

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
    @State private var isStrikeLooking = false
    @State private var isWildPitch = false
    @State private var isPassedBall = false
    @State private var isCalledPitchViewVisible = false
    @State private var shouldBlurBackground = false
    @State private var isGame = false
    @State private var selectedOutcome: String? = nil
    @State private var selectedDescriptor: String? = nil
    @State private var isError: Bool = false
    @State private var showGameSheet = false
    @State private var opponentName: String? = nil
    @State private var selectedGameId: String? = nil
    @State private var jerseyCells: [JerseyCell] = sampleJerseyCells
    @State private var draggingJersey: JerseyCell?
    
    // MARK: - Preview-friendly initializer
    // Allows previews to seed internal @State with dummy data without affecting app code
    init(
        previewTemplate: PitchTemplate? = nil,
        previewTemplates: [PitchTemplate] = [],
        previewIsGame: Bool = false
    ) {
        if let t = previewTemplate {
            _selectedTemplate = State(initialValue: t)
            _selectedPitches = State(initialValue: Set(t.pitches))
            _pitchCodeAssignments = State(initialValue: t.codeAssignments)
        }
        _templates = State(initialValue: previewTemplates)
        _isGame = State(initialValue: previewIsGame)
    }
    
    private var batterAndModeBar: some View {
        HStack {
            Spacer()
            VStack {
                Picker("Mode", selection: $sessionManager.currentMode) {
                    Text("Practice").tag(PitchMode.practice)
                    Text("Game").tag(PitchMode.game)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)   // optional, makes it feel more compact
                .frame(width: 180)     // <- adjust this to taste
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: sessionManager.currentMode) { oldValue, newValue in
                    sessionManager.switchMode(to: newValue)
                    if newValue == .game {
                        showGameSheet = true
                    } else {
                        opponentName = nil
                        isGame = false
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // 🧩 Top Hstack
            HStack {
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
                    HStack(spacing: 8) {
                        Text(selectedTemplate?.name ?? "Select a template")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundColor(templates.isEmpty ? .gray : .primary)
                    .background(templates.isEmpty ? Color.gray.opacity(0.12) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(templates.isEmpty ? Color.gray.opacity(0.35) : Color.blue, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule()) // ensures the whole capsule is tappable
                }
                .disabled(templates.isEmpty)
                
                
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
            
            // everything below top bar:
            Group {
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
                
                batterAndModeBar
                
                
                let deviceWidth = UIScreen.main.bounds.width
                let SZwidth: CGFloat = isGame ? (deviceWidth * 0.78) : (deviceWidth * 0.85)
                VStack {
                    HStack(alignment: .top, spacing: 8) {
                        
                        // 🧩 Leading scrollable cells (only if game is active)
                        if isGame {
                            VStack(spacing: 0) {
                                // 🧢 Header
                                Text("At Bat")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.gray)
                                
                                // 🧩 Scrollable jersey cells
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 6) {
                                        // Existing jersey cells first
                                        ForEach(jerseyCells) { cell in
                                            JerseyCellView(cell: cell)
                                                .onDrag {
                                                    draggingJersey = cell
                                                    return NSItemProvider(object: NSString(string: cell.id.uuidString))
                                                }
                                                .onDrop(of: [UTType.text], delegate: JerseyDropDelegate(current: cell, items: $jerseyCells, dragging: $draggingJersey))
                                        }

                                        // Permanent plus cell at the bottom
                                        Button(action: {
                                            // TODO: Implement add jersey cell action
                                        }) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.white)
                                                    .frame(height: 44)
                                                Image(systemName: "plus")
                                                    .foregroundColor(.secondary)
                                                    .font(.headline)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 6)
                                    }
                                    .padding(.vertical, 2)        // Less vertical breathing room
                                    .padding(.horizontal, 0)      // No horizontal inset — flush to edges
                                }
                            }
                            .frame(width: 60, height: 400)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
                        }
                        
                        // 🧩 Strike Zone View
                        ZStack(alignment: .top) {
                            // Rounded container holding the StrikeZoneView and bottom overlays
                            VStack {
                                StrikeZoneView(
                                    width: SZwidth,
                                    isGame: $isGame,
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
                            }
                            .frame(width: SZwidth, height: 400)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
                            .overlay(
                                Group {
                                    ResetPitchButton() {
                                        isRecordingResult = false
                                        selectedPitch = ""
                                        selectedLocation = ""
                                        lastTappedPosition = nil
                                        calledPitch = nil
                                        resultVisualState = nil
                                        actualLocationRecorded = nil
                                        pendingResultLabel = nil
                                    }
                                },
                                alignment: .bottomLeading
                            )
                            .overlay(
                                Group {
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
                                        sortedTemplates: sortedTemplates,
                                        onSelectTemplate: { template in
                                            menuSelectedStatsTemplate = template
                                            showTemplateStatsSheet = true
                                        }
                                    )
                                },
                                alignment: .bottomTrailing
                            )
                            .overlay(
                                Group {
                                    if isGame {
                                        Button(action: {
                                            showGameSheet = true
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "gearshape")
                                                Text(opponentName ?? "Game")
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: 160)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                                        }
                                        .buttonStyle(.plain)
                                        .offset(y: 6)
                                    }
                                },
                                alignment: .bottom
                            )
                            
                            // Top batter icons as a sibling, not clipped by corner radius
                            HStack {
                                let iconSize: CGFloat = 36
                                Button(action: {
                                    withAnimation { batterSide = .left }
                                }) {
                                    Image("rightBatterIcon")
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: iconSize, height: iconSize)
                                        .foregroundColor(batterSide == .left ? .primary : .gray.opacity(0.4))
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: {
                                    withAnimation { batterSide = .right }
                                }) {
                                    Image("leftBatterIcon")
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: iconSize, height: iconSize)
                                        .foregroundColor(batterSide == .right ? .primary : .gray.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: SZwidth)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .offset(y: -20)
                        }
                        .frame(width: SZwidth, height: 400)
                    }
                }
                .padding(.horizontal, 12)
                
                // 🧩 conditional "Choose a Pitch Result" pop up TEXT
                let shouldShowChooseResultText = isRecordingResult && pendingResultLabel == nil
                if shouldShowChooseResultText {
                    Text("Choose a Pitch Result")
                        .opacity(shouldShowChooseResultText ? 1 : 0)
                        .scaleEffect(shouldShowChooseResultText ? 1.05 : 1)
                        .shadow(color: .yellow.opacity(shouldShowChooseResultText ? 0.3 : 0), radius: 4)
                        .animation(.easeInOut(duration: 0.3), value: shouldShowChooseResultText)
                        .padding(.top, 4)
                    //.position(x: geo.size.width / 2, y: geo.size.height * 0.78)
                }
                
                ZStack {
                    // 🧩 Cards (PitchResultSheet)
                    VStack {
                        if selectedTemplate != nil {
                            PitchResultSheet(
                                allEvents: pitchEvents,
                                templates: templates,
                                filterMode: $filterMode
                            )
                            .environmentObject(authManager)
                        }
                    }
                    .blur(radius: shouldBlurBackground ? 6 : 0)
                    .animation(.easeInOut(duration: 0.2), value: shouldBlurBackground)
                    .transition(.opacity)

                    // 🧩 Called Pitch Display
                    Group {
                        if let call = calledPitch {
                            CalledPitchView(
                                isRecordingResult: $isRecordingResult,
                                activeCalledPitchId: $activeCalledPitchId,
                                call: call,
                                pitchCodeAssignments: pitchCodeAssignments,
                                batterSide: batterSide
                            )
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            .transition(.opacity)
                            .padding(.top, 4)
                            .onAppear {
                                shouldBlurBackground = true
                            }
                            .onDisappear {
                                shouldBlurBackground = false
                            }
                        }
                    }
                }
                
            }
            .opacity(selectedTemplate == nil ? 0.6 : 1.0)
            .blur(radius: selectedTemplate == nil ? 4 : 0)
            .allowsHitTesting(selectedTemplate != nil)
            .animation(.easeInOut(duration: 0.3), value: selectedTemplate)
            
        }
        .onReceive(NotificationCenter.default.publisher(for: .jerseyOrderChanged)) { output in
            guard let numbers = output.object as? [String], let gameId = selectedGameId else { return }
            authManager.updateGameLineup(gameId: gameId, jerseyNumbers: numbers)
        } // 🧩🧩🧩🧩 end of VStack 🧩🧩🧩🧩🧧🧩🧩🧩🧩🧩🧩🧩🧩🧩🧩🧩
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showConfirmSheet) {
            PitchResultSheetView(
                isPresented: $showConfirmSheet,
                isStrikeSwinging: $isStrikeSwinging,
                isStrikeLooking: $isStrikeLooking,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isError: $isError,
                pendingResultLabel: pendingResultLabel,
                pitchCall: calledPitch,
                batterSide: batterSide,
                selectedTemplateId: selectedTemplate?.id.uuidString,
                currentMode: sessionManager.currentMode,
                saveAction: { event in
                    authManager.savePitchEvent(event)
                    sessionManager.incrementCount()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitchEvents.append(event)
                    }
                    authManager.loadPitchEvents { events in
                        self.pitchEvents = events
                    }

                    // Reset state
                    resultVisualState = event.location
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
                    selectedOutcome = nil
                    selectedDescriptor = nil
                },
                template: selectedTemplate
            )
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
                    self.showPitchResults = true
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
        .sheet(item: $menuSelectedStatsTemplate) { template in
            TemplateSuccessSheet(template: template)
        }
        .sheet(isPresented: $showGameSheet, onDismiss: {
            // If user canceled without creating/choosing, optionally revert to practice
            if sessionManager.currentMode == .game && !isGame {
                sessionManager.switchMode(to: .practice)
            }
        }) {
            GameSelectionSheet(
                onCreate: { name, date in
                    let newGame = Game(id: nil, opponent: name, date: date, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                    authManager.saveGame(newGame)
                },
                onChoose: { gameId in
                    if gameId == "Practice" { // quick pick
                        opponentName = "Practice"
                        selectedGameId = nil
                        isGame = true
                        showGameSheet = false
                        return
                    }
                    authManager.loadGames { games in
                        if let game = games.first(where: { $0.id == gameId }) {
                            selectedGameId = game.id
                            opponentName = game.opponent
                            jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                        }
                        isGame = true
                        showGameSheet = false
                    }
                },
                onCancel: {
                    // User canceled: preserve any existing game state.
                    // If no game was active, onDismiss will revert to practice.
                    showGameSheet = false
                }
            )
            .presentationDetents([.fraction(0.5)])
            .presentationDragIndicator(.visible)
            .environmentObject(authManager)
        }
    }
}

private struct JerseyDropDelegate: DropDelegate {
    let current: JerseyCell
    @Binding var items: [JerseyCell]
    @Binding var dragging: JerseyCell?

    func dropEntered(info: DropInfo) {
        guard let dragging = dragging, dragging.id != current.id else { return }
        if let from = items.firstIndex(where: { $0.id == dragging.id }),
           let to = items.firstIndex(where: { $0.id == current.id }) {
            withAnimation {
                let item = items.remove(at: from)
                items.insert(item, at: to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        // Persist new order if possible
        // We need access to AuthManager and selectedGameId from the environment/scope.
        // Since DropDelegate is not a view, we post a notification with the new order.
        let order = items.map { $0.jerseyNumber }
        NotificationCenter.default.post(name: .jerseyOrderChanged, object: order)
        return true
    }
}

extension Notification.Name {
    static let jerseyOrderChanged = Notification.Name("jerseyOrderChanged")
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

struct ShowPitchLog: View {
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
        .accessibilityLabel("Show pitches.")
    }
}

struct ResetPitchButton: View {
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
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: 1)
                )
                .padding(.leading, 2)
                .offset(y: 6)
                
        }
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

struct GameSelectionSheet: View {
    var onCreate: (String, Date) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void

    @State private var games: [Game] = []
    @State private var showAddGamePopover: Bool = false
    @State private var newOpponentName: String = ""
    @State private var newGameDate: Date = Date()

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                // Permanent quick-pick: Practice Game
                Section {
                    Button(action: {
                        onChoose("Practice")
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "figure.run.circle")
                                .foregroundColor(.green)
                            Text("Practice Game")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                if games.isEmpty {
//                    Section {
//                        Text("No games yet. Tap + to add one.")
//                            .foregroundColor(.secondary)
//                    }
                } else {
                    Section() {
                        ForEach(games) { game in
                            Button(action: {
                                onChoose(game.id ?? "")
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(game.opponent)
                                            .font(.headline)
                                        Text(Self.formatter.string(from: game.date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddGamePopover = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add Game")
                }
            }
        }
        .overlay(
            Group {
                if showAddGamePopover {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showAddGamePopover = false }

                        AddGameCard(
                            opponentName: $newOpponentName,
                            gameDate: $newGameDate,
                            onCancel: { showAddGamePopover = false },
                            onSave: {
                                let name = newOpponentName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                let item = Game(opponent: name, date: newGameDate, jerseyNumbers: [])
                                games.append(item)
                                onCreate(name, newGameDate)
                                showAddGamePopover = false
                                // Keep the game selection sheet open; do not dismiss here.
                            }
                        )
                        .frame(maxWidth: 360)
                        .padding()
                    }
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.2), value: showAddGamePopover)
                }
            }
        )
        .onAppear {
            authManager.loadGames { loadedGames in
                self.games = loadedGames
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

struct GameItem: Identifiable {
    let id = UUID()
    var opponent: String
    var date: Date
}


struct AddGameCard: View {
    @Binding var opponentName: String
    @Binding var gameDate: Date
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Game")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Opponent name", text: $opponentName)
                .textFieldStyle(.roundedBorder)

            DatePicker("Date & Time", selection: $gameDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(opponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
    }
}


#Preview("PitchTracker Layout – Practice") {
    // Dummy pitch codes
    let dummyCodes: [PitchCodeAssignment] = [
        PitchCodeAssignment(code: "1", pitch: "FB", location: "Up Middle"),
        PitchCodeAssignment(code: "2", pitch: "FB", location: "Down Away"),
        PitchCodeAssignment(code: "7", pitch: "SL", location: "Down Middle")
    ]

    // Dummy template
    let template = PitchTemplate(
        id: UUID(),
        name: "Bullpen A",
        pitches: ["FB", "SL", "CH"],
        codeAssignments: dummyCodes
    )

    // Provide a couple of templates to populate the menu
    let templates = [
        template,
        PitchTemplate(id: UUID(), name: "Game Plan 1", pitches: ["FB", "CH"], codeAssignments: []),
        PitchTemplate(id: UUID(), name: "Mix – Offspeed", pitches: ["SL", "CH"], codeAssignments: [])
    ]

    // Build the view with preview-seeded state
    PitchTrackerView(
        previewTemplate: template,
        previewTemplates: templates,
        previewIsGame: false
    )
    .environmentObject(AuthManager())
}

#Preview("PitchTracker Layout – Game", traits: .landscapeLeft) {
    let dummyCodes: [PitchCodeAssignment] = [
        PitchCodeAssignment(code: "A", pitch: "FB", location: "Up In"),
        PitchCodeAssignment(code: "B", pitch: "FB", location: "Down Away"),
        PitchCodeAssignment(code: "C", pitch: "SL", location: "Down In")
    ]

    let template = PitchTemplate(
        id: UUID(),
        name: "Game Plan – RHB",
        pitches: ["FB", "SL", "CH"],
        codeAssignments: dummyCodes
    )

    let templates = [
        template,
        PitchTemplate(id: UUID(), name: "Alt Plan", pitches: ["FB", "SL"], codeAssignments: [])
    ]

    PitchTrackerView(
        previewTemplate: template,
        previewTemplates: templates,
        previewIsGame: true
    )
    .environmentObject(AuthManager())
    .preferredColorScheme(.dark)
}


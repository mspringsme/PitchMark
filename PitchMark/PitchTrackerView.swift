//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI

enum BatterSide: String, CaseIterable, Identifiable {
    case left, right
    
    var id: String { rawValue }
    
    var displayName: String {
        "\(self == .left ? "Left" : "Right")-Handed Batter"
    }
    
    var opposite: BatterSide {
        self == .left ? .right : .left
    }
}
struct PitchCall {
    let pitch: String
    let location: String
    let isStrike: Bool
    let codes: [String]  // ✅ Use array instead of single code

    var type: String {
        isStrike ? "Strike" : "Ball"
    }
}
struct PitchLocation {
    let label: String
    let isStrike: Bool
}

func allLocationsFromGrid() -> [String] {
    strikeGrid.map(\.label) + [
        "Up and Out", "Up", "Up and In",
        "Out", "In",
        "Down and Out", "Down", "Down and In"
    ]
}

func normalizedLocation(from label: String) -> String {
    if label.hasPrefix("Strike ") || label.hasPrefix("Ball ") {
        return label
    }

    let strikeLabels = strikeGrid.map(\.label)
    let prefix = strikeLabels.contains(label) ? "Strike" : "Ball"
    return "\(prefix) \(label)"
}
func normalizedLabel(_ label: String) -> String {
    switch label {
    case "Up and In", "Down and In", "In": return "Inside"
    case "Up and Out", "Down and Out", "Out": return "Outside"
    default: return label
    }
}
struct GridLocation: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let label: String
}
let strikeGrid: [GridLocation] = [
    .init(row: 0, col: 0, label: "Up and Out"),
    .init(row: 0, col: 1, label: "Up"),
    .init(row: 0, col: 2, label: "Up and In"),
    .init(row: 1, col: 0, label: "Out"),
    .init(row: 1, col: 1, label: "Middle"),
    .init(row: 1, col: 2, label: "In"),
    .init(row: 2, col: 0, label: "Down and Out"),
    .init(row: 2, col: 1, label: "Down"),
    .init(row: 2, col: 2, label: "Down and In")
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
}
struct PitchCodeAssignment: Hashable {
    let code: String
    let pitch: String
    let location: String
}
struct PitchTemplate: Identifiable, Hashable {
    let id: UUID
    var name: String
    var pitches: [String]
    var codeAssignments: [PitchCodeAssignment]
}
struct CodeAssignmentPanel: View {
    @Binding var selectedCodes: Set<String>
    @Binding var selectedPitch: String
    @Binding var selectedLocation: String
    @Binding var pitchCodeAssignments: [PitchCodeAssignment]
    
    let allPitches: [String]
    let allLocations: [String]
    let assignAction: () -> Void
    
    private var groupedCodes: [[String]] {
        stride(from: 1, through: 599, by: 100).map { start in
            let end = min(start + 99, 599)
            return (start...end).map { String(format: "%03d", $0) }
        }
    }

    private var assignedCodesForSelection: [String] {
        pitchCodeAssignments
            .filter { $0.pitch == selectedPitch && $0.location == selectedLocation }
            .map(\.code)
    }
    
    @ViewBuilder
    private func locationButton(label: String, isStrike: Bool) -> some View{
        let strikeLabels = strikeGrid.map(\.label)
        let fullLabel = "\(isStrike ? "Strike" : "Ball") \(label)"
        let isSelected = selectedLocation == fullLabel

        Button(action: {
            selectedLocation = fullLabel
        }) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
    }

    var body: some View {
        VStack(spacing: 12) {


            // 🔹 Assigned Codes for Current Pitch/Location
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assignedCodesForSelection, id: \.self) { code in
                        Text(code)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

            // 🔹 Dynamic Pitch + Location Label
            Text("\(selectedPitch) → \(selectedLocation)")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(allPitches, id: \.self) { pitch in
                        Button(action: { selectedPitch = pitch }) {
                            Text(pitch)
                                .padding(6)
                                .background(selectedPitch == pitch ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                // 🔹 Strike Locations
                Text("Strike Locations")
                    .font(.headline)
                    .padding(.leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(strikeGrid.map(\.label), id: \.self) { label in
                            locationButton(label: label, isStrike: true)
                        }
                    }
                    .padding(.horizontal)
                }

                // 🔹 Ball Locations
                Text("Ball Locations")
                    .font(.headline)
                    .padding(.leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([
                            "Up and Out", "Up", "Up and In",
                            "Out", "In",
                            "Down and Out", "Down", "Down and In"
                        ], id: \.self) { label in
                            locationButton(label: label, isStrike: false)
                        }
                    }
                    .padding(.horizontal)
                }
            }            // 🔹 Selected Codes Display
            Text("\(selectedCodes.sorted().joined(separator: ", "))")
                .font(.headline)
                .padding(.top, 4)

            // 🔹 Assign Button
            Button("Assign Codes") {
                for code in selectedCodes {
                    let assignment = PitchCodeAssignment(
                        code: code,
                        pitch: selectedPitch,
                        location: selectedLocation // already prefixed
                    )
                    if !pitchCodeAssignments.contains(assignment) {
                        pitchCodeAssignments.append(assignment)
                    }
                }
                selectedCodes.removeAll()
            }
            .disabled(selectedCodes.isEmpty || selectedPitch.isEmpty || selectedLocation.isEmpty)

            Divider()

            // 🔹 Embedded Scrollable Code Picker
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedCodes.indices, id: \.self) { groupIndex in
                        let codes = groupedCodes[groupIndex]
                        let rangeLabel = "\(codes.first!)–\(codes.last!)"

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Codes \(rangeLabel)")
                                .font(.headline)
                                .padding(.leading)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(codes, id: \.self) { code in
                                    let isGloballyAssigned = pitchCodeAssignments.contains { $0.code == code }
                                    let isSelected = selectedCodes.contains(code)

                                    Button(action: {
                                        if isGloballyAssigned { return }
                                        if isSelected {
                                            selectedCodes.remove(code)
                                        } else {
                                            selectedCodes.insert(code)
                                        }
                                    }) {
                                        Text(code)
                                            .font(.body)
                                            .frame(width: 60, height: 36)
                                            .background(isGloballyAssigned ? Color.clear : isSelected ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                                            .foregroundColor(isGloballyAssigned ? .red : .black)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(
                                                        isGloballyAssigned ? Color.red :
                                                        isSelected ? Color.green :
                                                        Color.blue,
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .disabled(isGloballyAssigned)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom)
            }
            
        }
        
    }
}
struct TemplateEditorView: View {
    @State private var name: String
    @State private var selectedPitches: Set<String>
    @State private var selectedPitch: String = ""
    @State private var selectedLocation: String = ""
    @State private var selectedCodes: Set<String> = []
    @State private var codeAssignments: [PitchCodeAssignment]
    
    let allPitches: [String]
    let templateID: UUID
    let onSave: (PitchTemplate) -> Void
    @Environment(\.dismiss) var dismiss
    
    init(template: PitchTemplate?, allPitches: [String], onSave: @escaping (PitchTemplate) -> Void) {
        self.allPitches = allPitches
        self.onSave = onSave
        
        // Use local vars to initialize @State
        let initialName = template?.name ?? ""
        let initialPitches = Set(template?.pitches ?? [])
        let initialAssignments = template?.codeAssignments ?? []
        let id = template?.id ?? UUID()
        
        _name = State(initialValue: initialName)
        _selectedPitches = State(initialValue: initialPitches)
        _codeAssignments = State(initialValue: initialAssignments)
        self.templateID = id
    }
    
    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            VStack(spacing: 16) {
                TextField("Template Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(allPitches, id: \.self) { pitch in
                            let isSelected = selectedPitches.contains(pitch)
                            Button(action: {
                                if isSelected {
                                    selectedPitches.remove(pitch)
                                } else {
                                    selectedPitches.insert(pitch)
                                }
                            }) {
                                Text(pitch)
                                    .padding(8)
                                    .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // 🔹 Code Assignment Panel
                CodeAssignmentPanel(
                    selectedCodes: $selectedCodes,
                    selectedPitch: $selectedPitch,
                    selectedLocation: $selectedLocation,
                    pitchCodeAssignments: $codeAssignments,
                    allPitches: Array(selectedPitches),
                    allLocations: allLocationsFromGrid(),
                    assignAction: {
                        for code in selectedCodes {
                            let assignment = PitchCodeAssignment(code: code, pitch: selectedPitch, location: selectedLocation)
                            if !codeAssignments.contains(assignment) {
                                codeAssignments.append(assignment)
                            }
                        }
                        selectedCodes.removeAll()
                    }
                )
                
                Spacer()
                
                Button("Save Template") {
                    // ✅ First, assign any pending codes
                    for code in selectedCodes {
                        let assignment = PitchCodeAssignment(code: code, pitch: selectedPitch, location: selectedLocation)
                        if !codeAssignments.contains(assignment) {
                            codeAssignments.append(assignment)
                        }
                    }
                    selectedCodes.removeAll()

                    // ✅ Then, save the full template
                    let newTemplate = PitchTemplate(
                        id: templateID,
                        name: name,
                        pitches: Array(selectedPitches),
                        codeAssignments: codeAssignments
                    )
                    onSave(newTemplate)
                    dismiss()
                }
                .disabled(name.isEmpty || selectedPitches.isEmpty)
            }
            .padding()
        }
    }
}

struct PitchTrackerView: View {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var showCodeAssignmentSheet = false
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
                .background(isSelected ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2))
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
                .onTapGesture {
                    if isSelected {
                        selectedPitches.remove(pitch)
                    } else {
                        selectedPitches.insert(pitch)
                    }
                }
        }
    }
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
    func rootViewController() -> UIViewController {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first ?? UIViewController()
    }
    @EnvironmentObject var authManager: AuthManager
        // SignInViewModel() will need: @Published var user: User? // Firebase user
    @State private var showProfileSheet = false
    @State private var showSignOutConfirmation = false
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplateEditor = false
    let availableTemplates: [String] = ["Ace Lefty", "Power Righty", "Slider Specialist"]
    
    
    let allPitches = ["2 Seam", "4 Seam", "Change", "Curve", "Screw", "Smile", "Drop", "Rise", "Pipe"]
    
    func pitchButton(
        x: CGFloat,
        y: CGFloat,
        location: PitchLocation,
        labelManager: PitchLabelManager,
        lastTappedPosition: CGPoint?,
        setLastTapped: @escaping (CGPoint?) -> Void,
        setCalledPitch: @escaping (PitchCall?) -> Void,
        buttonSize: CGFloat,
        selectedPitches: Set<String>,
        pitchCodeAssignments: [PitchCodeAssignment],
        calledPitch: PitchCall?
    ) -> some View {
        let isSelected = lastTappedPosition == CGPoint(x: x, y: y)
        let tappedPoint = CGPoint(x: x, y: y)
        let adjustedLabel = labelManager.adjustedLabel(from: location.label)
        return Menu {
            menuContent(
                for: adjustedLabel,
                tappedPoint: tappedPoint,
                location: location,
                setLastTapped: setLastTapped,
                setCalledPitch: setCalledPitch,
                selectedPitches: selectedPitches,
                pitchCodeAssignments: pitchCodeAssignments,
                lastTappedPosition: lastTappedPosition,
                calledPitch: calledPitch
            )
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
                    CalledPitchView(call: call, pitchCodeAssignments: pitchCodeAssignments)
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
private func menuContent(
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
            Button(pitch) {
                withAnimation {
                    let assignedCodes = pitchCodeAssignments
                        .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                        .map(\.code)

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
    
    var body: some View {
        let assignedCodes = pitchCodeAssignments
            .filter { $0.pitch == call.pitch && $0.location == call.location }
            .map(\.code)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Called Pitch:")
                Text(call.type)
                    .bold()
                    .foregroundColor(call.type == "Strike" ? .green : .red)
            }

            Text("\(call.pitch) (\(call.location))")
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

struct StrikeZoneView: View {
    let geo: GeometryProxy
    let batterSide: BatterSide
    let lastTappedPosition: CGPoint?
    let setLastTapped: (CGPoint?) -> Void
    let calledPitch: PitchCall?
    let setCalledPitch: (PitchCall?) -> Void
    let selectedPitches: Set<String>
    let gameIsActive: Bool
    let selectedPitch: String
    let pitchCodeAssignments: [PitchCodeAssignment]
    
    var body: some View {
        let zoneWidth = geo.size.width * 0.4
        let zoneHeight = geo.size.height * 0.35
        let cellWidth = zoneWidth / 3
        let cellHeight = zoneHeight / 3
        let buttonSize = min(cellWidth, cellHeight) * 0.8
        let originX = (geo.size.width - zoneWidth) / 2
        let originY: CGFloat = 0
        let labelManager = PitchLabelManager(batterSide: batterSide)
        
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.black, lineWidth: 2)
                .frame(width: zoneWidth, height: zoneHeight)
                .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)
            
            ForEach(strikeGrid) { loc in
                let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2
                
                pitchButton(
                    x: x,
                    y: y,
                    location: .init(label: loc.label, isStrike: true),
                    labelManager: labelManager,
                    lastTappedPosition: lastTappedPosition,
                    setLastTapped: setLastTapped,
                    setCalledPitch: setCalledPitch,
                    buttonSize: buttonSize,
                    selectedPitch: selectedPitch,
                    pitchCodeAssignments: pitchCodeAssignments,
                    gameIsActive: gameIsActive
                )
            }
            
            let ballLocations: [(String, CGFloat, CGFloat)] = [
                ("Up and Out", originX - buttonSize * 0.6, originY - buttonSize * 0.6),
                ("Up", originX + zoneWidth / 2, originY - buttonSize * 0.75),
                ("Up and In", originX + zoneWidth + buttonSize * 0.6, originY - buttonSize * 0.6),
                
                ("Out", originX - buttonSize * 0.75, originY + zoneHeight / 2),
                ("In", originX + zoneWidth + buttonSize * 0.75, originY + zoneHeight / 2),
                
                ("Down and Out", originX - buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6),
                ("Down", originX + zoneWidth / 2, originY + zoneHeight + buttonSize * 0.75),
                ("Down and In", originX + zoneWidth + buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6)
            ]
            ForEach(ballLocations, id: \.0) { label, x, y in
                pitchButton(
                    x: x,
                    y: y,
                    location: .init(label: label, isStrike: false),
                    labelManager: labelManager,
                    lastTappedPosition: lastTappedPosition,
                    setLastTapped: setLastTapped,
                    setCalledPitch: setCalledPitch,
                    buttonSize: buttonSize,
                    selectedPitch: selectedPitch,
                    pitchCodeAssignments: pitchCodeAssignments,
                    gameIsActive: gameIsActive
                )
            }
        }
        .frame(height: zoneHeight + buttonSize * 3)
    }
    private func pitchButton(
        x: CGFloat,
        y: CGFloat,
        location: PitchLocation,
        labelManager: PitchLabelManager,
        lastTappedPosition: CGPoint?,
        setLastTapped: @escaping (CGPoint?) -> Void,
        setCalledPitch: @escaping (PitchCall?) -> Void,
        buttonSize: CGFloat,
        selectedPitch: String,
        pitchCodeAssignments: [PitchCodeAssignment],
        gameIsActive: Bool
    ) -> some View {
        let tappedPoint = CGPoint(x: x, y: y)
        let prefix = location.isStrike ? "Strike" : "Ball"
        let normalized = normalizedLabel(location.label)
        let baseLabel = labelManager.adjustedLabel(from: normalized)
        let fullLabel = "\(prefix) \(baseLabel)"

        let assignedCode = pitchCodeAssignments.first {
            $0.pitch == selectedPitch && $0.location == fullLabel
        }

        let isDisabled = gameIsActive && assignedCode == nil
        let isSelected = lastTappedPosition == tappedPoint

        return Group {
            if isDisabled {
                disabledView(isStrike: location.isStrike)
                    .frame(width: buttonSize, height: buttonSize)
                    .position(x: x, y: y)
                    .zIndex(1)
            }

            Menu {
                if selectedPitches.isEmpty {
                    Button("Select pitches first") {}.disabled(true)
                } else {
                    ForEach(Array(selectedPitches), id: \.self) { pitch in
                        Button(pitch) {
                            withAnimation {
                                let assignedCodes = pitchCodeAssignments
                                    .filter { $0.pitch == pitch && $0.location == fullLabel }
                                    .map(\.code)

                                let newCall = PitchCall(
                                    pitch: pitch,
                                    location: fullLabel,
                                    isStrike: location.isStrike,
                                    codes: assignedCodes
                                )

                                let isSameCall = lastTappedPosition == tappedPoint &&
                                    calledPitch?.location == newCall.location &&
                                    calledPitch?.pitch == newCall.pitch

                                if isSameCall {
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
            } label: {
                ZStack {
                    shapeView(isStrike: location.isStrike, isSelected: isSelected)

                    Text(fullLabel)
                        .font(.system(size: buttonSize * 0.24, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .position(x: x, y: y)
            .zIndex(1)
        }
    }
    }
@ViewBuilder
private func shapeView(isStrike: Bool, isSelected: Bool) -> some View {
    Circle()
        .fill(isStrike ? Color.green.opacity(isSelected ? 0.6 : 1.0) : Color.red.opacity(isSelected ? 0.6 : 1.0))
        .overlay(Circle().stroke(Color.black, lineWidth: isSelected ? 3 : 0))
}
    @ViewBuilder
    private func disabledView(isStrike: Bool) -> some View {
        if isStrike {
            Circle().fill(Color.gray.opacity(0.3))
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
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



#Preview {
    PitchTrackerView()
}

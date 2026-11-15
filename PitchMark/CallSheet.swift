//
//  CallSheet.swift
//  PitchMark
//
//  Call Sheet, step 3 (2026-11-14): one full-screen place to call armband
//  signs from the coach's phone, with a Pitching tab (PitchKeyCaller.swift)
//  and a Batting & Fielding tab (SignGridCaller.swift), each with its own
//  key picker. Opened from Home (a key's or card's Call) and from the game
//  screen's Key menu (Open Call Sheet).
//
//  Every caller lives here, keyed by key/card id, so the latest call,
//  recent calls and code rotation survive switching tabs and keys while
//  the sheet is open. With a game open, the Pitching tab says the codes
//  aren't recorded - calling from the game screen is what records them.
//

import SwiftUI
import UIKit
import FirebaseAuth

enum CallSheetTab: Hashable {
    case pitching
    case batting
}

struct CallSheetView: View {
    let pitchKeys: [PitchTemplate]
    @ObservedObject var gridStore: SignGridStore
    /// A game is open in the tracker: pitch codes here aren't recorded.
    let gameOpen: Bool
    let onClose: () -> Void

    @State private var tab: CallSheetTab
    @State private var keyId: UUID?
    @State private var gridId: String?
    @State private var pitchCallers: [UUID: PitchKeyCaller] = [:]
    @State private var pitchCurrent: [UUID: PitchKeyCaller.Called] = [:]
    @State private var gridCallers: [String: SignGridCaller] = [:]
    @State private var gridCurrent: [String: SignGridCaller.Called] = [:]

    init(
        pitchKeys: [PitchTemplate],
        gridStore: SignGridStore,
        initialTab: CallSheetTab,
        initialKeyId: UUID? = nil,
        initialGridId: String? = nil,
        gameOpen: Bool,
        onClose: @escaping () -> Void
    ) {
        self.pitchKeys = pitchKeys
        self.gridStore = gridStore
        self.gameOpen = gameOpen
        self.onClose = onClose
        _tab = State(initialValue: initialTab)
        _keyId = State(initialValue: initialKeyId)
        _gridId = State(initialValue: initialGridId)
    }

    private var currentKey: PitchTemplate? {
        pitchKeys.first { $0.id == keyId } ?? pitchKeys.first
    }

    private var grids: [SignGrid] { gridStore.activeGrids }

    private var currentGrid: SignGrid? {
        grids.first { $0.id == gridId } ?? grids.first
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Signs", selection: $tab) {
                        Text("Pitching").tag(CallSheetTab.pitching)
                        Text("Batting & Fielding").tag(CallSheetTab.batting)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("callSheet.tab")

                    switch tab {
                    case .pitching: pitchingTab
                    case .batting: battingTab
                    }
                }
                .padding()
            }
            .navigationTitle("Call Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("callSheet.done")
                }
            }
        }
        // A dugout phone mustn't lock between calls.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Tabs

    @ViewBuilder
    private var pitchingTab: some View {
        if let key = currentKey {
            keyPicker(
                title: "Key",
                names: pitchKeys.map { ($0.id.uuidString, $0.name.isEmpty ? "Untitled key" : $0.name) },
                selected: key.id.uuidString
            ) { id in keyId = UUID(uuidString: id) }

            if gameOpen {
                Label("A game is open. These codes aren't recorded - call pitches from the game screen to record them.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("callSheet.gameOpenNote")
            }

            PitchKeyCallPanel(
                template: key,
                caller: Binding(
                    get: { pitchCallers[key.id] ?? PitchKeyCaller(template: key) },
                    set: { pitchCallers[key.id] = $0 }
                ),
                current: Binding(
                    get: { pitchCurrent[key.id] },
                    set: { pitchCurrent[key.id] = $0 }
                )
            )
            .id(key.id)
        } else {
            CallSheetEmptyMessage(
                systemImage: "key",
                title: "No pitching keys",
                detail: "Make one under Armband Keys on Home."
            )
        }
    }

    @ViewBuilder
    private var battingTab: some View {
        if let grid = currentGrid {
            keyPicker(
                title: "Card",
                names: grids.map { ($0.id, $0.name.isEmpty ? "Untitled card" : $0.name) },
                selected: grid.id
            ) { id in gridId = id }

            SignGridCallPanel(
                grid: grid,
                caller: Binding(
                    get: { gridCallers[grid.id] ?? SignGridCaller(card: SignGridCallingCard(grid: grid)) },
                    set: { gridCallers[grid.id] = $0 }
                ),
                current: Binding(
                    get: { gridCurrent[grid.id] },
                    set: { gridCurrent[grid.id] = $0 }
                )
            )
            .id(grid.id)
        } else {
            CallSheetEmptyMessage(
                systemImage: "rectangle.grid.3x2",
                title: "No Batting Bases & Fielding cards",
                detail: "Make one under Armband Keys on Home."
            )
        }
    }

    /// The name of what's on the armband, always at the top. A picker only
    /// when there's more than one - a mismatched key is the worst mistake
    /// this screen can make.
    @ViewBuilder
    private func keyPicker(
        title: String,
        names: [(id: String, name: String)],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let selectedName = names.first { $0.id == selected }?.name ?? ""
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if names.count > 1 {
                Picker(title, selection: Binding(get: { selected }, set: onSelect)) {
                    ForEach(names, id: \.id) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .accessibilityIdentifier("callSheet.picker.\(title)")
            } else {
                Text(selectedName)
                    .font(.subheadline.weight(.bold))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Presenting

/// The Call Sheet with its own card store - for callers that don't already
/// hold one (Home's Pitching keys, the game screen).
struct CallSheetHost: View {
    let pitchKeys: [PitchTemplate]
    let initialTab: CallSheetTab
    var initialKeyId: UUID? = nil
    let gameOpen: Bool
    let onClose: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var store = SignGridStore()

    var body: some View {
        CallSheetView(
            pitchKeys: pitchKeys,
            gridStore: store,
            initialTab: initialTab,
            initialKeyId: initialKeyId,
            gameOpen: gameOpen,
            onClose: onClose
        )
        .task(id: authManager.user?.uid) {
            store.start(uid: authManager.user?.uid)
        }
    }
}

/// The game screen's Open Call Sheet. A modifier struct so the tracker's
/// body gains one small frame, not the sheet's - see the stack notes on
/// PitchTrackerView in CLAUDE.md.
struct CallSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let pitchKeys: [PitchTemplate]
    let keyId: UUID?

    @EnvironmentObject private var authManager: AuthManager

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            CallSheetHost(
                pitchKeys: pitchKeys,
                // In a game, pitches are called on the game screen; the
                // sheet is for the other signs.
                initialTab: .batting,
                initialKeyId: keyId,
                gameOpen: true
            ) {
                isPresented = false
            }
            .environmentObject(authManager)
            .fixedAppDynamicType()
        }
    }
}

// MARK: - Shared parts

/// Black with white type whatever the theme - readable in sun. Tapping it
/// gives the same call's next code.
struct CallDisplayBox: View {
    let title: String?
    let code: String?
    let hint: String?
    let placeholder: String
    let codeIdentifier: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let code {
                    if let title {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Text(code)
                        .font(.system(size: 110, weight: .heavy, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .accessibilityIdentifier(codeIdentifier)
                    if let hint {
                        Text(hint)
                            .font(.caption.weight(.semibold))
                            .opacity(0.7)
                    }
                } else {
                    Text(placeholder)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 40)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 190)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black))
        }
        .buttonStyle(.plain)
        .disabled(code == nil)
    }
}

/// Show/Hide the armband or key as it prints.
struct CallSheetToggleButton: View {
    @Binding var isOn: Bool
    let onTitle: String
    let offTitle: String
    let identifier: String

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.toggle() }
        } label: {
            Label(isOn ? onTitle : offTitle, systemImage: isOn ? "eye.slash" : "rectangle.grid.3x2")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.primary)
        .accessibilityIdentifier(identifier)
    }
}

/// The last few calls, newest first.
struct CallRecentStrip: View {
    struct Item: Identifiable {
        let id: UUID
        let text: String
    }

    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            Text(item.text)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                }
            }
        }
    }
}

struct CallSheetEmptyMessage: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

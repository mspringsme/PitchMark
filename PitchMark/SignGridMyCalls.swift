import Foundation
import Combine
import FirebaseFirestore

/// The coach's own Quick Fill calls (2026-11-10), added from the cell box's
/// Add to Quick Fill. Kept on the account, so every device has them, at
/// `users/{uid}/meta/signGridQuickFill` (the meta rule: owner only).
struct SignGridMyCalls: Equatable {
    private(set) var labels: [String] = []

    /// What a typed call is saved as: trimmed, and no longer than a cell
    /// allows.
    static func cleaned(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SignGrid.maxCellLength))
    }

    /// True when Add to Quick Fill has nothing to do: blank, or already in
    /// Quick Fill (the built-in list or My Calls), ignoring case.
    func contains(_ text: String) -> Bool {
        let label = Self.cleaned(text)
        guard !label.isEmpty else { return true }
        let known = labels + SignGridQuickFill.sections.flatMap { $0.items.map(\.label) }
        return known.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    /// Adds a typed call. False when there was nothing to add.
    @discardableResult
    mutating func add(_ text: String) -> Bool {
        guard !contains(text) else { return false }
        labels.append(Self.cleaned(text))
        return true
    }

    mutating func remove(_ label: String) {
        labels.removeAll { $0 == label }
    }

    var firestoreData: [String: Any] {
        ["items": labels.map { ["label": $0] }]
    }

    init() {}

    init(firestoreData data: [String: Any]) {
        for entry in data["items"] as? [[String: Any]] ?? [] {
            if let label = entry["label"] as? String { add(label) }
        }
    }
}

/// My Calls for the signed-in coach.
final class SignGridMyCallsStore: ObservableObject {
    @Published private(set) var calls = SignGridMyCalls()

    private let inMemory: Bool
    private var uid: String? = nil
    private var listener: ListenerRegistration? = nil

    /// `inMemory` keeps everything local (UI tests).
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    deinit {
        listener?.remove()
    }

    func start(uid: String?) {
        guard !inMemory, uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        calls = SignGridMyCalls()
        guard let uid, !uid.isEmpty else { return }
        listener = document(uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    debugLog("❌ signGridQuickFill listener:", error.localizedDescription)
                    return
                }
                self.calls = SignGridMyCalls(firestoreData: snapshot?.data() ?? [:])
            }
        }
    }

    func add(_ text: String) {
        guard calls.add(text) else { return }
        save()
    }

    func remove(_ label: String) {
        calls.remove(label)
        save()
    }

    private func save() {
        guard !inMemory, let uid else { return }
        document(uid).setData(calls.firestoreData) { error in
            if let error { debugLog("❌ signGridQuickFill save:", error.localizedDescription) }
        }
    }

    private func document(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid).collection("meta").document("signGridQuickFill")
    }
}

extension SignGrid {
    /// Every empty call cell on every grid - never the numbered top row
    /// or first column.
    var emptyCallCells: [(grid: Int, row: Int, column: Int)] {
        var cells: [(Int, Int, Int)] = []
        for grid in 0..<gridCount {
            for row in 1..<max(rows, 1) {
                for column in 1..<max(columns, 1)
                where text(row: row, column: column, in: grid).trimmingCharacters(in: .whitespaces).isEmpty {
                    cells.append((grid, row, column))
                }
            }
        }
        return cells
    }

    /// Randomize (2026-11-10): fills the empty call cells with the picked
    /// calls, spread evenly (each one within one use of the others), in
    /// random cells. Typed cells are kept (user's call). Returns how many
    /// cells it filled.
    @discardableResult
    mutating func randomFill<R: RandomNumberGenerator>(with labels: [String], using generator: inout R) -> Int {
        var picks = Array(Set(labels.map(SignGridMyCalls.cleaned).filter { !$0.isEmpty })).sorted()
        let cells = emptyCallCells.shuffled(using: &generator)
        guard !picks.isEmpty else { return 0 }
        picks.shuffle(using: &generator)
        for (index, cell) in cells.enumerated() {
            setText(picks[index % picks.count], row: cell.row, column: cell.column, in: cell.grid)
        }
        return cells.count
    }

    @discardableResult
    mutating func randomFill(with labels: [String]) -> Int {
        var generator = SystemRandomNumberGenerator()
        return randomFill(with: labels, using: &generator)
    }
}

//
//  Pitch%.swift
//  PitchMark
//
//  Created by Mark Springer on 10/19/25.
//
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine

enum FilterType {
    case location
    case ballStrike
}
enum Duration: String, CaseIterable, Identifiable {
    case one = "1 Day", seven = "7 Days", fifteen = "15 Days"
    case thirty = "30 Days", fortyFive = "45 Days", ninety = "90 Days"

    var id: String { self.rawValue }
    var days: Int {
        switch self {
        case .one: return 1
        case .seven: return 7
        case .fifteen: return 15
        case .thirty: return 30
        case .fortyFive: return 45
        case .ninety: return 90
        }
    }
}



struct TemplateSuccessSheet: View {
    let template: PitchTemplate
    @StateObject private var vm = TemplateSuccessViewModel()
    @State private var selectedDuration: Duration = .seven
    @State private var sortPitch: String? = nil
    @State private var sortAscending: Bool = false
    @State private var selectedFilter: FilterType = .location

    private var batterSide: BatterSide {
        .right // or derive from template
    }

    private var rowLabels: [String] {
        BatterLabelSet(side: batterSide).strikeFull + BatterLabelSet(side: batterSide).ballFull
    }

    private func sortedRowLabels() -> [String] {
        guard let pitch = sortPitch else { return rowLabels }
        return rowLabels.sorted {
            let lhs = vm.stats[$0]?[pitch]?.percentage ?? -1
            let rhs = vm.stats[$1]?[pitch]?.percentage ?? -1
            return sortAscending ? lhs < rhs : lhs > rhs
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(templateName: template.name, selectedFilter: $selectedFilter)
            DurationPicker(selectedDuration: $selectedDuration)
            Divider()

            if selectedFilter == .location {
                LocationGrid(
                    rowLabels: sortedRowLabels(),
                    pitches: template.pitches,
                    stats: vm.stats,
                    sortPitch: sortPitch,
                    sortAscending: sortAscending,
                    onSort: { pitch in
                        if sortPitch == pitch {
                            sortAscending.toggle()
                        } else {
                            sortPitch = pitch
                            sortAscending = false
                        }
                    }
                )
            } else {
                BallStrikeSummaryGrid(events: vm.events)
            }
        }
        .onAppear {
            vm.load(templateId: template.id.uuidString, duration: selectedDuration, batterSide: batterSide, assignedPitches: template.pitches)
        }
        .onChange(of: selectedDuration) {
            vm.load(templateId: template.id.uuidString, duration: selectedDuration, batterSide: batterSide, assignedPitches: template.pitches)
        }
        .presentationDetents([.fraction(0.5)])
    }
}
struct SheetHeader: View {
    let templateName: String
    @Binding var selectedFilter: FilterType

    var body: some View {
        HStack {
            Text(templateName)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Filter", selection: $selectedFilter) {
                Text("Location").tag(FilterType.location)
                Text("Ball / Strike").tag(FilterType.ballStrike)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.top, 12)
        .padding(.horizontal)
    }
}
struct DurationPicker: View {
    @Binding var selectedDuration: Duration

    var body: some View {
        Picker("Duration", selection: $selectedDuration) {
            ForEach(Duration.allCases) { duration in
                Text(duration.rawValue).tag(duration)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
struct LocationGrid: View {
    let rowLabels: [String]
    let pitches: [String]
    let stats: [String: [String: CellStats]]
    let sortPitch: String?
    let sortAscending: Bool
    let onSort: (String) -> Void

    let columnWidth: CGFloat = 80

    var body: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                VStack(spacing: 12) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("").frame(width: columnWidth)
                        ForEach(pitches, id: \.self) { pitch in
                            Button(action: { onSort(pitch) }) {
                                HStack(spacing: 4) {
                                    Text(pitch).font(.caption)
                                    if sortPitch == pitch {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.caption2)
                                    }
                                }
                                .frame(width: columnWidth)
                                .background(pitchColors[pitch]?.opacity(0.2) ?? Color.gray.opacity(0.2))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Grid rows
                    ForEach(rowLabels, id: \.self) { row in
                        HStack(spacing: 0) {
                            Text(row)
                                .font(.caption)
                                .frame(width: columnWidth)
                                .padding(4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)

                            ForEach(pitches, id: \.self) { pitch in
                                let cell = stats[row]?[pitch]
                                let display = cell?.total == 0 ? "—" : String(format: "%.0f%%", cell?.percentage ?? 0)

                                Text(display)
                                    .font(.caption2)
                                    .frame(width: columnWidth, height: 30)
                                    .background(
                                        Group {
                                            if sortPitch == pitch {
                                                Color.yellow.opacity(0.3)
                                            } else {
                                                pitchColors[pitch]?.opacity(0.1) ?? Color.blue.opacity(0.1)
                                            }
                                        }
                                    )
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(sortPitch == pitch ? Color.yellow.opacity(0.6) : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
struct BallStrikeSummaryGrid: View {
    let events: [PitchEvent]

    var body: some View {
        let summaries = summarize(events: events)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(summaries, id: \.pitchType) { summary in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.pitchType)
                            .font(.headline)

                        HStack {
                            Text("Called Strike")
                            Spacer()
                            Text("\(summary.strikeSuccessRate)% success (\(summary.strikeSuccesses)/\(summary.calledStrikes))")
                                .foregroundColor(summary.strikeSuccessRate >= 70 ? .green : .red)
                        }

                        HStack {
                            Text("Called Ball")
                            Spacer()
                            Text("\(summary.ballSuccessRate)% success (\(summary.ballSuccesses)/\(summary.calledBalls))")
                                .foregroundColor(summary.ballSuccessRate >= 70 ? .green : .red)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }
}

// Added ShowPitchLogTemplates struct with requested modifications
struct ShowPitchLogTemplates: View {
    let sortedTemplates: [PitchTemplate]
    let onSelectTemplate: (PitchTemplate) -> Void
    
    var body: some View {
        Menu {
            ForEach(sortedTemplates, id: \.self) { template in
                Button(template.name) {
                    onSelectTemplate(template)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "baseball")
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("%")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 70, height: 36)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
            .offset(y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show all templates.")
    }
}

let rowLabels = BatterLabelSet(side: .right).strikeFull + BatterLabelSet(side: .right).ballFull


struct CellStats {
    var success: Int = 0
    var total: Int = 0

    var percentage: Double? {
        total == 0 ? nil : Double(success) / Double(total) * 100
    }
}

func aggregatePitchEvents(
    events: [PitchEvent],
    rowLabels: [String],
    colLabels: [String]
) -> [String: [String: CellStats]] {
    var matrix: [String: [String: CellStats]] = [:]

    for row in rowLabels {
        matrix[row] = [:]
        for col in colLabels {
            matrix[row]?[col] = CellStats()
        }
    }

    for event in events {
        let expected = event.calledPitch?.location ?? event.location
        let actual = event.location
        let pitch = event.pitch

        guard rowLabels.contains(expected),
              colLabels.contains(pitch) else { continue }

        var cell = matrix[expected]?[pitch] ?? CellStats()
        cell.total += 1
        if actual == expected {
            cell.success += 1
        }
        matrix[expected]?[pitch] = cell
    }

    return matrix
}

final class TemplateSuccessViewModel: ObservableObject {
    @Published var stats: [String: [String: CellStats]] = [:] // rowLabel → pitch → stats
    @Published var events: [PitchEvent] = [] // ✅ Add this
    func load(templateId: String, duration: Duration, batterSide: BatterSide, assignedPitches: [String]) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user")
            return
        }

        let since = Calendar.current.date(byAdding: .day, value: -duration.days, to: Date()) ?? Date()

        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("pitchEvents")
            .whereField("templateId", isEqualTo: templateId)
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: since))
            .getDocuments { snapshot, error in
                guard let docs = snapshot?.documents, error == nil else {
                    print("Firestore error:", error?.localizedDescription ?? "Unknown error")
                    return
                }

                let events: [PitchEvent] = docs.compactMap { try? $0.data(as: PitchEvent.self) }
                print("Fetched \(events.count) events")

                let rowLabels = BatterLabelSet(side: batterSide).strikeFull + BatterLabelSet(side: batterSide).ballFull
                let colLabels = assignedPitches

                let matrix = aggregatePitchEvents(events: events, rowLabels: rowLabels, colLabels: colLabels)

                DispatchQueue.main.async {
                    self.stats = matrix
                    self.events = events // ✅ Store raw events
                }
            }
    }
}

func isSuccessful(_ event: PitchEvent) -> Bool {
    guard let call = event.calledPitch else { return false }
    return call.isStrike == event.isStrike
}
func isLocationMatch(_ event: PitchEvent) -> Bool {
    guard let call = event.calledPitch else { return false }
    return call.location == event.location
}
func isFullySuccessful(_ event: PitchEvent) -> Bool {
    guard let call = event.calledPitch else { return false }
    return call.location == event.location && call.isStrike == event.isStrike
}

struct PitchSummary {
    let pitchType: String
    let calledStrikes: Int
    let strikeSuccesses: Int
    let calledBalls: Int
    let ballSuccesses: Int

    var strikeSuccessRate: Int {
        calledStrikes == 0 ? 0 : Int(Double(strikeSuccesses) / Double(calledStrikes) * 100)
    }

    var ballSuccessRate: Int {
        calledBalls == 0 ? 0 : Int(Double(ballSuccesses) / Double(calledBalls) * 100)
    }
}

func summarize(events: [PitchEvent]) -> [PitchSummary] {
    let grouped = Dictionary(grouping: events.compactMap { event -> (String, PitchEvent)? in
        guard let call = event.calledPitch else { return nil }
        return (call.pitch, event)
    }, by: { $0.0 })

    return grouped.mapValues { events in
        let strikeCalls = events.map(\.1).filter { $0.calledPitch?.isStrike == true }
        let ballCalls = events.map(\.1).filter { $0.calledPitch?.isStrike == false }

        let strikeSuccesses = strikeCalls.filter { isSuccessful($0) }.count
        let ballSuccesses = ballCalls.filter { isSuccessful($0) }.count

        return PitchSummary(
            pitchType: events.first?.0 ?? "Unknown",
            calledStrikes: strikeCalls.count,
            strikeSuccesses: strikeSuccesses,
            calledBalls: ballCalls.count,
            ballSuccesses: ballSuccesses
        )
    }
    .values.sorted(by: { $0.pitchType < $1.pitchType })
}


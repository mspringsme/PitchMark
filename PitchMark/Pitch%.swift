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
    
    func sortedRowLabels() -> [String] {
        guard let pitch = sortPitch else { return rowLabels }
        return rowLabels.sorted {
            let lhs = vm.stats[$0]?[pitch]?.percentage ?? -1
            let rhs = vm.stats[$1]?[pitch]?.percentage ?? -1
            return sortAscending ? lhs < rhs : lhs > rhs
        }
    }
    
    var body: some View {
        let batterSide = BatterSide.right // or from template
        let rowLabels = BatterLabelSet(side: batterSide).strikeFull + BatterLabelSet(side: batterSide).ballFull
        
        let columnWidth: CGFloat = 80
        
        
        VStack(spacing: 16) {
            Text(template.name)
                .font(.title2)
                .bold()
                .padding(.top)
            
            Picker("Duration", selection: $selectedDuration) {
                ForEach(Duration.allCases) { duration in
                    Text(duration.rawValue).tag(duration)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Divider()
            
            ScrollView(.vertical) {
                ScrollView(.horizontal) {
                    VStack(spacing: 12) {
                        // Column headers
                        HStack(spacing: 0) {
                            Text("") // Empty corner
                                .frame(width: columnWidth)
                            ForEach(pitchOrder, id: \.self) { pitch in
                                Button(action: {
                                    if sortPitch == pitch {
                                        sortAscending.toggle()
                                    } else {
                                        sortPitch = pitch
                                        sortAscending = false
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(pitch)
                                            .font(.caption)
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
                        ForEach(sortedRowLabels(), id: \.self) { row in                            HStack(spacing: 0) {
                                Text(row)
                                    .font(.caption)
                                    .frame(width: columnWidth)
                                    .padding(4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                
                            ForEach(pitchOrder, id: \.self) { pitch in
                                let cell = vm.stats[row]?[pitch]
                                let display = cell?.total == 0 ? "—" : String(format: "%.0f%%", cell?.percentage ?? 0)

                                Text(display)
                                    .font(.caption2)
                                    .frame(width: columnWidth, height: 30)
                                    .background(
                                        Group {
                                            if sortPitch == pitch {
                                                Color.yellow.opacity(0.3) // Highlight for sorted column
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
        
        .onAppear {
            vm.load(templateId: template.id.uuidString , duration: selectedDuration, batterSide: batterSide)
        }
        .onChange(of: selectedDuration) {
            vm.load(templateId: template.id.uuidString, duration: selectedDuration, batterSide: batterSide)
        }
        .presentationDetents([.fraction(0.5)])
    }
}

struct ShowPitchLogTemplates: View {
    let geo: GeometryProxy
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
            VStack(spacing: 4) {
                Image(systemName: "baseball")
                    .font(.body)
                    .foregroundColor(.black)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                Text("All")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .position(x: geo.size.width - 30, y: geo.size.height * 0.40)
        .accessibilityLabel("Show all templates.")
    }
}

let rowLabels = BatterLabelSet(side: .right).strikeFull + BatterLabelSet(side: .right).ballFull
let colLabels = pitchOrder

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

    func load(templateId: String, duration: Duration, batterSide: BatterSide) {
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
                let colLabels = pitchOrder

                let matrix = aggregatePitchEvents(events: events, rowLabels: rowLabels, colLabels: colLabels)

                DispatchQueue.main.async {
                    self.stats = matrix
                }
            }
    }
}


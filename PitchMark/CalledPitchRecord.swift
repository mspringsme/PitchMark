//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//


import Foundation
import FirebaseFirestore
import SwiftUI

enum PitchResultColumn {
    static let labelWidth: CGFloat = 80
    static let cellWidth: CGFloat = 80
}

struct CalledPitchRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let pitch: String
    let calledLocation: String
    let actualLocation: String?
    let isCalledStrike: Bool
    let isActualStrike: Bool?
    let assignedCodes: [String]
    let batterSideRaw: String?
    let notes: String?
    let mode: String
}

struct PitchResultsView: View {
    @State private var showSheet = false
    let sampleEvents: [PitchEvent] = []
    var body: some View {
        VStack {
            Button("Show Pitch Results") {
                showSheet = true
            }
            .sheet(isPresented: $showSheet) {
                PitchResultSheet(allEvents: sampleEvents)
            }
        }
    }
}

struct PitchResultSheet: View {
    let allEvents: [PitchEvent]
    @State private var filterMode: PitchMode? = nil

    private var filteredEvents: [PitchEvent] {
        guard let mode = filterMode else { return allEvents }
        return allEvents.filter { $0.mode == mode }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modePicker
                Text("Pitch Count: \(filteredEvents.count)")
                    .font(.headline)
                    .padding(.horizontal)

                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                            PitchResultRow(event: event, index: index)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }
            .padding(.top)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    private var modePicker: some View {
        Picker("Filter", selection: $filterMode) {
            Text("All").tag(nil as PitchMode?)
            Text("Game").tag(PitchMode.game as PitchMode?)
            Text("Practice").tag(PitchMode.practice as PitchMode?)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

struct PitchResultHeaderCell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .frame(width: PitchResultColumn.cellWidth, alignment: .leading)
            .padding(4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(4)
            
    }
}

struct PitchResultRow: View {
    let event: PitchEvent
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PitchResultLabelCell(text: "Called", isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.calledPitch?.pitch ?? "-", isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.calledPitch?.type ?? "-", isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.calledPitch?.location ?? "-", isStriped: index.isMultiple(of: 2))
            }

            Divider().frame(height: 1).background(Color.black.opacity(0.1))

            HStack(spacing: 0) {
                PitchResultLabelCell(text: "Thrown", isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.pitch, isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.isStrike ? "Strike" : "Ball", color: event.isStrike ? .green : .red, isStriped: index.isMultiple(of: 2))
                PitchResultDataCell(text: event.location, isStriped: index.isMultiple(of: 2))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

struct PitchResultLabelCell: View {
    let text: String
    var isStriped: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2)
            .frame(width: PitchResultColumn.labelWidth, alignment: .leading)
            .padding(4)
            .background(isStriped ? Color.gray.opacity(0.05) : Color.clear)
            
    }
}

struct PitchResultDataCell: View {
    let text: String
    var color: Color? = nil
    var isStriped: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(color ?? .primary)
            .frame(width: PitchResultColumn.cellWidth, alignment: .leading)
            .padding(4)
            .background(isStriped ? Color.gray.opacity(0.05) : Color.clear)
            
    }
}

extension View {
    func pitchResultCells() -> some View {
        self.modifier(PitchResultCellStyle())
    }
}

struct PitchResultCellStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .frame(minWidth: 80, alignment: .leading) // ✅ left-align content
            .padding(4)
            
            .fixedSize(horizontal: true, vertical: false)
            .multilineTextAlignment(.leading) // ✅ for multi-line safety
    }
}

struct PitchEvent: Codable, Identifiable {
    @DocumentID var id: String? // Firestore will auto-assign this
    let timestamp: Date
    let pitch: String
    let location: String
    let codes: [String]
    let isStrike: Bool
    let mode: PitchMode
    let calledPitch: PitchCall?
}

enum PitchMode: String, Codable {
    case game, practice
}

struct PitchCall: Codable {
    let pitch: String
    let location: String
    let isStrike: Bool
    let codes: [String]  // ✅ Use array instead of single code

    var type: String {
        isStrike ? "Strike" : "Ball"
    }
}

extension PitchCall {
    var displayTitle: String { "\(type) \(location)" } // location will now already be "Up & In" style
    var shortLabel: String { "\(pitch) — \(displayTitle)" }
}



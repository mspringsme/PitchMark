//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//


import Foundation

import SwiftUI

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

    var body: some View {
        VStack {
            Button("Show Pitch Results") {
                showSheet = true
            }
            .sheet(isPresented: $showSheet) {
                PitchResultsSheet()
            }
        }
    }
}

struct PitchResultsSheet: View {
    // Placeholder empty array for now
    let pitchRecords: [CalledPitchRecord] = []

    var body: some View {
        NavigationView {
            List(pitchRecords) { record in
                VStack(alignment: .leading) {
                    Text(record.pitch)
                        .font(.headline)
                    Text("Called: \(record.calledLocation)")
                        .font(.subheadline)
                    if let actual = record.actualLocation {
                        Text("Actual: \(actual)")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Pitch Results")
        }
    }
}



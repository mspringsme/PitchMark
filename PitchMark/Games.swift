//
//  Games.swift
//  PitchMark
//
//  Created by Mark Springer on 11/1/25.
//
import SwiftUI
import FirebaseFirestore





struct JerseyCell: Identifiable {
    let id: UUID
    var jerseyNumber: String
    init(id: UUID = UUID(), jerseyNumber: String) {
        self.id = id
        self.jerseyNumber = jerseyNumber
    }
}

//hi    

struct JerseyCellView: View {
    let cell: JerseyCell

    var body: some View {
        Text(cell.jerseyNumber)
            .font(.headline)
            .frame(width: 40, height: 40) // Square shape
            .background(Color.clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

let sampleJerseyCells: [JerseyCell] = [
]

struct Game: Identifiable, Codable {
    @DocumentID var id: String?
    var opponent: String
    var date: Date
    var jerseyNumbers: [String]
    var batterIds: [String]? = nil
    var createdAt: Date = Date()
}


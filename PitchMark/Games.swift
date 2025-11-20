//
//  Games.swift
//  PitchMark
//
//  Created by Mark Springer on 11/1/25.
//
import SwiftUI
import FirebaseFirestore





struct JerseyCell: Identifiable {
    let id = UUID()
    let jerseyNumber: String
}

//hi    

struct JerseyCellView: View {
    let cell: JerseyCell

    var body: some View {
        Text(cell.jerseyNumber)
            .font(.headline)
            .frame(width: 40, height: 40) // Square shape
            .background(Color.white)
            .cornerRadius(6)
    }
}

let sampleJerseyCells: [JerseyCell] = [
]

struct Game: Identifiable, Codable {
    @DocumentID var id: String?
    var opponent: String
    var date: Date
    var jerseyNumbers: [String]
    var createdAt: Date = Date()
}


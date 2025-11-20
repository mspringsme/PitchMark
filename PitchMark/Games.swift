//
//  Games.swift
//  PitchMark
//
//  Created by Mark Springer on 11/1/25.
//
import SwiftUI






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
    JerseyCell(jerseyNumber: "1"),
    JerseyCell(jerseyNumber: "2"),
    JerseyCell(jerseyNumber: "3")
]

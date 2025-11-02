//
//  BatterCell.swift
//  PitchMark
//
//  Created by Mark Springer on 11/1/25.
//
import SwiftUI

struct JerseyCell: Identifiable {
    let id = UUID()
    let jerseyNumber: String
}

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

let jerseyCells: [JerseyCell] = [
    JerseyCell(jerseyNumber: "12"),
    JerseyCell(jerseyNumber: "7"),
    JerseyCell(jerseyNumber: "34"),
    JerseyCell(jerseyNumber: "22"),
    JerseyCell(jerseyNumber: "9"),
    JerseyCell(jerseyNumber: "13"),
    JerseyCell(jerseyNumber: "2"),
    JerseyCell(jerseyNumber: "38"),
    JerseyCell(jerseyNumber: "24"),
    JerseyCell(jerseyNumber: "1"),
    JerseyCell(jerseyNumber: "20"),
    JerseyCell(jerseyNumber: "3")
]

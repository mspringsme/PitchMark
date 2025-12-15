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
    
    var balls: Int
    var strikes: Int
    var hits: Int
    var walks: Int
    var inning: Int
    var us: Int
    var them: Int

    init(
        id: String? = nil,
        opponent: String,
        date: Date,
        jerseyNumbers: [String],
        batterIds: [String]? = nil,
        createdAt: Date = Date(),
        balls: Int = 0,
        strikes: Int = 0,
        hits: Int = 0,
        walks: Int = 0,
        inning: Int = 1,
        us: Int = 0,
        them: Int = 0
    ) {
        self.id = id
        self.opponent = opponent
        self.date = date
        self.jerseyNumbers = jerseyNumbers
        self.batterIds = batterIds
        self.createdAt = createdAt
        self.balls = balls
        self.strikes = strikes
        self.hits = hits
        self.walks = walks
        self.inning = inning
        self.us = us
        self.them = them
    }
}


//
//  PitchSessionManager.swift
//  PitchMark
//
//  Created by Mark Springer on 10/14/25.
//
import SwiftUI
import Combine

class PitchSessionManager: ObservableObject {
    @Published var pitchCount: Int = 0
    @Published var currentMode: PitchMode = .game

    init() {
    }

    func switchMode(to newMode: PitchMode) {
        currentMode = .game
        pitchCount = 0
    }

    func incrementCount() {
        pitchCount += 1
    }

    func decrementCount() {
        pitchCount = max(0, pitchCount - 1)
    }
}

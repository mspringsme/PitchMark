//
//  PitchSessionManager.swift
//  PitchMark
//
//  Created by Mark Springer on 10/14/25.
//
import SwiftUI

class PitchSessionManager: ObservableObject {
    @Published var pitchCount: Int = 0
    @Published var currentMode: PitchMode = .practice

    func switchMode(to newMode: PitchMode) {
        currentMode = newMode
        pitchCount = 0
    }

    func incrementCount() {
        pitchCount += 1
    }
}

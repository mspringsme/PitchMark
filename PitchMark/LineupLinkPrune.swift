//
//  LineupLinkPrune.swift
//  PitchMark
//
//  Keeps the lineup's roster links (`hitterIdByJerseyCellId`) in step
//  with the cells on screen without losing a link to a passing glitch.
//
//  During a live session the owner's lineup is rebuilt from every room
//  snapshot, and a snapshot written before a just-added batter can land
//  after it - the batter vanishes for a moment and comes back. Pruning
//  that moment's missing cells deleted their links for good: the batter
//  returned as "Not on roster" while the same kid sat on the bench
//  (2026-11-02). A link whose cell disappears is parked instead, and put
//  back if the cell reappears.
//

import Foundation

enum LineupLinkPrune {
    struct Result: Equatable {
        var links: [UUID: String]
        var parked: [UUID: String]
    }

    static func apply(links: [UUID: String], parked: [UUID: String], cellIds: [UUID]) -> Result {
        let present = Set(cellIds)
        var links = links
        var parked = parked
        // A cell that came back gets its link back.
        for (id, hitterId) in parked where present.contains(id) && links[id] == nil {
            links[id] = hitterId
        }
        parked = parked.filter { !present.contains($0.key) }
        // A cell that's gone parks its link.
        for (id, hitterId) in links where !present.contains(id) {
            parked[id] = hitterId
        }
        links = links.filter { present.contains($0.key) }
        return Result(links: links, parked: parked)
    }
}

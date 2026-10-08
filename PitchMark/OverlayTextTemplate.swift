//
//  OverlayTextTemplate.swift
//  PitchMark
//
//  2026-10-01: the "3-4 templates with different fonts" the user asked
//  for alongside fillable text overlays (Overlay.swift's
//  `OverlayTextContent`). Each template is just a bold/regular font
//  PostScript name pair for the card's two lines - the layout itself
//  (bold line, divider, normal line), position/scale/rotation/timing/
//  fade, and the adjustable color are all shared across every template,
//  live on `OverlayItem`/`OverlayTextContent` directly.
//
//  Every font name below is one of Apple's own built-in iOS system
//  fonts (Helvetica Neue, Georgia, Futura, Noteworthy all ship on every
//  iOS device) - deliberately not a bundled custom font file, so there's
//  nothing to add to the app bundle or either Xcode target's membership
//  exceptions.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation

struct OverlayTextTemplate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let boldFontName: String
    let regularFontName: String
}

let overlayTextTemplates: [OverlayTextTemplate] = [
    OverlayTextTemplate(id: "modern", displayName: "Modern", boldFontName: "HelveticaNeue-Bold", regularFontName: "HelveticaNeue"),
    OverlayTextTemplate(id: "editorial", displayName: "Editorial", boldFontName: "Georgia-Bold", regularFontName: "Georgia"),
    OverlayTextTemplate(id: "bold", displayName: "Bold", boldFontName: "Futura-CondensedExtraBold", regularFontName: "Futura-Medium"),
    OverlayTextTemplate(id: "friendly", displayName: "Friendly", boldFontName: "Noteworthy-Bold", regularFontName: "Noteworthy-Light")
]

/// Looks up a template by id, falling back to the first template if the
/// id is unrecognized - keeps every call site total rather than needing
/// to thread an Optional through the editor/exporter for a case that
/// should only ever arise from corrupted data.
func overlayTextTemplate(id: String) -> OverlayTextTemplate {
    overlayTextTemplates.first(where: { $0.id == id }) ?? overlayTextTemplates[0]
}

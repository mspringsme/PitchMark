//
//  TeamDesignation.swift
//  PitchMark
//
//  The season/year/age/division stamp every Team carries (2026-10-21). A
//  team name on its own ("Reds") stopped being enough once the same kid's
//  stats were meant to span several seasons and several teams - two "Reds"
//  rosters a year apart are different teams, and the only thing that tells
//  them apart on a list is this designation.
//
//  Deliberately NOT in the "Pitchmark Display" target's
//  membershipExceptions: Display renders a called pitch and knows nothing
//  about teams, same reasoning as Team.swift itself.
//

import SwiftUI

// MARK: - Season

/// Raw values are the Firestore-stored strings; the cycle order below is
/// the product rule ("every season cycle begins in fall"), not alphabetical
/// and not `allCases` order by accident - `cycleIndex` is what makes a span
/// "consecutive" and what decides whether the span crosses a calendar year.
enum TeamSeason: String, Codable, CaseIterable, Identifiable, Hashable {
    case fall
    case winter
    case spring
    case summer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fall: return "Fall"
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        }
    }

    /// Position in the cycle that starts at fall. Winter/Spring/Summer all
    /// fall in the calendar year *after* the fall they follow.
    var cycleIndex: Int {
        switch self {
        case .fall: return 0
        case .winter: return 1
        case .spring: return 2
        case .summer: return 3
        }
    }

    static let cycleOrder: [TeamSeason] = [.fall, .winter, .spring, .summer]

    /// Position within a calendar year - what "newer" means when two teams
    /// share a year: Summer '26 is older than Fall '26.
    var calendarIndex: Int {
        switch self {
        case .winter: return 0
        case .spring: return 1
        case .summer: return 2
        case .fall: return 3
        }
    }
}

/// A start season plus an end season at or after it in the cycle. Every
/// valid span is one of the 10 `allSpans` entries - there is no way to
/// build a non-consecutive or out-of-order one through this type.
struct TeamSeasonSpan: Hashable, Identifiable {
    let start: TeamSeason
    let end: TeamSeason

    var id: String { "\(start.rawValue)-\(end.rawValue)" }

    var isSingleSeason: Bool { start == end }

    /// Endpoint form ("Fall", "Fall–Winter", "Fall–Summer") rather than
    /// spelling out every season in between: spans are consecutive by
    /// construction and the cycle order is fixed, so the two endpoints
    /// already name the span unambiguously and stay short enough to sit
    /// right-justified on a team row.
    var displayName: String {
        isSingleSeason ? start.displayName : "\(start.displayName)–\(end.displayName)"
    }

    var seasons: [TeamSeason] {
        TeamSeason.cycleOrder.filter { $0.cycleIndex >= start.cycleIndex && $0.cycleIndex <= end.cycleIndex }
    }

    /// Only a span that actually starts in fall and runs past it rolls into
    /// the next calendar year - Winter→Spring→Summer all sit inside one.
    var crossesCalendarYear: Bool {
        start == .fall && end != .fall
    }

    static let allSpans: [TeamSeasonSpan] = {
        var spans: [TeamSeasonSpan] = []
        for start in TeamSeason.cycleOrder {
            for end in TeamSeason.cycleOrder where end.cycleIndex >= start.cycleIndex {
                spans.append(TeamSeasonSpan(start: start, end: end))
            }
        }
        return spans
    }()
}

// MARK: - Age group

enum TeamAgeGroup: String, Codable, CaseIterable, Identifiable, Hashable {
    case u8 = "8U"
    case u9 = "9U"
    case u10 = "10U"
    case u11 = "11U"
    case u12 = "12U"
    case u13 = "13U"
    case u14 = "14U"
    case u15 = "15U"
    case u16 = "16U"
    case u17 = "17U"
    case u18 = "18U"
    case highSchool = "HS"

    var id: String { rawValue }

    /// What the picker shows. The compact `rawValue` is what a row shows.
    var displayName: String {
        self == .highSchool ? "High School" : rawValue
    }
}

// MARK: - Division

enum TeamDivision: String, Codable, CaseIterable, Identifiable, Hashable {
    case a = "A"
    case b = "B"
    case c = "C"
    case open = "Open"

    var id: String { rawValue }

    var displayName: String {
        self == .open ? "Open" : "Division \(rawValue)"
    }
}

// MARK: - Designation

/// The complete, validated stamp. A `Team` stores the five parts as
/// individual optional fields (so pre-designation documents still decode -
/// see Team.swift) and rebuilds this only when all five are present.
struct TeamDesignation: Codable, Equatable, Hashable {
    var seasonStart: TeamSeason
    var seasonEnd: TeamSeason
    /// The calendar year the span *starts* in. The end year is derived, not
    /// stored, so the pair can never disagree with the span.
    var startYear: Int
    var ageGroup: TeamAgeGroup
    var division: TeamDivision

    var span: TeamSeasonSpan {
        TeamSeasonSpan(start: seasonStart, end: seasonEnd)
    }

    var endYear: Int {
        span.crossesCalendarYear ? startYear + 1 : startYear
    }

    /// "Fall–Winter" / "Spring"
    var seasonText: String { span.displayName }

    /// "'25–'26" / "'26"
    var yearText: String {
        let start = Self.twoDigit(startYear)
        guard endYear != startYear else { return "'\(start)" }
        return "'\(start)–'\(Self.twoDigit(endYear))"
    }

    /// "Fall 2025 – Winter 2026" / "Spring 2026" - the long form the
    /// creation form echoes back so the year pair is obvious before saving.
    var longFormText: String {
        guard endYear != startYear else {
            return "\(seasonStart.displayName) \(startYear)"
        }
        return "\(seasonStart.displayName) \(startYear) – \(seasonEnd.displayName) \(endYear)"
    }

    /// One line, for places with horizontal room: "Fall–Winter '25–'26 · 16U · A"
    var inlineText: String {
        "\(seasonText) \(yearText) · \(ageGroup.rawValue) · \(division.rawValue)"
    }

    /// Stacked right-justified form, matching the team/player rows:
    /// ["Fall–Winter", "'25–'26", "16U · A"]
    var stackedLines: [String] {
        [seasonText, yearText, "\(ageGroup.rawValue) · \(division.rawValue)"]
    }

    private static func twoDigit(_ year: Int) -> String {
        String(format: "%02d", abs(year) % 100)
    }
}

// MARK: - Form state

/// The partially-filled form behind every create/edit-team screen. All four
/// choices are mandatory, which is exactly `designation` returning nil until
/// every one of them is made - callers disable Save on that.
struct TeamDesignationDraft: Equatable {
    var span: TeamSeasonSpan? = nil
    var startYear: Int? = nil
    var ageGroup: TeamAgeGroup? = nil
    var division: TeamDivision? = nil

    init() {}

    init(_ designation: TeamDesignation?) {
        guard let designation else { return }
        span = designation.span
        startYear = designation.startYear
        ageGroup = designation.ageGroup
        division = designation.division
    }

    var designation: TeamDesignation? {
        guard let span, let startYear, let ageGroup, let division else { return nil }
        return TeamDesignation(
            seasonStart: span.start,
            seasonEnd: span.end,
            startYear: startYear,
            ageGroup: ageGroup,
            division: division
        )
    }

    var isComplete: Bool { designation != nil }

    mutating func reset() {
        self = TeamDesignationDraft()
    }

    /// Years offered by the picker: a couple back for a season already
    /// underway, a couple forward for next year's roster being set up early.
    static var selectableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 3)...(current + 2))
    }
}

// MARK: - Picker UI

/// The four mandatory pickers, shared by every create/edit-team path -
/// Home's Teams section, the tracker's Set My Team / Set Opponent Team
/// sheets, and TeamRosterView's edit sheet - so "mandatory" means the same
/// thing wherever a team is born.
///
/// Menus rather than segmented pickers: twelve age groups and ten spans
/// don't fit a segmented row, and these are short enough never to scroll
/// (the `Menu`-loses-scroll-position problem in CLAUDE.md only bites menus
/// long enough to scroll).
struct TeamDesignationForm: View {
    @Binding var draft: TeamDesignationDraft
    var showsTitle: Bool = true

    private var yearLabel: String {
        guard let startYear = draft.startYear else { return "Select" }
        guard let span = draft.span, span.crossesCalendarYear else { return "\(startYear)" }
        return "\(startYear) – \(startYear + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text("Designation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            pickerRow(title: "Season") {
                Menu {
                    ForEach(TeamSeasonSpan.allSpans) { span in
                        Button(span.displayName) { draft.span = span }
                    }
                } label: {
                    menuLabel(draft.span?.displayName)
                }
            }

            pickerRow(title: "Year") {
                Menu {
                    ForEach(TeamDesignationDraft.selectableYears, id: \.self) { year in
                        Button(yearOptionLabel(year)) { draft.startYear = year }
                    }
                } label: {
                    menuLabel(draft.startYear == nil ? nil : yearLabel)
                }
            }

            pickerRow(title: "Age") {
                Menu {
                    ForEach(TeamAgeGroup.allCases) { group in
                        Button(group.displayName) { draft.ageGroup = group }
                    }
                } label: {
                    menuLabel(draft.ageGroup?.displayName)
                }
            }

            pickerRow(title: "Division") {
                Menu {
                    ForEach(TeamDivision.allCases) { division in
                        Button(division.displayName) { draft.division = division }
                    }
                } label: {
                    menuLabel(draft.division?.displayName)
                }
            }

            if let designation = draft.designation {
                Text(designation.longFormText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All four are required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The year menu spells the pair out per-option, not just on the label -
    /// picking "2025" for a Fall–Winter team should make "2025 – 2026"
    /// obvious before the tap, not after it.
    private func yearOptionLabel(_ year: Int) -> String {
        guard let span = draft.span, span.crossesCalendarYear else { return "\(year)" }
        return "\(year) – \(year + 1)"
    }

    private func pickerRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func menuLabel(_ value: String?) -> some View {
        HStack(spacing: 4) {
            Text(value ?? "Select")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(value == nil ? Color(.systemGray6) : Color.pitchMarkActiveGray.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(value == nil ? Color(.systemGray4) : Color.pitchMarkActiveGray.opacity(0.45), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
    }
}

/// The right-justified stamp on a team or player row. Renders nothing at
/// all for a team created before designations existed, rather than leaving
/// a gap or a placeholder.
struct TeamDesignationBadge: View {
    let designation: TeamDesignation?
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        if let designation {
            VStack(alignment: alignment, spacing: 1) {
                ForEach(designation.stackedLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
    }
}

//
//  GamesCalendarView.swift
//  PitchMark
//
//  Home's Games list as a month calendar (2026-11-05): a dot on each day
//  with a game; tap the day for its games, tap a game to open it the same
//  way its row in the list does.
//

import SwiftUI

enum GameCalendar {
    /// The month's cells, Sunday-first per `calendar`: nil for the blanks
    /// before the 1st, then the start of each day.
    static func monthCells(for month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = days.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: first)
        }
        return Array(repeating: nil, count: blanks) + dates
    }

    /// Games keyed by the start of the day they were played.
    static func gamesByDay(_ games: [Game], calendar: Calendar) -> [Date: [Game]] {
        Dictionary(grouping: games) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.sorted { $0.date > $1.date } }
    }

    /// Opens on this month when it has a game; otherwise on the latest
    /// month that does, so the calendar never opens empty while games exist.
    static func initialMonth(games: [Game], today: Date, calendar: Calendar) -> Date {
        let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let hasGameThisMonth = games.contains { calendar.isDate($0.date, equalTo: today, toGranularity: .month) }
        guard !hasGameThisMonth, let latest = games.map(\.date).filter({ $0 <= today }).max() ?? games.map(\.date).min()
        else { return thisMonth }
        return calendar.dateInterval(of: .month, for: latest)?.start ?? thisMonth
    }
}

struct GamesCalendarView: View {
    let games: [Game]
    let title: (Game) -> String
    let onOpen: (Game) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var month: Date
    @State private var selectedDay: Date? = nil

    private let calendar = Calendar.current

    init(games: [Game], title: @escaping (Game) -> String, onOpen: @escaping (Game) -> Void) {
        self.games = games
        self.title = title
        self.onOpen = onOpen
        _month = State(initialValue: GameCalendar.initialMonth(games: games, today: Date(), calendar: .current))
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    var body: some View {
        let byDay = GameCalendar.gamesByDay(games, calendar: calendar)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(Array(GameCalendar.monthCells(for: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day, count: byDay[day]?.count ?? 0)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    dayGames(byDay)
                }
                .padding()
            }
            .navigationTitle("Games Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(Self.monthFormatter.string(from: month))
                .font(.title3.weight(.bold))
                .accessibilityIdentifier("calendar.month")
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(.primary)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        let ordered = Array(symbols[start...] + symbols[..<start])
        return HStack(spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date, count: Int) -> some View {
        let isSelected = selectedDay == day
        let isToday = calendar.isDateInToday(day)
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(count > 0 || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (count > 0 ? Color.primary : Color.secondary))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.white : Color.green) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground).opacity(count > 0 ? 1 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday ? Color.secondary : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.dayFormatter.string(from: day))
        .accessibilityValue(count == 0 ? "no games" : (count == 1 ? "1 game" : "\(count) games"))
    }

    @ViewBuilder
    private func dayGames(_ byDay: [Date: [Game]]) -> some View {
        if let selectedDay {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.dayFormatter.string(from: selectedDay))
                    .font(.headline)
                let dayGames = byDay[selectedDay] ?? []
                if dayGames.isEmpty {
                    Text("No games this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(dayGames.enumerated()), id: \.offset) { _, game in
                    Button {
                        dismiss()
                        onOpen(game)
                    } label: {
                        HStack {
                            Text(title(game))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if game.isArchived {
                                Image(systemName: "archivebox")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Archived")
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("Tap a day with a dot to see its games.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            month = next
            selectedDay = nil
        }
    }
}

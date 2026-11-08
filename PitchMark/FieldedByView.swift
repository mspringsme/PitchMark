//
//  FieldedByView.swift
//  PitchMark
//
//  The result sheet's "Fielded by" rows (2026-11-03): for each out on the
//  play, tap the fielders in the order they handled the ball (SS then 1B
//  for a 6-3); for an error, tap who made it. Optional - a pitch saves the
//  same with nothing tapped, it just credits nobody. Rules and storage are
//  in FieldingPlay.swift.
//
//  Compiled into the Display target too (the result sheet is), so it is
//  listed in that target's membershipExceptions.
//

import SwiftUI

struct FieldedByView: View {
    let slots: [FieldingPlay.OutSlot]
    /// Fielders per slot, keyed by `OutSlot.runner`, in tap order.
    @Binding var answers: [String: [String]]
    let showsErrors: Bool
    @Binding var errors: [String]
    var descriptor: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fielded by")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(slots, id: \.self) { slot in
                outRow(slot)
            }

            if showsErrors {
                errorRow
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func outRow(_ slot: FieldingPlay.OutSlot) -> some View {
        let sequence = answers[slot.runner] ?? []
        let notation = sequence.isEmpty
            ? "Tap in order"
            : FieldingPlay.notation(FieldingOut(runner: slot.runner, positions: sequence), descriptor: descriptor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slots.count > 1 ? "\(slot.label) out" : "Out")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(notation)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(sequence.isEmpty ? .secondary : .primary)
                    .accessibilityIdentifier("fielding.\(slot.runner).sequence")
                    .accessibilityValue(sequence.isEmpty ? "none" : notation)
                if !sequence.isEmpty {
                    Button("Clear") { answers[slot.runner] = nil }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("fielding.\(slot.runner).clear")
                }
            }
            chipRow { position in
                chip(position, isSelected: sequence.contains(position),
                     identifier: "fielding.\(slot.runner).\(position)") {
                    var updated = sequence
                    // A rundown can go back to a fielder, but not twice in a row.
                    guard updated.last != position else { return }
                    updated.append(position)
                    answers[slot.runner] = updated
                }
            }
        }
    }

    private var errorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Error by")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(FieldingPlay.summary(outs: nil, errors: errors, descriptor: nil) ?? "Tap who")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(errors.isEmpty ? .secondary : .primary)
            }
            chipRow { position in
                chip(position, isSelected: errors.contains(position),
                     identifier: "fielding.error.\(position)") {
                    if let index = errors.firstIndex(of: position) {
                        errors.remove(at: index)
                    } else {
                        errors.append(position)
                    }
                }
            }
        }
    }

    private func chipRow<Chip: View>(@ViewBuilder _ chip: @escaping (String) -> Chip) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FieldingPlay.positions, id: \.self) { position in
                    chip(position)
                }
            }
        }
    }

    private func chip(_ position: String, isSelected: Bool, identifier: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(position)
                    .font(.caption.weight(.bold))
                Text("\(FieldingPlay.number(position) ?? 0)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            .frame(minWidth: 34)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

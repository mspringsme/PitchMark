//
//  HomeAreaTabBar.swift
//  PitchMark
//
//  Phase 2, step 2 of the Coach/Parent/Family direction (2026-09-24). A
//  persistent bar for jumping between Home/Games/Moments/Family without
//  touching PitchTrackerView's root/boot logic - see the plan doc for why.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI

enum HomeArea: Identifiable {
    case games
    case home
    case moments
    case family

    var id: Self { self }

    var title: String {
        switch self {
        case .games: return "Games"
        case .home: return "Home"
        case .moments: return "Moments"
        case .family: return "Family"
        }
    }

    var systemImage: String {
        switch self {
        case .games: return "figure.baseball"
        case .home: return "house.fill"
        case .moments: return "video.fill"
        case .family: return "person.2.fill"
        }
    }
}

struct HomeAreaTabBar: View {
    let current: HomeArea
    let onSelect: (HomeArea) -> Void

    private let areas: [HomeArea] = [.home, .games, .moments, .family]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(areas) { area in
                Button {
                    onSelect(area)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: area.systemImage)
                            .font(.system(size: 18))
                        Text(area.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(area == current ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }
}

struct ComingSoonSheetView: View {
    let area: HomeArea
    let title: String
    let systemImage: String
    let message: String
    var onSwitchToArea: ((HomeArea) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeAreaTabBar(current: area) { selected in
                    onSwitchToArea?(selected)
                    dismiss()
                }
            }
        }
    }
}

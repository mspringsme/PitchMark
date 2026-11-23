//
//  SponsorSlot.swift
//  PitchMark
//
//  Team Sponsors (2026-11-19). A team sells a season sponsorship to a local
//  business itself - the way it already sells outfield banners - and the
//  coach buys the slot that shows it in PitchMark: "Sponsored by {name}".
//
//  The rules (founding vision, Section 13):
//  - Only the server makes a slot, after payment (stripeWebhook); the
//    coach who paid may fix its name, link and logo (firestore.rules,
//    TEAM SPONSOR SLOTS). The server twin is functions/src/sponsorSlot.ts -
//    keep the limits identical.
//  - A slot holds what's shown and nothing about players or families;
//    sponsors get no data back.
//  - It shows only on the allow-listed surfaces below, always labeled.
//    Clips, editors, the slideshow, the tracker and Display never show
//    one. Every badge goes through `SponsorBadge`, which checks
//    `SponsorPlacement` - and a unit test reads the source to make sure
//    no badge is placed on a protected surface.
//

import SwiftUI
import UIKit
import PhotosUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Product

enum SponsorSlotProduct {
    static let retailProductId = "team_sponsor_season"
    static let itemKind = "sponsorSlot"
    static let priceCents = 2500
    static let durationDays = 183

    static let nameMax = 60
    static let linkMax = 200
    /// Base64 characters - must fit the 120k-character checkout snapshot.
    static let logoMax = 100_000
    /// Longest side of the stored logo, in pixels.
    static let logoPixels: CGFloat = 400
}

// MARK: - Placement

/// Every place in the app a sponsor could be drawn. Only `allowed` ones
/// ever show a badge.
enum SponsorSurface: String, CaseIterable {
    // Allowed: where a family is planning or celebrating, never inside a memory.
    case teamRoster
    case tourneyPage
    case sharedTourneyPage
    case seasonBook

    // Protected: never commercial.
    case clipPlayback
    case momentEditor
    case homeSlideshow
    case tracker
    case display
}

enum SponsorPlacement {
    static let allowed: Set<SponsorSurface> = [.teamRoster, .tourneyPage, .sharedTourneyPage, .seasonBook]

    static func allows(_ surface: SponsorSurface) -> Bool {
        allowed.contains(surface)
    }

    /// Source files that are protected surfaces as a whole: no sponsor
    /// badge may appear in them at all (checked by a unit test).
    static let protectedSourceFiles: [String] = [
        "PitchTrackerView.swift",
        "HomeSlideshow.swift",
        "MomentDetailView.swift",
        "MomentEditorChrome.swift",
        "MomentPhotoEditor.swift",
        "MomentStillGrabber.swift",
        "MomentsLibraryView.swift"
    ]
}

// MARK: - Model

struct SponsorSlot: Identifiable, Equatable {
    var id: String
    var teamId: String
    var name: String
    var link: String
    /// Base64 JPEG/PNG, or empty.
    var logo: String
    var startsAt: Date
    var endsAt: Date
    var purchasedByUid: String

    func isActive(at now: Date = Date()) -> Bool {
        startsAt <= now && now < endsAt
    }

    var logoImage: UIImage? {
        guard !logo.isEmpty, let data = Data(base64Encoded: logo) else { return nil }
        return UIImage(data: data)
    }

    var linkURL: URL? {
        guard link.hasPrefix("https://") else { return nil }
        return URL(string: link)
    }

    /// The words every badge shows.
    static func label(for name: String) -> String { "Sponsored by \(name)" }

    init(id: String, teamId: String, name: String, link: String = "", logo: String = "",
         startsAt: Date, endsAt: Date, purchasedByUid: String) {
        self.id = id
        self.teamId = teamId
        self.name = name
        self.link = link
        self.logo = logo
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.purchasedByUid = purchasedByUid
    }

    init?(id: String, data: [String: Any]) {
        guard let teamId = data["teamId"] as? String,
              let name = data["name"] as? String,
              let startsAt = (data["startsAt"] as? Timestamp)?.dateValue(),
              let endsAt = (data["endsAt"] as? Timestamp)?.dateValue() else { return nil }
        self.init(id: id, teamId: teamId, name: name,
                  link: data["link"] as? String ?? "", logo: data["logo"] as? String ?? "",
                  startsAt: startsAt, endsAt: endsAt,
                  purchasedByUid: data["purchasedByUid"] as? String ?? "")
    }
}

/// What the coach sends with the checkout. The server checks it again
/// (validateSponsorSnapshot) and builds the slot from it after payment.
struct SponsorSnapshot: Encodable, Equatable {
    var teamId: String
    var name: String
    var link: String
    var logo: String

    var trimmed: SponsorSnapshot {
        SponsorSnapshot(teamId: teamId,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                        logo: logo)
    }

    /// Nil when it's ready to send; otherwise what to fix.
    var problem: String? {
        let value = trimmed
        if value.name.isEmpty || value.name.count > SponsorSlotProduct.nameMax {
            return "The sponsor's name is 1 to \(SponsorSlotProduct.nameMax) characters."
        }
        if !value.link.isEmpty {
            guard value.link.count <= SponsorSlotProduct.linkMax,
                  value.link.hasPrefix("https://"),
                  let url = URL(string: value.link), url.host?.isEmpty == false else {
                return "The link must be an https web address."
            }
        }
        if value.logo.count > SponsorSlotProduct.logoMax {
            return "The logo is too large."
        }
        return nil
    }

    var json: String { RetailCheckoutRequest.snapshotJson(trimmed) }

    /// A logo shrunk to `logoPixels` and compressed until it fits.
    static func encodeLogo(_ image: UIImage) -> String? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, SponsorSlotProduct.logoPixels / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in stride(from: 0.8, through: 0.2, by: -0.15) {
            if let data = resized.jpegData(compressionQuality: quality) {
                let base64 = data.base64EncodedString()
                if base64.count <= SponsorSlotProduct.logoMax { return base64 }
            }
        }
        return nil
    }
}

// MARK: - Badge

/// The only way a sponsor is drawn. Shows nothing on a protected surface
/// or for a slot that isn't running.
struct SponsorBadge: View {
    let slot: SponsorSlot
    let surface: SponsorSurface
    var now: Date = Date()

    static func isVisible(_ slot: SponsorSlot, on surface: SponsorSurface, now: Date = Date()) -> Bool {
        SponsorPlacement.allows(surface) && slot.isActive(at: now)
    }

    var body: some View {
        if Self.isVisible(slot, on: surface, now: now) {
            HStack(spacing: 10) {
                if let image = slot.logoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(SponsorSlot.label(for: slot.name))
                        .font(.subheadline.weight(.semibold))
                    if let url = slot.linkURL {
                        Link(url.host ?? slot.link, destination: url)
                            .font(.caption)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sponsor.badge")
        }
    }
}

// MARK: - Store

/// A team's slots, live. Readable by whoever can see the team.
@MainActor
final class TeamSponsorStore: ObservableObject {
    @Published private(set) var slots: [SponsorSlot] = []
    private var listener: ListenerRegistration? = nil
    private var teamId: String? = nil

    var activeSlots: [SponsorSlot] { slots.filter { $0.isActive() } }

    func start(teamId: String?) {
        guard teamId != self.teamId else { return }
        listener?.remove()
        listener = nil
        self.teamId = teamId
        slots = []
        guard let teamId, !teamId.isEmpty else { return }
        listener = Firestore.firestore().collection("teams").document(teamId).collection("sponsors")
            .addSnapshotListener { [weak self] snapshot, _ in
                let loaded = (snapshot?.documents ?? [])
                    .compactMap { SponsorSlot(id: $0.documentID, data: $0.data()) }
                    .sorted { $0.startsAt > $1.startsAt }
                Task { @MainActor in self?.slots = loaded }
            }
    }

    deinit { listener?.remove() }
}

// MARK: - Roster section

/// The team roster's sponsor section: the running sponsors for everyone who
/// can see the team, and Add a Sponsor for its coach. Its purchase sheet is
/// on the roster's root (`RosterExtrasSheets`) - see RosterExtrasPresentation
/// for why a sheet can't sit on a List section.
struct TeamSponsorSection: View {
    let team: Team
    let isTeamOwner: Bool
    let presentation: RosterExtrasPresentation
    @ObservedObject private var store: TeamSponsorStore

    init(team: Team, isTeamOwner: Bool, presentation: RosterExtrasPresentation) {
        self.team = team
        self.isTeamOwner = isTeamOwner
        self.presentation = presentation
        self._store = ObservedObject(wrappedValue: presentation.sponsorStore)
    }

    var body: some View {
        Section {
            ForEach(store.activeSlots) { slot in
                SponsorBadge(slot: slot, surface: .teamRoster)
            }
            if isTeamOwner {
                Button {
                    presentation.showSponsorPurchase = true
                } label: {
                    Label("Add a Team Sponsor", systemImage: "megaphone")
                }
                .accessibilityIdentifier("team.addSponsor")
            } else if store.activeSlots.isEmpty {
                Text("No sponsors this season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Team Sponsors")
        } footer: {
            if isTeamOwner {
                Text("Sell a season sponsorship to a local business the way you'd sell a banner, then show it here, on your tourney pages and in season books. Sponsors see nothing about your players or families.")
            }
        }
    }
}

// MARK: - Purchase

struct SponsorSlotPurchaseView: View {
    let team: Team
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var link = ""
    @State private var logo = ""
    @State private var logoItem: PhotosPickerItem? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var orderKey = "sponsor_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"

    private var snapshot: SponsorSnapshot {
        SponsorSnapshot(teamId: team.id ?? "", name: name, link: link, logo: logo)
    }

    var body: some View {
        Form {
            Section {
                TextField("Business name", text: $name)
                    .accessibilityIdentifier("sponsor.name")
                TextField("Website (optional, https://)", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                PhotosPicker(selection: $logoItem, matching: .images) {
                    Label(logo.isEmpty ? "Add Logo (optional)" : "Change Logo", systemImage: "photo")
                }
            } header: {
                Text("Sponsor for \(team.name)")
            }

            if !snapshot.trimmed.name.isEmpty {
                Section("Preview") {
                    SponsorBadge(
                        slot: SponsorSlot(id: "preview", teamId: snapshot.teamId, name: snapshot.trimmed.name,
                                          link: snapshot.trimmed.link, logo: logo,
                                          startsAt: Date.distantPast, endsAt: Date.distantFuture, purchasedByUid: ""),
                        surface: .teamRoster
                    )
                }
            }

            Section {
                Text("One season (\(SponsorSlotProduct.durationDays) days): \(Decimal(SponsorSlotProduct.priceCents) / 100, format: .currency(code: "USD"))")
                    .font(.subheadline.weight(.semibold))
                Text("Always labeled \"Sponsored by\". Shown on your roster, tourney pages and season books - never on clips, the slideshow or during a game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Team Sponsor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Buy") { buy() }
                    .disabled(isLoading || snapshot.problem != nil)
                    .accessibilityIdentifier("sponsor.buy")
            }
        }
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let encoded = SponsorSnapshot.encodeLogo(image) {
                    logo = encoded
                }
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        }
        .appConfirmationDialog(
            isPresented: $showError,
            title: "Couldn't start checkout",
            message: errorMessage ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
    }

    private func buy() {
        if let problem = snapshot.problem {
            errorMessage = problem
            showError = true
            return
        }
        isLoading = true
        let payload: [String: Any] = [
            "retailProductId": SponsorSlotProduct.retailProductId,
            "itemKind": SponsorSlotProduct.itemKind,
            "templateId": team.id ?? "",
            "templateName": snapshot.trimmed.name,
            "storeTemplateName": "Team Sponsor",
            "templateSnapshotJson": snapshot.json,
            "idempotencyKey": orderKey
        ]
        Task {
            do {
                let result = try await Functions.functions().httpsCallable("createRetailCheckoutSession").call(payload)
                isLoading = false
                guard let data = result.data as? [String: Any],
                      let urlString = data["checkoutUrl"] as? String,
                      let url = URL(string: urlString) else {
                    errorMessage = "Checkout link was not returned."
                    showError = true
                    return
                }
                openURL(url)
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

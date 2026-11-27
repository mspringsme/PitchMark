//
//  PlayAnimation.swift
//  PitchMark
//
//  The play animation in a follower's feed card (2026-11-25, user's picks:
//  drawn in code, plays once then back to the text, a button replays it;
//  only balls in play, runner moves, strikeouts and walks).
//
//  `PlayAnimationPlan` is the math - where the ball and each runner are at
//  any moment - kept apart from the drawing so it can be tested.
//  `PlayAnimationView` draws it over the result sheet's field picture
//  (FieldImage2). Positions are 0 to 1 across and down that picture, the
//  same space as the hit location and `BasesFieldLayer.normalizedPoint`.
//
//  PitchMark only - not in the Display target.
//

import SwiftUI

enum PlayBallType: String {
    case grounder, line, fly, pop, bunt, hr
}

struct PlayAnimationPlan: Equatable {
    struct Ball: Equatable {
        var type: PlayBallType
        var spot: CGPoint
        var duration: Double
    }

    struct Runner: Equatable {
        var from: Int
        var to: Int
        /// Corner to corner along the base paths.
        var waypoints: [CGPoint]
        var isOut: Bool { to == Base.out }
        var scored: Bool { to == Base.scored }
        var isBatter: Bool { from == Base.home }
    }

    var ball: Ball?
    var runners: [Runner]
    var strikeout: Bool
    var runnersStart: Double

    /// Seconds per base, the same for every runner - a runner going two
    /// bases takes twice as long as one going one, so nobody laps anybody
    /// (user, 2026-11-25: the batter raced round and caught the runner
    /// ahead when every runner got the same time whatever the distance).
    static let secondsPerBase = 0.75
    /// The time to get up to speed out of the base, and to slow into it.
    static let speedUpTime = 0.3
    static let hold = 0.5

    /// Runners go at the crack of the bat, alongside the ball (user,
    /// 2026-11-25), so the play lasts as long as the slower of the two.
    static let runnersDelay = 0.1

    var duration: Double {
        let ballEnd = ball?.duration ?? 0
        let runnersEnd = runners.map { runnersStart + Self.runTime($0) }.max() ?? 0
        return max(ballEnd, runnersEnd) + Self.hold + (strikeout ? 0.8 : 0)
    }

    // MARK: Building a plan

    /// The bag positions on the field picture (BasesFieldLayer's numbers).
    static func point(_ base: Int) -> CGPoint {
        switch base {
        case Base.first: return CGPoint(x: 0.6376, y: 0.5768)
        case Base.second: return CGPoint(x: 0.4983, y: 0.4773)
        case Base.third: return CGPoint(x: 0.3582, y: 0.5754)
        default: return CGPoint(x: 0.4984, y: 0.6753)
        }
    }

    static let home = point(Base.home)

    static func ballDuration(_ type: PlayBallType) -> Double {
        switch type {
        case .line: return 0.7
        case .grounder: return 0.85
        case .bunt: return 0.6
        case .fly: return 1.1
        case .pop: return 1.1
        case .hr: return 1.3
        }
    }

    /// The route along the base paths. Out = partway to the next base, where
    /// they were put out. Staying = no route.
    static func waypoints(from: Int, to: Int) -> [CGPoint] {
        let start = point(from)
        if to == Base.out {
            let next = point(min(from + 1, Base.scored))
            return [start, CGPoint(x: start.x + (next.x - start.x) * 0.55, y: start.y + (next.y - start.y) * 0.55)]
        }
        guard to > from else { return [start] }
        return [start] + ((from + 1)...to).map { point($0 == Base.scored ? Base.home : $0) }
    }

    /// Nil when the play isn't animated: balls, strikes and fouls stay text.
    static func make(for event: GameFeedEvent) -> PlayAnimationPlan? {
        guard ["hit", "out", "run", "walk", "strikeout", "hbp", "inPlay"].contains(event.kind) else { return nil }
        var ball: Ball? = nil
        if let x = event.spotX, let y = event.spotY, let type = event.ballType.flatMap(PlayBallType.init(rawValue:)) {
            ball = Ball(type: type, spot: CGPoint(x: x, y: y), duration: ballDuration(type))
        } else if let x = event.spotX, let y = event.spotY {
            // A ball in play with no type picked: a line drive.
            ball = Ball(type: .line, spot: CGPoint(x: x, y: y), duration: ballDuration(.line))
        }
        var moves = event.moves
        // A walk or hit batter saved without a play: the batter to 1st.
        if !moves.contains(where: { $0.from == Base.home }), event.kind == "walk" || event.kind == "hbp" {
            moves.append(FeedMove(from: Base.home, to: Base.first))
        }
        // Everyone on base is drawn; a runner who stayed has a one-point route.
        let runners = moves
            .map { Runner(from: $0.from, to: $0.to, waypoints: waypoints(from: $0.from, to: $0.to)) }
        let strikeout = event.kind == "strikeout"
        guard ball != nil || runners.contains(where: { $0.from != $0.to }) || strikeout else { return nil }
        return PlayAnimationPlan(ball: ball, runners: runners, strikeout: strikeout,
                                 runnersStart: runnersDelay)
    }

    // MARK: Where things are at time t

    /// The ball's spot on the ground and how high it is (in field heights),
    /// or nil before it's hit / when there's no ball.
    func ballState(at t: Double) -> (ground: CGPoint, lift: Double)? {
        guard let ball else { return nil }
        let p = min(1, max(0, t / ball.duration))
        let home = Self.home
        let eased: Double
        switch ball.type {
        case .grounder, .bunt: eased = 1 - pow(1 - p, 2)   // slows as it rolls
        // Fast off the bat, easing in at the very end (user, 2026-11-25).
        case .line: eased = 1 - pow(1 - p, 2.2)
        case .fly, .pop, .hr: eased = p
        }
        let ground = CGPoint(x: home.x + (ball.spot.x - home.x) * eased,
                             y: home.y + (ball.spot.y - home.y) * eased)
        let lift: Double
        switch ball.type {
        case .line: lift = sin(.pi * p) * 0.025
        case .fly: lift = sin(.pi * p) * 0.10
        case .hr: lift = sin(.pi * p) * 0.12
        case .pop: lift = sin(.pi * p) * 0.14
        // Three bounces, each lower (user, 2026-11-25).
        case .grounder: lift = abs(sin(.pi * 3 * p)) * 0.05 * (1 - 0.75 * p)
        case .bunt: lift = 0
        }
        return (ground, lift)
    }

    /// How far a route is, in bases (home to 1st = 1).
    static func bases(_ runner: Runner) -> Double {
        let baseLength = distance(point(Base.home), point(Base.first))
        var total = 0.0
        for i in 0..<max(0, runner.waypoints.count - 1) {
            total += distance(runner.waypoints[i], runner.waypoints[i + 1])
        }
        return total / baseLength
    }

    static func runTime(_ runner: Runner) -> Double { bases(runner) * secondsPerBase }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// How far along the route (0 to 1) after `t` seconds of a run that
    /// takes `total`: speeding up out of the base, a steady run, slowing
    /// into the base - the same top speed for every runner.
    static func runFraction(_ t: Double, total: Double) -> Double {
        guard total > 0 else { return 1 }
        let t = min(max(t, 0), total)
        let a = min(speedUpTime, total / 2)
        let vmax = 1 / (total - a)
        if t < a { return vmax * t * t / (2 * a) }
        if t <= total - a { return vmax * a / 2 + vmax * (t - a) }
        let r = total - t
        return 1 - vmax * r * r / (2 * a)
    }

    /// Where a runner is at time t: on their base until the runners go,
    /// then along their route at the common speed.
    func runnerPosition(_ runner: Runner, at t: Double) -> CGPoint {
        let points = runner.waypoints
        guard points.count > 1 else { return points.first ?? Self.home }
        // Distance along the route, walked segment by segment.
        let fraction = Self.runFraction(t - runnersStart, total: Self.runTime(runner))
        var remaining = fraction * Self.bases(runner) * Self.distance(Self.point(Base.home), Self.point(Base.first))
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let leg = Self.distance(a, b)
            if remaining <= leg || i == points.count - 2 {
                let f = leg > 0 ? min(1, remaining / leg) : 1
                return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            }
            remaining -= leg
        }
        return points.last ?? Self.home
    }

    func runnerDone(_ runner: Runner, at t: Double) -> Bool { t >= runnersStart + Self.runTime(runner) }
}

/// The animation, drawn over the field picture. Calls `onFinish` once when
/// it's done; with Reduce Motion it shows the last frame and finishes.
struct PlayAnimationView: View {
    let plan: PlayAnimationPlan
    /// A frozen moment, 0 to 1 of the animation (screenshots, UI tests).
    var frozenAt: Double? = nil
    var onFinish: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    /// The whole field - outfield wall to home plate - and a little room
    /// for a ball over the fence. Fitted, never cropped (user, 2026-11-25:
    /// the top of the outfield and home plate were cut off).
    private static let crop = CGRect(x: 0.04, y: 0.15, width: 0.92, height: 0.63)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Scale the picture so the whole crop fits, centered.
            let aspect = 842.0 / 596.0
            let imageW = min(size.width / Self.crop.width, size.height / (Self.crop.height * aspect))
            let imageH = imageW * aspect
            let originX = (size.width - Self.crop.width * imageW) / 2 - Self.crop.minX * imageW
            let originY = (size.height - Self.crop.height * imageH) / 2 - Self.crop.minY * imageH
            let place = { (p: CGPoint) -> CGPoint in
                CGPoint(x: originX + p.x * imageW, y: originY + p.y * imageH)
            }
            TimelineView(.animation(paused: finished)) { context in
                let t = frozenAt.map { $0 * plan.duration }
                    ?? (reduceMotion ? plan.duration : context.date.timeIntervalSince(start))
                ZStack(alignment: .topLeading) {
                    Image("FieldImage2")
                        .resizable()
                        .frame(width: imageW, height: imageH)
                        .offset(x: originX, y: originY)
                    ForEach(Array(plan.runners.enumerated()), id: \.offset) { _, runner in
                        runnerDot(runner, at: place(plan.runnerPosition(runner, at: t)), t: t)
                    }
                    if let ball = plan.ballState(at: t) {
                        let ground = place(ball.ground)
                        Ellipse()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 9, height: 4)
                            .position(ground)
                        let ballSize = 9 + ball.lift * 40
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1))
                            .frame(width: ballSize, height: ballSize)
                            // Kept inside the frame, however high it goes.
                            .position(x: ground.x, y: max(ballSize / 2 + 2, ground.y - ball.lift * imageH))
                    }
                    if plan.strikeout {
                        Text("K")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(Color.red)
                            .opacity(min(1, max(0, t / 0.4)))
                            .position(place(PlayAnimationPlan.home).applying(.init(translationX: 0, y: -28)))
                    }
                }
                .onChange(of: t >= plan.duration) { _, done in
                    if done && !finished && frozenAt == nil {
                        finished = true
                        onFinish()
                    }
                }
            }
        }
        .clipped()
        .accessibilityLabel("Play animation")
        .onAppear {
            start = Date()
            finished = false
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !finished { finished = true; onFinish() }
                }
            }
        }
    }

    @ViewBuilder
    private func runnerDot(_ runner: PlayAnimationPlan.Runner, at p: CGPoint, t: Double) -> some View {
        let done = plan.runnerDone(runner, at: t)
        ZStack {
            Circle()
                .fill(runner.isBatter ? Color.black.opacity(0.8) : Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .frame(width: 11, height: 11)
            if runner.isOut && done {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.red)
            }
            if runner.scored && done {
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
        }
        .position(p)
    }
}

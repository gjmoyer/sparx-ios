//
//  Helix.swift
//  Qix
//
//  The roaming Qix entity — faithful port of Sparx `helix.js`.
//
//  Geometry: one straight segment, two free endpoints.
//  Appearance: live line + delayed full-segment afterimages (rainbow ribbon).
//  Motion: independent endpoint wander / loiter / lunge (no midpoint pin).
//
//  The trail must NOT look "tied at the middle". That artifact comes from
//  forcing both ends to orbit a shared center. Classic Qix fans because the
//  whole segment translates and one end usually leads the other — history
//  shares a rough pivot near one end, not the midpoint.
//
//  Author: Greg Moyer (original JS); Swift port for Qix iOS.
//

import CoreGraphics
import Foundation

/// Simulation + AI for one Helix. Rendering is handled by `HelixNode`.
final class Helix {
    // MARK: - Constants (match JS)

    static let trailLength = 12
    static let sampleMs: CGFloat = 42
    static let wallPad: CGFloat = 18

    // MARK: - Size / bounds

    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    private(set) var minLen: CGFloat = 0
    private(set) var maxLen: CGFloat = 0
    private(set) var bounds: Bounds = Bounds(left: 0, top: 0, right: 1, bottom: 1)

    // MARK: - Endpoints

    let a: HelixEndpoint
    let b: HelixEndpoint

    // MARK: - Trail

    private(set) var trail: [HelixSegment] = []
    private var sampleAccum: CGFloat = 0

    // MARK: - AI state

    private(set) var mode: HelixMode = .wander
    private var modeTimer: CGFloat = 1.0
    private var lungeTarget: CGPoint?
    private var lungeBias: CGPoint?

    /// World position of the player (for lunge targeting). Updated by the scene.
    var playerPosition: CGPoint = .zero

    /// Which end currently leads (asymmetric motion = classic wedge fan).
    private var lead: HelixLead
    private var leadTimer: CGFloat

    /// Angular rate of the free end around the lagging pivot (rad/s).
    /// Rotation is around the FOLLOWER, not the midpoint — wedge fan, not bowtie.
    private var omega: CGFloat
    private var omegaTimer: CGFloat

    /// Target length the segment breathes toward (short ↔ long).
    private var lengthTarget: CGFloat = 0
    private var lengthTimer: CGFloat = 0

    var difficulty: HelixDifficulty = .standard

    // MARK: - Derived

    var mid: CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    /// Live segment endpoints (for collision with Stix later).
    var segment: HelixSegment {
        HelixSegment(x1: a.x, y1: a.y, x2: b.x, y2: b.y)
    }

    var stateLabel: String { mode.label }

    // MARK: - Audio drivers (motion → Qix voice)

    /// Current parent-segment length in points.
    var segmentLength: CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// Absolute angular sweep rate (rad/s).
    var angularRate: CGFloat { abs(omega) }

    /// Average endpoint speed (points/s).
    var endpointSpeed: CGFloat {
        (a.speed() + b.speed()) * 0.5
    }

    /// Asymmetry between ends — classic fan when one end leads hard.
    var endpointSpeedDelta: CGFloat {
        abs(a.speed() - b.speed())
    }

    // MARK: - Init

    init(size: CGSize) {
        width = size.width
        height = size.height

        let dim = min(size.width, size.height)
        minLen = dim * 0.12
        maxLen = dim * 0.55

        bounds = Bounds.from(size: size, pad: Self.wallPad, topExtra: 28)

        let cx = size.width * 0.5
        let cy = size.height * 0.5
        let half = maxLen * 0.4

        a = HelixEndpoint(
            x: cx - half * 0.85,
            y: cy - half * 0.25,
            vx: randomRange(-120, -40),
            vy: randomRange(-100, 100)
        )
        b = HelixEndpoint(
            x: cx + half * 0.85,
            y: cy + half * 0.25,
            vx: randomRange(80, 200),
            vy: randomRange(-160, 160)
        )

        lead = Bool.random() ? .a : .b
        leadTimer = randomRange(0.8, 2.0)
        omega = randomRange(1.8, 3.2) * (Bool.random() ? 1 : -1)
        omegaTimer = randomRange(0.6, 1.6)

        playerPosition = CGPoint(x: cx, y: cy)

        rollLengthTarget()
        seedTrail()
    }

    // MARK: - Configuration

    func resize(to size: CGSize) {
        width = size.width
        height = size.height
        let dim = min(size.width, size.height)
        minLen = dim * 0.12
        maxLen = dim * 0.55
        if lengthTarget == 0 {
            rollLengthTarget()
        }
        bounds = Bounds.from(size: size, pad: Self.wallPad, topExtra: 28)
    }

    /// Confine helix to remaining unclaimed pixel rect (from playfield).
    func setBounds(_ newBounds: Bounds?) {
        guard let newBounds else { return }
        bounds = newBounds.inset(by: 4)
    }

    func setPlayer(x: CGFloat, y: CGFloat) {
        playerPosition = CGPoint(x: x, y: y)
    }

    func setPlayer(_ point: CGPoint) {
        playerPosition = point
    }

    func setDifficulty(_ d: HelixDifficulty) {
        difficulty = d
    }

    /// Place the segment near a world point (for multi-helix spacing).
    func placeNear(x: CGFloat, y: CGFloat, spread: CGFloat = 80) {
        let half = min(maxLen * 0.35, spread)
        a.x = x - half * 0.7
        a.y = y - half * 0.3
        b.x = x + half * 0.7
        b.y = y + half * 0.3
        a.vx = randomRange(-140, 140)
        a.vy = randomRange(-140, 140)
        b.vx = randomRange(-140, 140)
        b.vy = randomRange(-140, 140)
        seedTrail()
    }

    func placeNear(_ point: CGPoint, spread: CGFloat = 80) {
        placeNear(x: point.x, y: point.y, spread: spread)
    }

    /// Force an immediate lunge (useful for debugging / claim reactions later).
    func provoke() {
        enterLunge(kind: CGFloat.random(in: 0...1) < 0.55 ? .player : .center)
    }

    // MARK: - Claimed-cell resolution (playfield hooks)

    /// Callback signature matches future `Playfield` integration.
    /// When an endpoint sits in claimed space, nudge toward nearest open cell.
    func resolveClaimed(
        isClaimed: (CGFloat, CGFloat) -> Bool,
        nearestUnclaimed: (CGFloat, CGFloat) -> CGPoint?
    ) {
        for ep in [a, b] {
            if !isClaimed(ep.x, ep.y) { continue }
            if let p = nearestUnclaimed(ep.x, ep.y) {
                ep.x = p.x
                ep.y = p.y
                ep.vx *= -0.6
                ep.vy *= -0.6
            }
        }
    }

    // MARK: - Update

    func update(dt rawDt: CGFloat) {
        let dt = min(rawDt, 0.05)
        // Higher levels think/move faster
        let sdt = dt * difficulty.speed

        modeTimer -= sdt
        if modeTimer <= 0 {
            pickNextMode()
        }

        leadTimer -= sdt
        if leadTimer <= 0 {
            lead.toggle()
            leadTimer = randomRange(0.7, 2.2)
            omega = randomRange(1.6, 3.6) * difficulty.omegaScale * (Bool.random() ? 1 : -1)
        }

        omegaTimer -= sdt
        if omegaTimer <= 0 {
            if CGFloat.random(in: 0...1) < 0.4 {
                omega = -omega
            } else {
                omega = randomRange(1.4, 3.8) * difficulty.omegaScale * (omega >= 0 ? 1 : -1)
            }
            if CGFloat.random(in: 0...1) < 0.25 {
                omega *= randomRange(1.3, 1.9)
            }
            omegaTimer = randomRange(0.5, 1.4)
        }

        lengthTimer -= sdt
        if lengthTimer <= 0 {
            rollLengthTarget()
        }

        steer(sdt)
        breatheLength(sdt)
        constrainLength(sdt)

        a.integrate(dt: sdt, bounds: bounds)
        b.integrate(dt: sdt, bounds: bounds)

        sampleAccum += dt * 1000
        while sampleAccum >= Self.sampleMs {
            sampleAccum -= Self.sampleMs
            pushSample()
        }
    }

    // MARK: - Mode transitions

    private func pickNextMode() {
        let roll = CGFloat.random(in: 0...1)
        let agg = difficulty.aggression

        switch mode {
        case .lunge:
            if CGFloat.random(in: 0...1) < 0.45 {
                enterLoiter()
            } else {
                enterWander()
            }
            return
        case .loiter:
            if CGFloat.random(in: 0...1) < 0.25 + agg {
                enterLunge(kind: CGFloat.random(in: 0...1) < 0.45 ? .center : .player)
            } else {
                enterWander()
            }
            return
        case .wander:
            break
        }

        // Higher aggression → more lunges at the player
        if roll < 0.5 - agg * 0.3 {
            enterWander()
        } else if roll < 0.68 - agg * 0.15 {
            enterLoiter()
        } else {
            enterLunge(kind: CGFloat.random(in: 0...1) < 0.35 + agg ? .player : .center)
        }
    }

    private func enterWander() {
        mode = .wander
        modeTimer = randomRange(1.0, 2.4)
        lungeTarget = nil

        let (leader, follower) = leadPair()
        // Leader gets a strong new heading; follower gets a milder, different one
        nudgeEndpoint(leader, speed: randomRange(160, 280))
        nudgeEndpoint(follower, speed: randomRange(50, 130))
        omega = randomRange(1.8, 3.5) * (Bool.random() ? 1 : -1)
    }

    private func enterLoiter() {
        mode = .loiter
        // Short only — first version lingered too long
        modeTimer = randomRange(0.35, 0.85)
        lungeTarget = nil
        a.vx *= 0.45
        a.vy *= 0.45
        b.vx *= 0.45
        b.vy *= 0.45
    }

    private enum LungeKind {
        case player
        case center
    }

    private func enterLunge(kind: LungeKind) {
        mode = .lunge
        modeTimer = randomRange(0.5, 0.95)

        let cx = bounds.midX
        let cy = bounds.midY

        switch kind {
        case .player:
            lungeTarget = playerPosition
        case .center:
            lungeTarget = CGPoint(x: cx + randomRange(-50, 50), y: cy + randomRange(-50, 50))
        }

        guard let target = lungeTarget else { return }

        // Asymmetric lunge: one end charges hard, the other sweeps wider/slower
        // so history fans from the lagging end (classic wedge), not from midpoint.
        let midX = (a.x + b.x) * 0.5
        let midY = (a.y + b.y) * 0.5
        let toTx = target.x - midX
        let toTy = target.y - midY
        let tLen = length(toTx, toTy)
        let inv = tLen > 0 ? 1 / tLen : 1
        let px = -toTy * inv
        let py = toTx * inv
        let spread = randomRange(minLen * 0.25, minLen * 0.55)
        lungeBias = CGPoint(x: px * spread, y: py * spread)

        let kickLead = randomRange(300, 460)
        let kickFollow = kickLead * randomRange(0.35, 0.65)
        let bias = lungeBias!

        if lead == .a {
            aimEndpoint(a, tx: target.x - bias.x * 0.3, ty: target.y - bias.y * 0.3, speed: kickLead)
            aimEndpoint(b, tx: target.x + bias.x, ty: target.y + bias.y, speed: kickFollow)
        } else {
            aimEndpoint(b, tx: target.x + bias.x * 0.3, ty: target.y + bias.y * 0.3, speed: kickLead)
            aimEndpoint(a, tx: target.x - bias.x, ty: target.y - bias.y, speed: kickFollow)
        }
    }

    // MARK: - Steering

    private func steer(_ dt: CGFloat) {
        switch mode {
        case .wander:
            let (leader, follower) = leadPair()
            // Primary classic look: free end sweeps around the lagging pivot.
            sweepLeaderAroundPivot(leader: leader, pivot: follower, omega: omega, dt: dt)
            meander(leader, accel: 140, dt: dt, maxSpeed: 280)
            meander(follower, accel: 70, dt: dt, maxSpeed: 130)
            if CGFloat.random(in: 0...1) < 0.02 {
                follower.vx += randomRange(-80, 80)
                follower.vy += randomRange(-80, 80)
            }

        case .loiter:
            let (leader, follower) = leadPair()
            // Keep a slower sweep while "waiting" so the fan stays open
            sweepLeaderAroundPivot(leader: leader, pivot: follower, omega: omega * 0.55, dt: dt)
            meander(a, accel: 40, dt: dt, maxSpeed: 70)
            meander(b, accel: 55, dt: dt, maxSpeed: 90)
            dampen(follower, rate: 1.1, dt: dt)
            dampen(leader, rate: 0.5, dt: dt)

        case .lunge:
            guard let t = lungeTarget else { return }
            let bias = lungeBias ?? .zero
            let (leader, follower) = leadPair()
            // Extra whip during the pounce
            sweepLeaderAroundPivot(leader: leader, pivot: follower, omega: omega * 1.35, dt: dt)
            if lead == .a {
                steerToward(a, tx: t.x - bias.x * 0.3, ty: t.y - bias.y * 0.3, accel: 560, dt: dt)
                steerToward(b, tx: t.x + bias.x, ty: t.y + bias.y, accel: 380, dt: dt)
            } else {
                steerToward(b, tx: t.x + bias.x * 0.3, ty: t.y + bias.y * 0.3, accel: 560, dt: dt)
                steerToward(a, tx: t.x - bias.x, ty: t.y - bias.y, accel: 380, dt: dt)
            }
            capSpeed(a, max: 480)
            capSpeed(b, max: 480)
        }
    }

    /// Drive the free end tangentially around the pivot end.
    /// Pivot only gets a small share of the motion so history clusters there
    /// (classic wedge) instead of bowing around midspan.
    private func sweepLeaderAroundPivot(leader: HelixEndpoint, pivot: HelixEndpoint, omega: CGFloat, dt: CGFloat) {
        let rx = leader.x - pivot.x
        let ry = leader.y - pivot.y
        let r = length(rx, ry)
        let invR = r > 0 ? 1 / r : 1
        // Tangential unit * speed (= |omega| * r)
        let tvx = (-ry * invR) * omega * r
        let tvy = (rx * invR) * omega * r

        // Blend a solid chunk of leader velocity toward the sweep
        let blend = 1 - exp(-5.5 * dt)
        leader.vx += (tvx - leader.vx * 0.35) * blend * 2.8
        leader.vy += (tvy - leader.vy * 0.35) * blend * 2.8

        // Tiny opposite reaction on pivot so it isn't a welded nail — still laggy
        pivot.vx -= tvx * blend * 0.12
        pivot.vy -= tvy * blend * 0.12
    }

    private func meander(_ ep: HelixEndpoint, accel: CGFloat, dt: CGFloat, maxSpeed: CGFloat) {
        ep.vx += randomRange(-1, 1) * accel * dt
        ep.vy += randomRange(-1, 1) * accel * dt
        capSpeed(ep, max: maxSpeed)
    }

    private func steerToward(_ ep: HelixEndpoint, tx: CGFloat, ty: CGFloat, accel: CGFloat, dt: CGFloat) {
        let dx = tx - ep.x
        let dy = ty - ep.y
        let d = length(dx, dy)
        let inv = d > 0 ? 1 / d : 1
        ep.vx += dx * inv * accel * dt
        ep.vy += dy * inv * accel * dt
    }

    private func dampen(_ ep: HelixEndpoint, rate: CGFloat, dt: CGFloat) {
        let f = exp(-rate * dt)
        ep.vx *= f
        ep.vy *= f
    }

    private func capSpeed(_ ep: HelixEndpoint, max maxSpeed: CGFloat) {
        let s = ep.speed()
        if s > maxSpeed {
            let inv = 1 / s
            ep.vx = ep.vx * inv * maxSpeed
            ep.vy = ep.vy * inv * maxSpeed
        }
    }

    private func nudgeEndpoint(_ ep: HelixEndpoint, speed: CGFloat) {
        let ang = CGFloat.random(in: 0..<(CGFloat.pi * 2))
        ep.vx = cos(ang) * speed
        ep.vy = sin(ang) * speed
    }

    private func aimEndpoint(_ ep: HelixEndpoint, tx: CGFloat, ty: CGFloat, speed: CGFloat) {
        let dx = tx - ep.x
        let dy = ty - ep.y
        let d = length(dx, dy)
        let inv = d > 0 ? 1 / d : 1
        ep.vx = dx * inv * speed
        ep.vy = dy * inv * speed
    }

    private func leadPair() -> (leader: HelixEndpoint, follower: HelixEndpoint) {
        lead == .a ? (a, b) : (b, a)
    }

    // MARK: - Length breathing

    private func rollLengthTarget() {
        // Bias toward extremes so it really shortens and lengthens, not mid-range hum
        let u = CGFloat.random(in: 0...1)
        let t: CGFloat
        if u < 0.45 {
            t = randomRange(0, 0.28)
        } else if u < 0.9 {
            t = randomRange(0.72, 1)
        } else {
            t = randomRange(0.35, 0.65)
        }
        lengthTarget = minLen + (maxLen - minLen) * t
        lengthTimer = randomRange(0.45, 1.25)
    }

    /// Actively stretch / collapse the parent segment toward lengthTarget.
    /// Along-segment only — no midspan pin.
    private func breatheLength(_ dt: CGFloat) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let d = length(dx, dy)
        guard d > 0 else { return }
        let err = d - lengthTarget
        // Stronger when far from target so short↔long reads clearly
        let strength = 55 + min(80, abs(err) * 0.35)
        let f = (err / d) * strength * dt
        a.vx += dx * f
        a.vy += dy * f
        b.vx -= dx * f
        b.vy -= dy * f
    }

    private func constrainLength(_ dt: CGFloat) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let d = length(dx, dy)
        let safeD = max(d, 0.0001)

        if d < minLen || d > maxLen {
            let target = clamp(d, minLen, maxLen)
            let ux = dx / safeD
            let uy = dy / safeD
            let mx = (a.x + b.x) * 0.5
            let my = (a.y + b.y) * 0.5
            let half = target * 0.5
            let k = 1 - exp(-10 * dt)
            let ax = mx - ux * half
            let ay = my - uy * half
            let bx = mx + ux * half
            let by = my + uy * half
            a.x += (ax - a.x) * k
            a.y += (ay - a.y) * k
            b.x += (bx - b.x) * k
            b.y += (by - b.y) * k

            let rvA = a.vx * ux + a.vy * uy
            let rvB = b.vx * ux + b.vy * uy
            if d < minLen {
                if rvA > 0 {
                    a.vx -= ux * rvA
                    a.vy -= uy * rvA
                }
                if rvB < 0 {
                    b.vx -= ux * rvB
                    b.vy -= uy * rvB
                }
            } else {
                if rvA < 0 {
                    a.vx -= ux * rvA
                    a.vy -= uy * rvA
                }
                if rvB > 0 {
                    b.vx -= ux * rvB
                    b.vy -= uy * rvB
                }
            }
        }
    }

    // MARK: - Trail

    private func seedTrail() {
        // Seed as if the free end has already been sweeping around the pivot end.
        trail.removeAll(keepingCapacity: true)
        let leader = lead == .a ? a : b
        let pivot = lead == .a ? b : a
        let rx0 = leader.x - pivot.x
        let ry0 = leader.y - pivot.y

        for i in 0..<Self.trailLength {
            // Older samples are further back in the sweep
            let age = CGFloat(Self.trailLength - 1 - i) / CGFloat(Self.trailLength)
            let ang = -omega * age * 0.55 // ~half-radian fan already open
            let c = cos(ang)
            let s = sin(ang)
            let rx = rx0 * c - ry0 * s
            let ry = rx0 * s + ry0 * c
            // Pivot drifts slightly in older history so it isn't a perfect nail
            let pdx = pivot.vx * age * -0.04
            let pdy = pivot.vy * age * -0.04
            let px = pivot.x + pdx
            let py = pivot.y + pdy
            if lead == .a {
                trail.append(HelixSegment(x1: px + rx, y1: py + ry, x2: px, y2: py))
            } else {
                trail.append(HelixSegment(x1: px, y1: py, x2: px + rx, y2: py + ry))
            }
        }
    }

    private func pushSample() {
        trail.append(HelixSegment(x1: a.x, y1: a.y, x2: b.x, y2: b.y))
        while trail.count > Self.trailLength {
            trail.removeFirst()
        }
    }
}

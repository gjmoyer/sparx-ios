//
//  SparkField.swift
//  Qix
//
//  Death / reform particle bursts — port of Sparx `sparks.js`.
//

import CoreGraphics
import Foundation

struct SparkParticle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var colorIndex: Int
    var life: CGFloat
    var maxLife: CGFloat
    var size: CGFloat
    var trail: CGFloat
    var attractX: CGFloat?
    var attractY: CGFloat?
    var attract: CGFloat

    var isDead: Bool { life <= 0 }
}

struct SparkRing {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat
    var maxR: CGFloat
    var life: CGFloat
    var maxLife: CGFloat
    var width: CGFloat
    var colorIndex: Int
}

final class SparkField {
    private(set) var particles: [SparkParticle] = []
    private(set) var rings: [SparkRing] = []

    var isActive: Bool { !particles.isEmpty || !rings.isEmpty }

    static let palette: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (1, 1, 1),
        (1, 0.91, 0.63),
        (1, 0.80, 0.27),
        (1, 0.48, 0.09),
        (1, 0.25, 0.25),
        (0.47, 0.93, 1),
        (0.30, 0.88, 1),
        (0.66, 1, 0.38),
    ]

    static let reformPalette: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (1, 1, 1),
        (0.78, 1, 1),
        (0.47, 0.93, 1),
        (0.30, 0.88, 1),
        (0.66, 1, 0.38),
        (1, 0.91, 0.63),
    ]

    func burst(at point: CGPoint, count: Int = 90, speedMin: CGFloat = 120, speedMax: CGFloat = 520) {
        for i in 0..<count {
            let ang = (CGFloat(i) / CGFloat(count)) * .pi * 2 + randomRange(-0.12, 0.12)
            let ang2 = CGFloat.random(in: 0..<(CGFloat.pi * 2))
            let use = CGFloat.random(in: 0...1) < 0.65 ? ang : ang2
            var spd = randomRange(speedMin, speedMax)
            if CGFloat.random(in: 0...1) < 0.15 { spd *= randomRange(1.2, 1.8) }
            particles.append(
                SparkParticle(
                    x: point.x + randomRange(-3, 3),
                    y: point.y + randomRange(-3, 3),
                    vx: cos(use) * spd,
                    vy: sin(use) * spd,
                    colorIndex: Int.random(in: 0..<Self.palette.count),
                    life: randomRange(0.45, 1.15),
                    maxLife: 0,
                    size: randomRange(1.2, 3.4),
                    trail: hypot(cos(use) * spd, sin(use) * spd) * 0.018,
                    attractX: nil,
                    attractY: nil,
                    attract: 0
                )
            )
            particles[particles.count - 1].maxLife = particles[particles.count - 1].life
        }
        for i in 0..<24 {
            let ang = (CGFloat(i) / 24) * .pi * 2
            let spd = randomRange(280, 640)
            particles.append(
                SparkParticle(
                    x: point.x, y: point.y,
                    vx: cos(ang) * spd, vy: sin(ang) * spd,
                    colorIndex: 0,
                    life: randomRange(0.2, 0.45),
                    maxLife: 0,
                    size: randomRange(2.5, 5),
                    trail: spd * 0.018,
                    attractX: nil, attractY: nil, attract: 0
                )
            )
            particles[particles.count - 1].maxLife = particles[particles.count - 1].life
        }
    }

    func reform(at point: CGPoint, count: Int = 70) {
        for i in 0..<count {
            let ang = (CGFloat(i) / CGFloat(count)) * .pi * 2 + randomRange(-0.2, 0.2)
            let dist = randomRange(40, 160)
            let sx = point.x + cos(ang) * dist
            let sy = point.y + sin(ang) * dist
            let dx = point.x - sx
            let dy = point.y - sy
            let d = max(hypot(dx, dy), 1)
            let spd = randomRange(180, 420)
            let tx = -dy / d
            let ty = dx / d
            var p = SparkParticle(
                x: sx, y: sy,
                vx: (dx / d) * spd + tx * randomRange(-80, 80),
                vy: (dy / d) * spd + ty * randomRange(-80, 80),
                colorIndex: Int.random(in: 0..<Self.reformPalette.count),
                life: randomRange(0.5, 0.95),
                maxLife: 0,
                size: randomRange(1.4, 3.2),
                trail: spd * 0.018,
                attractX: point.x, attractY: point.y, attract: 900
            )
            p.maxLife = p.life
            particles.append(p)
        }
        for _ in 0..<16 {
            let ang = CGFloat.random(in: 0..<(CGFloat.pi * 2))
            let spd = randomRange(40, 140)
            var p = SparkParticle(
                x: point.x, y: point.y,
                vx: cos(ang) * spd, vy: sin(ang) * spd,
                colorIndex: 0,
                life: randomRange(0.25, 0.5),
                maxLife: 0,
                size: randomRange(2, 4.5),
                trail: spd * 0.018,
                attractX: nil, attractY: nil, attract: 0
            )
            p.maxLife = p.life
            particles.append(p)
        }
    }

    func pulseRings(at point: CGPoint) {
        rings.append(contentsOf: [
            SparkRing(x: point.x, y: point.y, r: 4, maxR: 70, life: 0.55, maxLife: 0.55, width: 3, colorIndex: 5),
            SparkRing(x: point.x, y: point.y, r: 2, maxR: 110, life: 0.75, maxLife: 0.75, width: 2, colorIndex: 0),
            SparkRing(x: point.x, y: point.y, r: 8, maxR: 45, life: 0.4, maxLife: 0.4, width: 4, colorIndex: 6),
        ])
    }

    func clear() {
        particles.removeAll(keepingCapacity: true)
        rings.removeAll(keepingCapacity: true)
    }

    func update(dt: CGFloat) {
        for i in stride(from: particles.count - 1, through: 0, by: -1) {
            updateParticle(&particles[i], dt: dt)
            if particles[i].isDead { particles.remove(at: i) }
        }
        for i in stride(from: rings.count - 1, through: 0, by: -1) {
            rings[i].life -= dt
            let u = 1 - rings[i].life / rings[i].maxLife
            rings[i].r = rings[i].maxR * (1 - pow(1 - u, 2))
            if rings[i].life <= 0 { rings.remove(at: i) }
        }
    }

    private func updateParticle(_ p: inout SparkParticle, dt: CGFloat) {
        p.life -= dt
        if p.attract > 0, let ax = p.attractX, let ay = p.attractY {
            let dx = ax - p.x
            let dy = ay - p.y
            let d = max(hypot(dx, dy), 1)
            p.vx += (dx / d) * p.attract * dt
            p.vy += (dy / d) * p.attract * dt
            if d < 6 && p.life < p.maxLife * 0.45 {
                p.life = 0
                return
            }
            p.vx *= exp(-1.2 * dt)
            p.vy *= exp(-1.2 * dt)
        } else {
            p.vx *= exp(-1.8 * dt)
            p.vy *= exp(-1.8 * dt)
            p.vy += 90 * dt
        }
        p.x += p.vx * dt
        p.y += p.vy * dt
    }
}

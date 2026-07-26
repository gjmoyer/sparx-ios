//
//  Geometry.swift
//  Qix
//
//  Shared math helpers — ported from the Sparx JS utilities.
//

import CoreGraphics
import Foundation

@inline(__always)
func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
    max(a, min(b, v))
}

@inline(__always)
func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
    max(a, min(b, v))
}

@inline(__always)
func clamp(_ v: Int, _ a: Int, _ b: Int) -> Int {
    max(a, min(b, v))
}

@inline(__always)
func length(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
    hypot(dx, dy)
}

@inline(__always)
func length(_ p: CGPoint) -> CGFloat {
    hypot(p.x, p.y)
}

/// Uniform random in [a, b]. Named to avoid clashing with Darwin `rand()`.
/// Single CGFloat overload so integer literals (e.g. `randomRange(300, 460)`) are unambiguous.
@inline(__always)
func randomRange(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    a + CGFloat.random(in: 0...1) * (b - a)
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    var length: CGFloat { hypot(x, y) }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func normalized() -> CGPoint {
        let len = length
        guard len > 1e-8 else { return .zero }
        return CGPoint(x: x / len, y: y / len)
    }
}

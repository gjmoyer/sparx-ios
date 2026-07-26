//
//  Bounds.swift
//  Qix
//
//  Axis-aligned rectangle used to confine the Helix (and later other entities)
// to the unclaimed playfield region.
//

import CoreGraphics

struct Bounds: Equatable, Sendable {
    var left: CGFloat
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat

    var width: CGFloat { right - left }
    var height: CGFloat { bottom - top }
    var midX: CGFloat { (left + right) * 0.5 }
    var midY: CGFloat { (top + bottom) * 0.5 }
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    static func from(size: CGSize, pad: CGFloat = 0, topExtra: CGFloat = 0) -> Bounds {
        Bounds(
            left: pad,
            top: pad + topExtra,
            right: size.width - pad,
            bottom: size.height - pad
        )
    }

    func inset(by amount: CGFloat) -> Bounds {
        Bounds(
            left: left + amount,
            top: top + amount,
            right: right - amount,
            bottom: bottom - amount
        )
    }

    func contains(_ p: CGPoint) -> Bool {
        p.x >= left && p.x <= right && p.y >= top && p.y <= bottom
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: QixClamp.clamp(p.x, left, right), y: QixClamp.clamp(p.y, top, bottom))
    }
}

/// Disambiguates from Foundation/CoreGraphics clamp helpers when needed.
enum QixClamp {
    @inline(__always)
    static func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        max(a, min(b, v))
    }
}

//
//  HelixEndpoint.swift
//  Qix
//
//  Free endpoint of the Helix line segment.
//  Each end has independent velocity; motion is NOT pinned to a shared midpoint.
//

import CoreGraphics
import Foundation

final class HelixEndpoint {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat

    var position: CGPoint {
        get { CGPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }

    var velocity: CGPoint {
        get { CGPoint(x: vx, y: vy) }
        set {
            vx = newValue.x
            vy = newValue.y
        }
    }

    init(x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }

    convenience init(position: CGPoint, velocity: CGPoint = .zero) {
        self.init(x: position.x, y: position.y, vx: velocity.x, vy: velocity.y)
    }

    func speed() -> CGFloat {
        hypot(vx, vy)
    }

    /// Euler integrate and bounce off axis-aligned bounds with slight speed jitter.
    func integrate(dt: CGFloat, bounds: Bounds) {
        x += vx * dt
        y += vy * dt

        if x < bounds.left {
            x = bounds.left
            vx = abs(vx) * randomRange(0.75, 1.15)
        } else if x > bounds.right {
            x = bounds.right
            vx = -abs(vx) * randomRange(0.75, 1.15)
        }

        if y < bounds.top {
            y = bounds.top
            vy = abs(vy) * randomRange(0.75, 1.15)
        } else if y > bounds.bottom {
            y = bounds.bottom
            vy = -abs(vy) * randomRange(0.75, 1.15)
        }
    }
}

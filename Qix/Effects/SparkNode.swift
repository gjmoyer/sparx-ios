//
//  SparkNode.swift
//  Qix
//
//  SpriteKit presentation for SparkField particles and rings.
//

import SpriteKit
import UIKit

final class SparkNode: SKNode {
    private let batch = SKNode()

    override init() {
        super.init()
        name = "sparks"
        zPosition = 60
        addChild(batch)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(_ field: SparkField) {
        batch.removeAllChildren()

        for ring in field.rings {
            let a = max(0, ring.life / ring.maxLife)
            let node = SKShapeNode(circleOfRadius: max(0.5, ring.r))
            node.position = CGPoint(x: ring.x, y: ring.y)
            node.fillColor = .clear
            let c = SparkField.palette[min(ring.colorIndex, SparkField.palette.count - 1)]
            node.strokeColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: a * 0.85)
            node.lineWidth = ring.width * a
            node.glowWidth = 8
            batch.addChild(node)
        }

        for p in field.particles {
            let t = max(0, p.life / p.maxLife)
            let alpha = t * t
            let spd = hypot(p.vx, p.vy)
            let len = max(p.size, p.trail * (spd / 200) + p.size)
            var dx = p.vx
            var dy = p.vy
            let d = max(hypot(dx, dy), 1)
            dx /= d
            dy /= d

            let path = CGMutablePath()
            path.move(to: CGPoint(x: p.x - dx * len, y: p.y - dy * len))
            path.addLine(to: CGPoint(x: p.x + dx * len * 0.25, y: p.y + dy * len * 0.25))

            let useReform = p.attract > 0
            let palette = useReform ? SparkField.reformPalette : SparkField.palette
            let c = palette[min(p.colorIndex, palette.count - 1)]
            let color = UIColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)

            let line = SKShapeNode(path: path)
            line.strokeColor = color
            line.lineWidth = max(1, p.size * 0.55 * t)
            line.lineCap = .round
            line.glowWidth = 4 * t
            batch.addChild(line)

            let tip = SKShapeNode(circleOfRadius: max(0.8, p.size * 0.45 * t))
            tip.position = CGPoint(x: p.x, y: p.y)
            tip.fillColor = color
            tip.strokeColor = .clear
            batch.addChild(tip)
        }
    }
}

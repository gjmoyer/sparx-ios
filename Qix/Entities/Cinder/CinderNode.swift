//
//  CinderNode.swift
//  Qix
//
//  Renders the cinder pack as spiky orbs on the perimeter.
//

import SpriteKit
import UIKit

final class CinderNode: SKNode {
    private var bodyNodes: [SKShapeNode] = []

    override init() {
        super.init()
        name = "cinders"
        zPosition = 30
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(pack: CinderPack, time: TimeInterval) {
        if pack.hidden {
            isHidden = true
            return
        }
        isHidden = false

        let list = pack.list
        while bodyNodes.count < list.count {
            let node = SKShapeNode()
            node.lineWidth = 2
            node.glowWidth = 8
            addChild(node)
            bodyNodes.append(node)
        }
        while bodyNodes.count > list.count {
            bodyNodes.removeLast().removeFromParent()
        }

        let cell = pack.field?.cellSize ?? 4
        for (i, cinder) in list.enumerated() {
            let node = bodyNodes[i]
            let pulse = 0.75 + 0.25 * sin(cinder.pulse)
            let r = max(10, cell * 2.4) * pulse
            let col: UIColor = cinder.isSuper
                ? UIColor(red: 1, green: 0.16, blue: 0.42, alpha: 1)
                : UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)

            let path = CGMutablePath()
            let spikes = 8
            for s in 0..<spikes {
                let a0 = (CGFloat(s) / CGFloat(spikes)) * .pi * 2 + cinder.pulse * 0.15
                let a1 = ((CGFloat(s) + 0.5) / CGFloat(spikes)) * .pi * 2 + cinder.pulse * 0.15
                let x0 = cos(a0) * r
                let y0 = sin(a0) * r
                let x1 = cos(a1) * r * 0.42
                let y1 = sin(a1) * r * 0.42
                if s == 0 { path.move(to: CGPoint(x: x0, y: y0)) }
                else { path.addLine(to: CGPoint(x: x0, y: y0)) }
                path.addLine(to: CGPoint(x: x1, y: y1))
            }
            path.closeSubpath()
            node.path = path
            node.fillColor = col
            node.strokeColor = .white
            node.glowWidth = 10 * pulse
            node.position = cinder.position
        }
    }
}

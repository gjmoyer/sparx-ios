//
//  HelixNode.swift
//  Qix
//
//  SpriteKit presentation of a Helix: rainbow afterimage ribbon + glowing tips.
//  Logic stays in `Helix`; this node only samples state and draws.
//

import SpriteKit
import UIKit

/// Renders the Helix trail as layered SKShapeNodes (older ghosts under live segment).
final class HelixNode: SKNode {
    private let helix: Helix
    private var segmentNodes: [SKShapeNode] = []
    private let tipA = SKShapeNode(circleOfRadius: 1.8)
    private let tipB = SKShapeNode(circleOfRadius: 1.8)

    /// Optional debug label showing AI mode (hidden by default in production).
    let modeLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    init(helix: Helix) {
        self.helix = helix
        super.init()
        name = "helix"
        zPosition = 20
        setupNodes()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupNodes() {
        // Pre-allocate trail slots so we don't thrash the node tree every frame.
        for i in 0..<Helix.trailLength {
            let node = SKShapeNode()
            node.lineCap = .round
            node.lineJoin = .round
            node.glowWidth = i == Helix.trailLength - 1 ? 4 : 2
            node.zPosition = CGFloat(i)
            addChild(node)
            segmentNodes.append(node)
        }

        for tip in [tipA, tipB] {
            tip.fillColor = UIColor(white: 1, alpha: 0.9)
            tip.strokeColor = .clear
            tip.glowWidth = 3
            tip.zPosition = 100
            addChild(tip)
        }

        modeLabel.fontSize = 11
        modeLabel.fontColor = UIColor(white: 0.7, alpha: 0.85)
        modeLabel.verticalAlignmentMode = .center
        modeLabel.horizontalAlignmentMode = .center
        modeLabel.zPosition = 110
        modeLabel.isHidden = true
        addChild(modeLabel)
    }

    /// Show/hide AI mode text near the segment midpoint.
    var showsModeLabel: Bool {
        get { !modeLabel.isHidden }
        set { modeLabel.isHidden = !newValue }
    }

    func refresh() {
        let trail = helix.trail
        let n = trail.count
        let total = max(n, 1)

        for i in 0..<segmentNodes.count {
            let node = segmentNodes[i]
            if i < n {
                let seg = trail[i]
                let path = CGMutablePath()
                path.move(to: CGPoint(x: seg.x1, y: seg.y1))
                path.addLine(to: CGPoint(x: seg.x2, y: seg.y2))
                node.path = path
                node.isHidden = false

                let isLive = i == n - 1
                node.strokeColor = Self.trailColor(index: i, total: total)
                node.lineWidth = isLive ? 2.6 : 1.7
                node.glowWidth = isLive ? 6 : 2
                node.alpha = 1
            } else {
                node.isHidden = true
            }
        }

        if let tip = trail.last {
            tipA.position = CGPoint(x: tip.x1, y: tip.y1)
            tipB.position = CGPoint(x: tip.x2, y: tip.y2)
            tipA.isHidden = false
            tipB.isHidden = false
        } else {
            tipA.isHidden = true
            tipB.isHidden = true
        }

        if showsModeLabel {
            modeLabel.text = helix.stateLabel
            modeLabel.position = helix.mid + CGPoint(x: 0, y: 18)
        }
    }

    /// Rainbow afterimage color — hue 0→160, older ghosts still readable.
    private static func trailColor(index: Int, total: Int) -> UIColor {
        let t = CGFloat(index) / CGFloat(max(1, total - 1))
        let hue = (0 + t * 160) / 360
        let light = 0.42 + t * 0.18
        // Older ghosts stay more visible so the fan reads as a body, not a blink
        let alpha = 0.38 + t * 0.62
        return UIColor(hue: hue, saturation: 1, brightness: light + 0.25, alpha: alpha)
    }
}

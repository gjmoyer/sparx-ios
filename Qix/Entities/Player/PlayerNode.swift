//
//  PlayerNode.swift
//  Qix
//
//  Distinctive marker reticle + open Stix + fuse (Sparx player draw).
//

import SpriteKit
import UIKit

final class PlayerNode: SKNode {
    private let stixNode = SKShapeNode()
    private let fuseTrail = SKShapeNode()
    private let fuseHead = SKShapeNode(circleOfRadius: 5)
    private let markerRoot = SKNode()
    private let glow = SKShapeNode(circleOfRadius: 18)
    private let halo = SKShapeNode(circleOfRadius: 14)
    private let core = SKShapeNode(circleOfRadius: 6)
    private let pin = SKShapeNode(circleOfRadius: 2)
    private let brackets = SKShapeNode()
    private let chevron = SKShapeNode()
    private let spinRing = SKShapeNode(circleOfRadius: 18)

    override init() {
        super.init()
        name = "player"
        zPosition = 40

        stixNode.lineCap = .square
        stixNode.lineJoin = .miter
        stixNode.glowWidth = 3
        stixNode.zPosition = 1
        stixNode.fillColor = .clear
        addChild(stixNode)

        fuseTrail.lineCap = .round
        fuseTrail.lineJoin = .round
        fuseTrail.glowWidth = 4
        fuseTrail.zPosition = 2
        fuseTrail.fillColor = .clear
        addChild(fuseTrail)

        fuseHead.fillColor = UIColor(red: 1, green: 0.93, blue: 0.4, alpha: 1)
        fuseHead.strokeColor = .clear
        fuseHead.glowWidth = 8
        fuseHead.zPosition = 3
        fuseHead.isHidden = true
        addChild(fuseHead)

        markerRoot.zPosition = 10
        addChild(markerRoot)

        glow.fillColor = UIColor(white: 0, alpha: 0.55)
        glow.strokeColor = .clear
        glow.glowWidth = 10
        markerRoot.addChild(glow)

        halo.fillColor = .clear
        halo.lineWidth = 2
        halo.alpha = 0.55
        markerRoot.addChild(halo)

        brackets.strokeColor = .white
        brackets.lineWidth = 2.2
        brackets.lineCap = .square
        brackets.glowWidth = 3
        brackets.fillColor = .clear
        markerRoot.addChild(brackets)

        chevron.lineWidth = 1.5
        chevron.strokeColor = .white
        chevron.glowWidth = 4
        markerRoot.addChild(chevron)

        core.lineWidth = 2
        core.strokeColor = UIColor(white: 0.07, alpha: 1)
        core.glowWidth = 6
        markerRoot.addChild(core)

        pin.fillColor = .white
        pin.strokeColor = .clear
        pin.position = CGPoint(x: -1.2, y: 1.5)
        markerRoot.addChild(pin)

        spinRing.fillColor = .clear
        spinRing.lineWidth = 2
        spinRing.alpha = 0.75
        spinRing.glowWidth = 2
        spinRing.isHidden = true
        markerRoot.addChild(spinRing)

        rebuildBrackets(radius: 14)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(player: Player, time: TimeInterval) {
        guard let field = player.field else {
            isHidden = true
            return
        }

        // Stix
        if player.alive && !player.path.isEmpty {
            let path = CGMutablePath()
            for (i, cell) in player.path.enumerated() {
                let p = field.cellToPixel(c: cell.c, r: cell.r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.addLine(to: player.position)
            stixNode.path = path
            stixNode.strokeColor = player.slow
                ? UIColor(red: 1, green: 0.48, blue: 0.09, alpha: 1)
                : UIColor(red: 0.30, green: 0.88, blue: 1, alpha: 1)
            stixNode.lineWidth = max(2, field.cellSize * 0.55)
            stixNode.isHidden = false
            refreshFuse(player: player, field: field, time: time)
        } else {
            stixNode.isHidden = true
            fuseTrail.isHidden = true
            fuseHead.isHidden = true
        }

        if !player.alive && player.respawnT == nil {
            markerRoot.isHidden = true
            return
        }

        let reforming = player.respawnT != nil
        let pos = reforming ? player.spawnPosition : player.position
        let t = reforming ? (player.respawnT ?? 0) : 1
        let appear = reforming ? min(1, max(0, (t - 0.25) / 0.55)) : 1
        if appear <= 0 && reforming {
            markerRoot.isHidden = true
            return
        }
        let ease = appear * appear * (3 - 2 * appear)
        let scale = reforming ? 0.15 + ease * 0.85 : 1
        let alpha = reforming ? ease : 1

        markerRoot.isHidden = false
        markerRoot.position = pos
        markerRoot.setScale(scale)
        markerRoot.alpha = alpha

        let pulse = 0.85 + 0.15 * sin(time * 5.5)
        let R = max(11, field.cellSize * 2.6) * pulse

        let coreColor: UIColor
        let rim: UIColor
        if player.drawing {
            if player.slow {
                coreColor = UIColor(red: 1, green: 0.69, blue: 0.38, alpha: 1)
                rim = UIColor(red: 1, green: 0.42, blue: 0.09, alpha: 1)
            } else {
                coreColor = UIColor(red: 0.66, green: 1, blue: 1, alpha: 1)
                rim = UIColor(red: 0.20, green: 0.84, blue: 1, alpha: 1)
            }
        } else {
            coreColor = .white
            rim = UIColor(red: 0.72, green: 1, blue: 0.42, alpha: 1)
        }

        glow.setScale(R / 18)
        halo.setScale(R / 14)
        halo.strokeColor = rim
        core.fillColor = coreColor
        core.setScale(max(4.5, R * 0.32) / 6)
        pin.setScale(max(1.6, R * 0.12) / 2)

        rebuildBrackets(radius: R)

        // Facing chevron
        let faceAng: CGFloat
        switch player.facing {
        case .up: faceAng = .pi / 2
        case .down: faceAng = -.pi / 2
        case .left: faceAng = .pi
        case .right: faceAng = 0
        }
        let chev = CGMutablePath()
        chev.move(to: CGPoint(x: R * 0.15, y: 0))
        chev.addLine(to: CGPoint(x: R * 1.05, y: -R * 0.28))
        chev.addLine(to: CGPoint(x: R * 0.72, y: 0))
        chev.addLine(to: CGPoint(x: R * 1.05, y: R * 0.28))
        chev.closeSubpath()
        chevron.path = chev
        chevron.fillColor = rim
        chevron.zRotation = faceAng

        if player.drawing {
            spinRing.isHidden = false
            spinRing.strokeColor = rim
            spinRing.setScale(R * 1.2 / 18)
            spinRing.zRotation = CGFloat(time) * (player.slow ? 2.2 : 4.5)
        } else {
            spinRing.isHidden = true
        }
    }

    private func refreshFuse(player: Player, field: Playfield, time: TimeInterval) {
        guard player.drawing, player.path.count >= 2 else {
            fuseTrail.isHidden = true
            fuseHead.isHidden = true
            return
        }

        if player.fuseDist <= 0.02 {
            fuseTrail.isHidden = true
            if player.fuseLit {
                let p0 = field.cellToPixel(c: player.path[0].c, r: player.path[0].r)
                fuseHead.position = p0
                fuseHead.isHidden = false
                fuseHead.setScale(player.fuseLit ? 1 : 0.7)
            } else {
                fuseHead.isHidden = true
            }
            return
        }

        let d = player.fuseDist
        let iMax = min(Int(floor(d)), player.path.count - 2)
        let path = CGMutablePath()
        for i in 0...iMax {
            let p = field.cellToPixel(c: player.path[i].c, r: player.path[i].r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        if iMax + 1 < player.path.count {
            let a = field.cellToPixel(c: player.path[iMax].c, r: player.path[iMax].r)
            let b = field.cellToPixel(c: player.path[iMax + 1].c, r: player.path[iMax + 1].r)
            let t = d - CGFloat(iMax)
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        fuseTrail.path = path
        fuseTrail.strokeColor = UIColor(red: 1, green: 0.24, blue: 0.08, alpha: 0.85)
        fuseTrail.lineWidth = max(3, field.cellSize * 0.75)
        fuseTrail.glowWidth = player.fuseLit ? 8 : 3
        fuseTrail.isHidden = false

        if let head = player.fuseWorldPos() {
            fuseHead.position = head
            fuseHead.isHidden = false
            let flicker = player.fuseLit ? 0.75 + 0.25 * sin(time * 12) : 0.45
            fuseHead.alpha = flicker
            fuseHead.fillColor = player.fuseLit
                ? UIColor(red: 1, green: 0.93, blue: 0.4, alpha: 1)
                : UIColor(red: 0.67, green: 0.4, blue: 0.13, alpha: 1)
        } else {
            fuseHead.isHidden = true
        }
    }

    private func rebuildBrackets(radius R: CGFloat) {
        let bIn = R * 0.42
        let bOut = R * 0.92
        let bLen = R * 0.38
        let path = CGMutablePath()
        let corners: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        for (sx, sy) in corners {
            path.move(to: CGPoint(x: sx * bOut, y: sy * bOut))
            path.addLine(to: CGPoint(x: sx * (bOut - bLen), y: sy * bOut))
            path.move(to: CGPoint(x: sx * bOut, y: sy * bOut))
            path.addLine(to: CGPoint(x: sx * bOut, y: sy * (bOut - bLen)))
            path.move(to: CGPoint(x: sx * bIn, y: sy * bIn))
            path.addLine(to: CGPoint(x: sx * (bIn + bLen * 0.45), y: sy * bIn))
            path.move(to: CGPoint(x: sx * bIn, y: sy * bIn))
            path.addLine(to: CGPoint(x: sx * bIn, y: sy * (bIn + bLen * 0.45)))
        }
        brackets.path = path
    }
}

//
//  TouchControlsNode.swift
//  Qix
//
//  Mobile controls:
//  - Left: fixed virtual joystick (4-way snap — Qix is orthogonal only)
//  - Right: SLOW / FAST sticky toggles, stacked vertically
//
//  Simulator: tap SLOW/FAST to arm, then drag the stick (or use WASD + Space/Shift).
//

import SpriteKit
import UIKit

final class TouchControlsNode: SKNode {
    private let input: InputState

    // MARK: - Joystick

    private let stickRoot = SKNode()
    private let stickBase = SKShapeNode()
    private let stickKnob = SKShapeNode()
    private let stickHit = SKShapeNode() // large invisible hit pad
    private var stickRadius: CGFloat = 56
    private var knobRadius: CGFloat = 22
    private var stickCenter: CGPoint = .zero
    private var stickTouch: UITouch?
    private var currentDir: InputAction?

    // MARK: - Draw buttons

    private let actionsRoot = SKNode()
    private var buttonLocalFrames: [String: CGRect] = [:] // in self space

    // Dead zone as fraction of stick radius
    private let deadZone: CGFloat = 0.28

    init(input: InputState) {
        self.input = input
        super.init()
        name = "touchControls"
        zPosition = 500
        isUserInteractionEnabled = true

        addChild(stickRoot)
        stickRoot.addChild(stickHit)
        stickRoot.addChild(stickBase)
        stickRoot.addChild(stickKnob)
        addChild(actionsRoot)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter safeInsets: view safe area (home indicator, notch) in points.
    func layout(sceneSize: CGSize, safeInsets: UIEdgeInsets = .zero) {
        actionsRoot.removeAllChildren()
        buttonLocalFrames.removeAll()

        // Comfortable thumb zone; keep fully on-screen inside safe area.
        // Stick needs extra left/bottom inset so stroke + glow don't clip the bezel.
        let margin: CGFloat = 12
        let stickEdgePad: CGFloat = 22 // keep outer ring clear of the bezel (iPad)
        let rightPad = safeInsets.right + margin
        let bottomPad = max(safeInsets.bottom, 8) + margin + stickEdgePad
        let leftPad = max(safeInsets.left, 0) + margin + stickEdgePad

        // —— Virtual joystick (bottom-left) ——
        stickRadius = min(58, sceneSize.width * 0.13)
        knobRadius = stickRadius * 0.40
        // Nudge: a bit right, and down by 3× that amount, then ease up ~10pt.
        let nudgeRight: CGFloat = 12
        let nudgeDown = nudgeRight * 3 - 10 // net down 26pt (was 36)
        stickCenter = CGPoint(
            x: leftPad + stickRadius + nudgeRight,
            y: bottomPad + stickRadius - nudgeDown
        )
        stickRoot.position = stickCenter

        // Generous hit pad so the thumb doesn't miss the stick
        let hitR = stickRadius * 1.55
        stickHit.path = CGPath(ellipseIn: CGRect(x: -hitR, y: -hitR, width: hitR * 2, height: hitR * 2), transform: nil)
        stickHit.fillColor = UIColor(white: 1, alpha: 0.04)
        stickHit.strokeColor = .clear
        stickHit.name = "stickHit"
        stickHit.zPosition = 0

        stickBase.path = CGPath(
            ellipseIn: CGRect(x: -stickRadius, y: -stickRadius, width: stickRadius * 2, height: stickRadius * 2),
            transform: nil
        )
        stickBase.fillColor = UIColor(white: 0.1, alpha: 0.55)
        stickBase.strokeColor = UIColor(white: 0.55, alpha: 0.75)
        stickBase.lineWidth = 2
        stickBase.glowWidth = 1
        stickBase.name = "stickBase"
        stickBase.zPosition = 1

        // Crosshair ticks — hint 4-way
        let tick = SKShapeNode()
        let tPath = CGMutablePath()
        let t = stickRadius * 0.72
        tPath.move(to: CGPoint(x: 0, y: t * 0.55))
        tPath.addLine(to: CGPoint(x: 0, y: t))
        tPath.move(to: CGPoint(x: 0, y: -t * 0.55))
        tPath.addLine(to: CGPoint(x: 0, y: -t))
        tPath.move(to: CGPoint(x: t * 0.55, y: 0))
        tPath.addLine(to: CGPoint(x: t, y: 0))
        tPath.move(to: CGPoint(x: -t * 0.55, y: 0))
        tPath.addLine(to: CGPoint(x: -t, y: 0))
        tick.path = tPath
        tick.strokeColor = UIColor(white: 0.45, alpha: 0.7)
        tick.lineWidth = 1.5
        tick.lineCap = .round
        tick.name = "ticks"
        stickBase.removeAllChildren()
        stickBase.addChild(tick)

        stickKnob.path = CGPath(
            ellipseIn: CGRect(x: -knobRadius, y: -knobRadius, width: knobRadius * 2, height: knobRadius * 2),
            transform: nil
        )
        stickKnob.fillColor = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.85)
        stickKnob.strokeColor = UIColor(white: 1, alpha: 0.85)
        stickKnob.lineWidth = 1.5
        stickKnob.glowWidth = 4
        stickKnob.position = .zero
        stickKnob.name = "stickKnob"
        stickKnob.zPosition = 2

        // —— Draw buttons (bottom-right), vertical stack, same X ——
        let btnW = min(78, sceneSize.width * 0.19)
        let btnH = min(48, btnW * 0.62)
        let stackGap: CGFloat = 10
        let stackHeight = btnH * 2 + stackGap

        // Center of stack sits above bottom pad so both buttons fully fit
        let stackMidY = bottomPad + stackHeight * 0.5
        let btnX = sceneSize.width - rightPad - btnW * 0.5

        // FAST on top, SLOW immediately under it (same x)
        let fastY = stackMidY + (btnH + stackGap) * 0.5
        let slowY = stackMidY - (btnH + stackGap) * 0.5

        placeDrawButton(action: .fast, label: "FAST", center: CGPoint(x: btnX, y: fastY), width: btnW, height: btnH)
        placeDrawButton(action: .slow, label: "SLOW", center: CGPoint(x: btnX, y: slowY), width: btnW, height: btnH)

        // Reset stick visual if no active touch
        if stickTouch == nil {
            stickKnob.position = .zero
            setStickDir(nil)
        }

        refreshDrawHighlights()
    }

    func syncFromInput() {
        refreshDrawHighlights()
    }

    // MARK: - Build draw button

    private func placeDrawButton(action: InputAction, label: String, center: CGPoint, width: CGFloat, height: CGFloat) {
        let node = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 12)
        node.fillColor = UIColor(white: 0.12, alpha: 0.78)
        node.strokeColor = UIColor(white: 0.55, alpha: 0.85)
        node.lineWidth = 1.5
        node.position = center
        node.name = action.rawValue
        actionsRoot.addChild(node)

        let text = SKLabelNode(fontNamed: "Menlo-Bold")
        text.text = label
        text.name = "label"
        text.fontSize = 13
        text.fontColor = UIColor(white: 0.92, alpha: 1)
        text.verticalAlignmentMode = .center
        text.horizontalAlignmentMode = .center
        node.addChild(text)

        buttonLocalFrames[action.rawValue] = CGRect(
            x: center.x - width * 0.5,
            y: center.y - height * 0.5,
            width: width,
            height: height
        )
    }

    // MARK: - Hit testing

    private func drawAction(at p: CGPoint) -> InputAction? {
        for (name, frame) in buttonLocalFrames {
            if frame.contains(p), let a = InputAction(rawValue: name), a.isDrawMode {
                return a
            }
        }
        return nil
    }

    private func isInStickZone(_ p: CGPoint) -> Bool {
        let d = hypot(p.x - stickCenter.x, p.y - stickCenter.y)
        return d <= stickRadius * 1.55
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)

            if let draw = drawAction(at: p) {
                input.toggleStickyDraw(draw)
                refreshDrawHighlights()
                continue
            }

            if stickTouch == nil, isInStickZone(p) {
                stickTouch = touch
                updateStick(to: p)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard touch === stickTouch else { continue }
            updateStick(to: touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === stickTouch {
                releaseStick()
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Stick logic

    private func updateStick(to p: CGPoint) {
        var dx = p.x - stickCenter.x
        var dy = p.y - stickCenter.y
        let len = hypot(dx, dy)
        let maxR = stickRadius * 0.92
        if len > maxR, len > 0 {
            dx = dx / len * maxR
            dy = dy / len * maxR
        }
        stickKnob.position = CGPoint(x: dx, y: dy)

        let magnitude = hypot(dx, dy) / stickRadius
        if magnitude < deadZone {
            setStickDir(nil)
            return
        }

        // 4-way only (Qix / Stix are orthogonal)
        if abs(dx) >= abs(dy) {
            setStickDir(dx >= 0 ? .right : .left)
        } else {
            setStickDir(dy >= 0 ? .up : .down)
        }
    }

    private func releaseStick() {
        stickTouch = nil
        stickKnob.position = .zero
        setStickDir(nil)
    }

    private func setStickDir(_ dir: InputAction?) {
        if currentDir == dir { return }
        currentDir = dir
        input.setDirection(dir)
        // Visual feedback on base ring
        stickBase.strokeColor = dir != nil
            ? UIColor(red: 0.24, green: 1, blue: 0.42, alpha: 0.9)
            : UIColor(white: 0.55, alpha: 0.75)
        stickKnob.fillColor = dir != nil
            ? UIColor(red: 0.35, green: 1, blue: 0.55, alpha: 0.95)
            : UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.85)
    }

    // MARK: - Draw button look

    private func refreshDrawHighlights() {
        let armed = input.stickyDraw
        for n in actionsRoot.children {
            guard let shape = n as? SKShapeNode,
                  let name = n.name,
                  let action = InputAction(rawValue: name)
            else { continue }

            let on = armed == action
            if action == .slow {
                shape.fillColor = on
                    ? UIColor(red: 0.85, green: 0.35, blue: 0.08, alpha: 0.95)
                    : UIColor(white: 0.12, alpha: 0.78)
                shape.strokeColor = on
                    ? UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
                    : UIColor(white: 0.55, alpha: 0.85)
                if let label = shape.childNode(withName: "label") as? SKLabelNode {
                    label.text = on ? "SLOW ●" : "SLOW"
                }
            } else if action == .fast {
                shape.fillColor = on
                    ? UIColor(red: 0.08, green: 0.45, blue: 0.65, alpha: 0.95)
                    : UIColor(white: 0.12, alpha: 0.78)
                shape.strokeColor = on
                    ? UIColor(red: 0.3, green: 0.88, blue: 1, alpha: 1)
                    : UIColor(white: 0.55, alpha: 0.85)
                if let label = shape.childNode(withName: "label") as? SKLabelNode {
                    label.text = on ? "FAST ●" : "FAST"
                }
            }
        }
    }
}

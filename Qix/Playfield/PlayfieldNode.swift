//
//  PlayfieldNode.swift
//  Qix
//
//  Renders fill kinds + permanent white walls into a single texture sprite.
//  Outer frame is a single continuous rectangle so corners stay clean
//  (no per-cell segment stubs / double-thick joins).
//

import SpriteKit
import UIKit

final class PlayfieldNode: SKNode {
    private let sprite = SKSpriteNode()
    private var lastVisualVersion: Int = -1
    private weak var field: Playfield?

    override init() {
        super.init()
        name = "playfield"
        zPosition = 1
        sprite.anchorPoint = .zero
        sprite.zPosition = 0
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(_ field: Playfield) {
        self.field = field
        lastVisualVersion = -1
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        guard let field else { return }
        if !force && field.visualVersion == lastVisualVersion { return }
        lastVisualVersion = field.visualVersion
        sprite.texture = Self.renderTexture(field: field)
        sprite.size = CGSize(width: field.pixelWidth, height: field.pixelHeight)
        sprite.position = .zero
    }

    private static func renderTexture(field: Playfield) -> SKTexture {
        let w = max(1, Int(ceil(field.pixelWidth)))
        let h = max(1, Int(ceil(field.pixelHeight)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // UIKit Y-down → flip so grid row 0 is bottom (SpriteKit).
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: 1, y: -1)

            let s = field.cellSize
            let patterns = makePatterns()

            // Fill runs
            for kind in [FillKind.border, .fast, .slow] {
                drawFillRuns(field: field, kind: kind, cellSize: s, pattern: patterns[kind]!, cg: cg)
            }

            drawWalls(field: field, cellSize: s, cg: cg)
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    // MARK: - Patterns (match Sparx diamond tiles)

    private static func makePatterns() -> [FillKind: UIImage] {
        [
            .border: diamondTile(
                bg: UIColor(red: 0.04, green: 0.16, blue: 0.04, alpha: 1),
                line: UIColor(red: 0.12, green: 0.56, blue: 0.23, alpha: 1),
                edge: UIColor(red: 0.05, green: 0.35, blue: 0.12, alpha: 1)
            ),
            .fast: diamondTile(
                bg: UIColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1),
                line: UIColor(red: 0.16, green: 0.50, blue: 1.0, alpha: 1),
                edge: UIColor(red: 0.04, green: 0.23, blue: 0.48, alpha: 1)
            ),
            .slow: diamondTile(
                bg: UIColor(red: 0.16, green: 0.05, blue: 0.02, alpha: 1),
                line: UIColor(red: 1.0, green: 0.35, blue: 0.09, alpha: 1),
                edge: UIColor(red: 0.54, green: 0.16, blue: 0.03, alpha: 1)
            ),
        ]
    }

    private static func diamondTile(bg: UIColor, line: UIColor, edge: UIColor) -> UIImage {
        let s: CGFloat = 16
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            bg.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
            line.setStroke()
            cg.setLineWidth(1)
            cg.beginPath()
            cg.move(to: CGPoint(x: s / 2, y: 1))
            cg.addLine(to: CGPoint(x: s - 1, y: s / 2))
            cg.addLine(to: CGPoint(x: s / 2, y: s - 1))
            cg.addLine(to: CGPoint(x: 1, y: s / 2))
            cg.closePath()
            cg.strokePath()
            edge.setStroke()
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: s - 1, height: s - 1))
        }
    }

    private static func drawFillRuns(
        field: Playfield,
        kind: FillKind,
        cellSize s: CGFloat,
        pattern: UIImage,
        cg: CGContext
    ) {
        // Tile the pattern into each horizontal run of this fill kind.
        guard let tile = pattern.cgImage else {
            fallbackSolid(field: field, kind: kind, cellSize: s, cg: cg)
            return
        }
        let tw = CGFloat(tile.width)
        let th = CGFloat(tile.height)

        for r in 0..<field.rows {
            var runStart = -1
            for c in 0...field.cols {
                let on = c < field.cols && field.fillAt(c: c, r: r) == kind
                if on && runStart < 0 { runStart = c }
                if !on && runStart >= 0 {
                    let rect = CGRect(
                        x: CGFloat(runStart) * s,
                        y: CGFloat(r) * s,
                        width: CGFloat(c - runStart) * s,
                        height: s
                    )
                    cg.saveGState()
                    cg.clip(to: rect)
                    // Repeat diamond tile across the run
                    var x = rect.minX
                    while x < rect.maxX {
                        var y = rect.minY
                        while y < rect.maxY {
                            cg.draw(tile, in: CGRect(x: x, y: y, width: tw, height: th))
                            y += th
                        }
                        x += tw
                    }
                    cg.restoreGState()
                    runStart = -1
                }
            }
        }
    }

    private static func fallbackSolid(field: Playfield, kind: FillKind, cellSize s: CGFloat, cg: CGContext) {
        let color: UIColor
        switch kind {
        case .border: color = UIColor(red: 0.05, green: 0.22, blue: 0.08, alpha: 1)
        case .fast: color = UIColor(red: 0.04, green: 0.18, blue: 0.38, alpha: 1)
        case .slow: color = UIColor(red: 0.38, green: 0.10, blue: 0.04, alpha: 1)
        case .empty: return
        }
        color.setFill()
        for r in 0..<field.rows {
            var runStart = -1
            for c in 0...field.cols {
                let on = c < field.cols && field.fillAt(c: c, r: r) == kind
                if on && runStart < 0 { runStart = c }
                if !on && runStart >= 0 {
                    cg.fill(CGRect(
                        x: CGFloat(runStart) * s,
                        y: CGFloat(r) * s,
                        width: CGFloat(c - runStart) * s,
                        height: s
                    ))
                    runStart = -1
                }
            }
        }
    }

    // MARK: - Walls

    private static func drawWalls(field: Playfield, cellSize s: CGFloat, cg: CGContext) {
        let lineW = max(2, s * 0.55)
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(lineW)
        cg.setLineCap(.square)
        cg.setLineJoin(.miter)
        cg.setMiterLimit(4)

        // Outer frame as ONE continuous rect — clean square corners, no double stubs.
        let frame = CGRect(x: 0, y: 0, width: CGFloat(field.cols) * s, height: CGFloat(field.rows) * s)
        // Inset by half stroke so the stroke sits fully inside the texture.
        let inset = lineW * 0.5
        let outer = frame.insetBy(dx: inset, dy: inset)
        cg.stroke(outer)

        // Interior permanent walls only (skip pure outer-frame keys).
        cg.beginPath()
        for key in field.walls {
            let parts = key.split(separator: ",")
            guard parts.count == 3 else { continue }
            let kind = parts[0]
            let c = Int(parts[1]) ?? 0
            let r = Int(parts[2]) ?? 0

            if kind == "v" {
                // Outer left/right already covered by the rect.
                if c == -1 || c == field.cols - 1 { continue }
                let x = CGFloat(c + 1) * s
                let y0 = CGFloat(r) * s
                let y1 = CGFloat(r + 1) * s
                cg.move(to: CGPoint(x: x, y: y0))
                cg.addLine(to: CGPoint(x: x, y: y1))
            } else if kind == "h" {
                // Outer top/bottom already covered by the rect.
                if r == -1 || r == field.rows - 1 { continue }
                let y = CGFloat(r + 1) * s
                let x0 = CGFloat(c) * s
                let x1 = CGFloat(c + 1) * s
                cg.move(to: CGPoint(x: x0, y: y))
                cg.addLine(to: CGPoint(x: x1, y: y))
            }
        }
        cg.strokePath()
    }
}

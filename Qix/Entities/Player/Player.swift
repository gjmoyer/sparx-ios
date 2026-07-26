//
//  Player.swift
//  Qix
//
//  Player marker — walks claimed boundary, draws Stix into the open, closes to fill.
//  Port of Sparx `player.js`.
//
//  Controls:
//    D-pad / arrows — move
//    Slow — orange draw (double points)
//    Fast — cyan draw
//  Fuse: while drawing and stopped, fuse burns from Stix start toward marker.
//

import CoreGraphics
import Foundation

enum PlayerFacing: String, Sendable {
    case up, down, left, right

    var delta: (dc: Int, dr: Int) {
        switch self {
        case .left: return (-1, 0)
        case .right: return (1, 0)
        case .up: return (0, 1) // SpriteKit: +y is up → higher row index
        case .down: return (0, -1)
        }
    }
}

struct PlayerUpdateResult {
    var fuseHit: Bool = false
}

/// Marker that walks the claimed rim and draws Stix into the open pit.
final class Player {
    weak var field: Playfield?

    var c: Int = 0
    var r: Int = 0
    var spawnC: Int = 0
    var spawnR: Int = 0
    var drawing = false
    var slow = false
    var path: [GridCell] = []
    var alive = true
    var facing: PlayerFacing = .up
    var moveAccum: CGFloat = 0
    var respawnT: CGFloat?

    /// Distance along path in cell steps from start (0 = first path cell).
    var fuseDist: CGFloat = 0
    /// Currently burning (player stopped while drawing).
    var fuseLit = false
    var fuseKilled = false

    private static let fuseSpeed: CGFloat = 14

    var x: CGFloat {
        guard let field else { return 0 }
        return field.cellToPixel(c: c, r: r).x
    }

    var y: CGFloat {
        guard let field else { return 0 }
        return field.cellToPixel(c: c, r: r).y
    }

    var position: CGPoint { CGPoint(x: x, y: y) }

    var spawnPosition: CGPoint {
        guard let field else { return .zero }
        return field.cellToPixel(c: spawnC, r: spawnR)
    }

    init(field: Playfield) {
        self.field = field
        reset()
    }

    func reset() {
        guard let field else { return }
        // Bottom-center of the outer frame (SpriteKit: row 0 is bottom).
        c = field.cols / 2
        r = 0
        spawnC = c
        spawnR = r
        drawing = false
        slow = false
        path = []
        alive = true
        moveAccum = 0
        facing = .up
        respawnT = nil
        clearFuse()
    }

    func markSafe() {
        spawnC = c
        spawnR = r
    }

    /// After a claim, snap onto a border cell if the current one was buried.
    @discardableResult
    func ensureOnWalkableBoundary() -> Bool {
        guard let field, alive, !drawing else { return false }
        if field.isWalkable(c: c, r: r) {
            markSafe()
            return false
        }
        let near = field.nearestWalkable(c: c, r: r)
        c = near.c
        r = near.r
        markSafe()
        return true
    }

    func respawnAt(c: Int? = nil, r: Int? = nil) {
        guard let field else { return }
        let tc = c ?? spawnC
        let tr = r ?? spawnR
        if field.isWalkable(c: tc, r: tr) {
            self.c = tc
            self.r = tr
        } else {
            let near = field.nearestWalkable(c: tc, r: tr)
            self.c = near.c
            self.r = near.r
        }
        spawnC = self.c
        spawnR = self.r
        drawing = false
        slow = false
        path = []
        alive = true
        moveAccum = 0
        respawnT = 0
        clearFuse()
        _ = ensureOnWalkableBoundary()
    }

    func kill() {
        alive = false
        drawing = false
        path = []
        respawnT = nil
        clearFuse()
    }

    /// World position of the fuse head along the path.
    func fuseWorldPos() -> CGPoint? {
        guard drawing, path.count >= 2, let field else { return nil }
        let d = fuseDist
        let i0 = min(Int(floor(d)), path.count - 2)
        let i1 = i0 + 1
        let t = d - CGFloat(i0)
        let a = field.cellToPixel(c: path[i0].c, r: path[i0].r)
        let b = field.cellToPixel(c: path[i1].c, r: path[i1].r)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    func update(
        input: InputState,
        dt: CGFloat,
        onComplete: ([GridCell], Bool) -> Void
    ) -> PlayerUpdateResult {
        guard alive, let field else { return PlayerUpdateResult() }

        // Safety net: never remain stuck off the walkable rim.
        if !drawing {
            _ = ensureOnWalkableBoundary()
        }

        let slowHeld = input.held.contains(.slow)
        let fastHeld = input.held.contains(.fast)
        let wantDraw = slowHeld || fastHeld
        let dirHeld = readDir(input.held)

        let speed: CGFloat = drawing ? (slow ? 18 : 42) : 38
        moveAccum += dt * speed
        var steps = Int(floor(moveAccum))
        if steps > 0 { moveAccum -= CGFloat(steps) }
        steps = min(steps, 8)

        var moved = false

        for _ in 0..<steps {
            guard let dir = readDir(input.held) else { break }
            facing = dir
            let (dc, dr) = dir.delta
            let nc = c + dc
            let nr = r + dr
            guard field.inBounds(c: nc, r: nr) else { continue }

            if !drawing {
                if wantDraw {
                    // Start a draw only from the true rim into open pit.
                    if field.isBoundary(c: c, r: r), !field.isClaimed(c: nc, r: nr) {
                        markSafe()
                        drawing = true
                        slow = slowHeld && !fastHeld
                        path = [GridCell(c: c, r: r), GridCell(c: nc, r: nr)]
                        c = nc
                        r = nr
                        clearFuse()
                        moved = true
                        continue
                    }
                }
                // Border only: orthogonal step, or diagonal corner-assist onto border.
                if tryBorderMove(toC: nc, toR: nr, field: field) {
                    moved = true
                    continue
                }
                // Concave corner: orthogonal blocked → slide diagonally forward.
                if tryBorderCornerSlide(dir: dir, field: field) {
                    moved = true
                }
            } else {
                // Drawing
                if pathContains(c: nc, r: nr)
                    && !(path.count >= 2 && path[path.count - 2].c == nc && path[path.count - 2].r == nr)
                {
                    if !(field.isClaimed(c: nc, r: nr) && field.isBoundary(c: nc, r: nr)) {
                        continue
                    }
                }

                // Reverse along path
                if path.count >= 2,
                   path[path.count - 2].c == nc,
                   path[path.count - 2].r == nr
                {
                    path.removeLast()
                    c = nc
                    r = nr
                    clampFuseToPath()
                    moved = true
                    if path.count <= 1 {
                        drawing = false
                        path = []
                        clearFuse()
                    }
                    continue
                }

                // Close when stepping onto claimed shoreline/rim.
                if field.isClaimed(c: nc, r: nr) && field.isBoundary(c: nc, r: nr) {
                    path.append(GridCell(c: nc, r: nr))
                    c = nc
                    r = nr
                    let finished = path
                    let wasSlow = slow
                    drawing = false
                    path = []
                    clearFuse()
                    moved = true
                    onComplete(finished, wasSlow)
                    // Fill can bury this cell inside claimed mass — free the player.
                    _ = ensureOnWalkableBoundary()
                    continue
                }

                if !field.isClaimed(c: nc, r: nr) {
                    path.append(GridCell(c: nc, r: nr))
                    c = nc
                    r = nr
                    moved = true
                }
            }
        }

        // Fuse: burn while drawing and stopped; pause while moving
        if drawing && path.count >= 2 {
            if dirHeld != nil && moved {
                fuseLit = false
            } else if dirHeld == nil {
                fuseLit = true
                fuseDist += Self.fuseSpeed * dt
                clampFuseToPath()
                let tipIndex = CGFloat(path.count - 1)
                if fuseDist >= tipIndex - 0.05 {
                    fuseKilled = true
                    fuseDist = tipIndex
                    return PlayerUpdateResult(fuseHit: true)
                }
            }
        } else {
            fuseLit = false
        }

        return PlayerUpdateResult()
    }

    // MARK: - Private

    @discardableResult
    private func tryBorderMove(toC: Int, toR: Int, field: Playfield) -> Bool {
        guard field.isBorderStep(fromC: c, fromR: r, toC: toC, toR: toR) else { return false }
        c = toC
        r = toR
        markSafe()
        return true
    }

    /// When the orthogonal border step is blocked, step diagonally forward
    /// onto another border cell (classic Qix corner feel without leaving the rim).
    @discardableResult
    private func tryBorderCornerSlide(dir: PlayerFacing, field: Playfield) -> Bool {
        let (dc, dr) = dir.delta
        // Sideways offsets perpendicular to movement
        let sides: [(Int, Int)]
        if dc == 0 {
            sides = [(-1, dr), (1, dr)] // moving vertically → diagonal L/R
        } else {
            sides = [(dc, -1), (dc, 1)] // moving horizontally → diagonal U/D
        }
        for (sc, sr) in sides {
            let nc = c + sc
            let nr = r + sr
            if tryBorderMove(toC: nc, toR: nr, field: field) {
                return true
            }
        }
        return false
    }

    private func clearFuse() {
        fuseDist = 0
        fuseLit = false
        fuseKilled = false
    }

    private func clampFuseToPath() {
        if path.isEmpty {
            fuseDist = 0
            return
        }
        let maxD = CGFloat(max(0, path.count - 1))
        fuseDist = min(max(fuseDist, 0), maxD)
    }

    private func pathContains(c: Int, r: Int) -> Bool {
        path.contains { $0.c == c && $0.r == r }
    }

    private func readDir(_ held: Set<InputAction>) -> PlayerFacing? {
        if held.contains(.up) { return .up }
        if held.contains(.down) { return .down }
        if held.contains(.left) { return .left }
        if held.contains(.right) { return .right }
        return nil
    }

}

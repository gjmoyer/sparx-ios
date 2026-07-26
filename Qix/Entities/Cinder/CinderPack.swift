//
//  CinderPack.swift
//  Qix
//
//  Cinders ride a precomputed one-way boundary loop — port of Sparx `cinders.js`.
//

import CoreGraphics
import Foundation

/// Pack of edge-patrolling enemies.
final class CinderPack {
    weak var field: Playfield?
    private(set) var list: [Cinder] = []
    private(set) var loop: [PerimeterPoint] = []
    private var loopVersion: Int = -1
    private var lastSnapVersion: Int = -1
    /// Paused after a kill until player finishes respawn.
    var frozen = false
    /// Hidden briefly on hit so they "disappear" then reappear at home.
    var hidden = false
    /// After thaw / claim snap, ignore hits briefly so we never insta-kill.
    private var hitGrace: CGFloat = 0

    init(field: Playfield) {
        self.field = field
    }

    func spawn(count: Int, superMode: Bool = false, speed: CGFloat = 16) {
        list = []
        frozen = false
        hidden = false
        hitGrace = 0
        rebuildLoop(force: true)
        lastSnapVersion = loopVersion
        guard count > 0, !loop.isEmpty else { return }

        let home = findTopCenterIndex()
        let base = max(14, speed * 1.25)

        for i in 0..<count {
            let dir: Int = i % 2 == 0 ? 1 : -1
            list.append(
                Cinder(
                    pack: self,
                    index: home,
                    dir: dir,
                    isSuper: superMode,
                    speed: base * (0.97 + CGFloat.random(in: 0...0.08))
                )
            )
        }
    }

    func clear() {
        list = []
        loop = []
        loopVersion = -1
        lastSnapVersion = -1
        frozen = false
        hidden = false
        hitGrace = 0
    }

    /// On player kill: vanish and snap every cinder back to playfield top-center.
    func resetAfterPlayerHit() {
        rebuildLoop(force: false)
        snapAllToPlayfieldTopCenter()
        frozen = true
        hidden = true
        hitGrace = 0
    }

    /// Call when the player has finished reforming and is safe to play.
    func thawAfterRespawn() {
        rebuildLoop(force: false)
        snapAllToPlayfieldTopCenter()
        frozen = false
        hidden = false
        // Brief grace so a bad overlap cannot death-loop.
        hitGrace = 1.1
    }

    /// - Returns: true if any cinder touched the player this frame.
    @discardableResult
    func update(dt: CGFloat, player: Player) -> Bool {
        rebuildLoop(force: false)

        // Perimeter changed after a claim — stay on the outline (nearest point).
        // Do NOT send them home; only death / thaw respawns at top-center.
        if lastSnapVersion != loopVersion {
            lastSnapVersion = loopVersion
            let home = findTopCenterIndex()
            for s in list {
                s.homeIndex = home // origin for future death resets only
                s.reattachToLoop()
            }
        }

        if frozen || hidden { return false }

        if hitGrace > 0 {
            hitGrace -= dt
            // Still patrol from home, but cannot kill during grace.
            for s in list {
                _ = s.update(dt: dt, player: player)
            }
            return false
        }

        var hit = false
        for s in list {
            if s.update(dt: dt, player: player) { hit = true }
        }
        if !hit && hitsPlayer(player) { hit = true }
        return hit
    }

    func hitsPlayer(_ player: Player) -> Bool {
        guard player.alive, let field else { return false }
        let hitR = max(14, field.cellSize * 3.5)
        let hitR2 = hitR * hitR
        for s in list {
            if s.touchesPlayer(player, hitR2: hitR2) { return true }
        }
        return false
    }

    /// Snap every cinder to the loop index nearest the playfield top-center.
    func snapAllToPlayfieldTopCenter() {
        let home = findTopCenterIndex()
        for s in list {
            s.homeIndex = home
            s.resetHome()
        }
    }

    /// Loop index nearest the **outer top-center of the playfield**
    /// (not merely the top of whatever unclaimed pocket remains).
    func findTopCenterIndex() -> Int {
        guard !loop.isEmpty, let field else { return 0 }
        let targetX = field.pixelWidth * 0.5
        // SpriteKit: top of the field is high y (outer frame / top rim).
        let targetY = field.pixelHeight - field.cellSize * 0.5
        var best = 0
        var bestD = CGFloat.infinity
        for (i, p) in loop.enumerated() {
            let dx = p.x - targetX
            let dy = p.y - targetY
            // Strongly prefer top edge, then horizontal center.
            let d = dy * dy * 4 + dx * dx
            if d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }

    private func rebuildLoop(force: Bool) {
        guard let field else { return }
        let v = field.perimeterVersion
        if !force && v == loopVersion && !loop.isEmpty { return }
        loop = field.buildOpenPerimeterLoop()
        loopVersion = v
    }
}

// MARK: - Single cinder

final class Cinder {
    unowned let pack: CinderPack
    var homeIndex: Int
    var index: Int
    var dir: Int
    var isSuper: Bool
    var speed: CGFloat
    var accum: CGFloat = 0
    var pulse: CGFloat
    var onStix = false

    private(set) var cellC: Int = 0
    private(set) var cellR: Int = 0
    private(set) var x: CGFloat = 0
    private(set) var y: CGFloat = 0

    var position: CGPoint { CGPoint(x: x, y: y) }

    init(pack: CinderPack, index: Int, dir: Int, isSuper: Bool, speed: CGFloat) {
        self.pack = pack
        self.homeIndex = index
        self.index = index
        self.dir = dir == -1 ? -1 : 1
        self.isSuper = isSuper
        self.speed = speed
        self.pulse = CGFloat.random(in: 0..<(CGFloat.pi * 2))
        syncFromIndex()
    }

    func resetHome() {
        let n = pack.loop.count
        guard n > 0 else { return }
        var hi = homeIndex % n
        if hi < 0 { hi += n }
        homeIndex = hi
        index = hi
        onStix = false
        accum = 0
        syncFromIndex()
    }

    func reattachToLoop() {
        let loop = pack.loop
        guard !loop.isEmpty else { return }
        var best = 0
        var bestD = CGFloat.infinity
        for i in 0..<loop.count {
            let d = abs(loop[i].x - x) + abs(loop[i].y - y)
            if d < bestD {
                bestD = d
                best = i
            }
        }
        index = best
        onStix = false
        syncFromIndex()
    }

    /// - Returns: true if this cinder hit the player during movement.
    func update(dt: CGFloat, player: Player) -> Bool {
        pulse += dt * 8
        let loop = pack.loop
        guard !loop.isEmpty, let field = pack.field else { return false }

        let hitR = max(14, field.cellSize * 3.5)
        let hitR2 = hitR * hitR

        if player.alive && touchesPlayer(player, hitR2: hitR2) { return true }

        accum += dt * speed
        var steps = min(10, Int(floor(accum)))
        accum -= CGFloat(steps)

        while steps > 0 {
            steps -= 1
            if isSuper && player.drawing && player.path.count > 1 {
                if tryChasePathForward(player) {
                    onStix = true
                    if player.alive && touchesPlayer(player, hitR2: hitR2) { return true }
                    continue
                }
            }
            if onStix {
                onStix = false
                reattachToLoop()
            }
            index += dir
            syncFromIndex()
            if player.alive && touchesPlayer(player, hitR2: hitR2) { return true }
        }
        return false
    }

    func touchesPlayer(_ player: Player, hitR2: CGFloat) -> Bool {
        let dc = abs(cellC - player.c)
        let dr = abs(cellR - player.r)
        if dc + dr <= 1 { return true }

        let dx = x - player.x
        let dy = y - player.y
        if dx * dx + dy * dy <= hitR2 { return true }

        if dc <= 1 && dr <= 1 && dc + dr == 2 { return true }
        return false
    }

    private func syncFromIndex() {
        let loop = pack.loop
        guard !loop.isEmpty else {
            cellC = 1
            cellR = 1
            x = 0
            y = 0
            return
        }
        let n = loop.count
        var i = index % n
        if i < 0 { i += n }
        index = i
        let p = loop[i]
        cellC = p.c
        cellR = p.r
        x = p.x
        y = p.y
    }

    private func tryChasePathForward(_ player: Player) -> Bool {
        guard let field = pack.field else { return false }
        let path = player.path
        let d4 = [(1, 0), (0, 1), (-1, 0), (0, -1)]

        let onPath =
            path.contains { $0.c == cellC && $0.r == cellR }
            || (cellC == player.c && cellR == player.r)

        if !onPath {
            var best: GridCell?
            var bestI = -1
            for (dc, dr) in d4 {
                let nc = cellC + dc
                let nr = cellR + dr
                for (pi, p) in path.enumerated() {
                    if p.c == nc && p.r == nr && pi > bestI {
                        bestI = pi
                        best = GridCell(c: nc, r: nr)
                    }
                }
            }
            if let best {
                cellC = best.c
                cellR = best.r
                let px = field.cellToPixel(c: best.c, r: best.r)
                x = px.x
                y = px.y
                return true
            }
            return false
        }

        var curPi = -1
        for (pi, p) in path.enumerated() {
            if p.c == cellC && p.r == cellR { curPi = pi }
        }
        if cellC == player.c && cellR == player.r { return true }

        let nextPi = curPi + 1
        if nextPi < path.count {
            cellC = path[nextPi].c
            cellR = path[nextPi].r
            let px = field.cellToPixel(c: cellC, r: cellR)
            x = px.x
            y = px.y
            return true
        }
        if abs(cellC - player.c) + abs(cellR - player.r) == 1 {
            cellC = player.c
            cellR = player.r
            let px = field.cellToPixel(c: cellC, r: cellR)
            x = px.x
            y = px.y
            return true
        }
        return false
    }
}

//
//  Playfield.swift
//  Qix
//
//  Claimed / unclaimed grid — port of Sparx `playfield.js`.
//
//  fill kinds:
//    empty  = unclaimed (danger)
//    border = neutral frame (green)
//    fast   = fast claim (blue)
//    slow   = slow claim (orange-red, double points)
//

import CoreGraphics
import Foundation

enum FillKind: UInt8, Sendable {
    case empty = 0
    case border = 1
    case fast = 2
    case slow = 3
}

struct GridCell: Hashable, Sendable {
    var c: Int
    var r: Int
}

struct PerimeterPoint: Sendable {
    var x: CGFloat
    var y: CGFloat
    /// Nearest open cell for collision.
    var c: Int
    var r: Int
}

struct ClaimResult: Sendable {
    var gained: Int
    var percent: CGFloat
    var slow: Bool
    var split: Bool
}

/// Grid playfield with permanent walls, flood-fill claims, and perimeter loops.
final class Playfield {
    let cellSize: CGFloat
    private(set) var pixelWidth: CGFloat = 0
    private(set) var pixelHeight: CGFloat = 0
    private(set) var cols: Int = 0
    private(set) var rows: Int = 0
    private(set) var fill: [FillKind] = []
    /// Permanent white walls. Keys: "v,c,r" or "h,c,r".
    private(set) var walls: Set<String> = []
    /// Bumps when geometry changes — Cinders rebuild their one-way loop.
    private(set) var perimeterVersion: Int = 0
    /// Incremented whenever fill/walls change (renderer dirty flag).
    private(set) var visualVersion: Int = 0

    var totalCells: Int { cols * rows }

    init(width: CGFloat, height: CGFloat, cellSize: CGFloat = 4) {
        self.cellSize = cellSize
        resize(width: width, height: height)
    }

    func resize(width: CGFloat, height: CGFloat) {
        pixelWidth = width
        pixelHeight = height
        cols = max(8, Int(width / cellSize))
        rows = max(8, Int(height / cellSize))
        fill = Array(repeating: .empty, count: cols * rows)
        walls.removeAll(keepingCapacity: true)
        perimeterVersion += 1
        visualVersion += 1
        initBorder()
    }

    // MARK: - Queries

    func inBounds(c: Int, r: Int) -> Bool {
        c >= 0 && r >= 0 && c < cols && r < rows
    }

    func isClaimed(c: Int, r: Int) -> Bool {
        if !inBounds(c: c, r: r) { return true }
        return fill[index(c, r)] != .empty
    }

    func fillAt(c: Int, r: Int) -> FillKind {
        if !inBounds(c: c, r: r) { return .border }
        return fill[index(c, r)]
    }

    func setFill(c: Int, r: Int, kind: FillKind) {
        guard inBounds(c: c, r: r) else { return }
        fill[index(c, r)] = kind
        visualVersion += 1
    }

    /// Boundary cell: claimed and adjacent to unclaimed, or outer frame.
    func isBoundary(c: Int, r: Int) -> Bool {
        guard inBounds(c: c, r: r), isClaimed(c: c, r: r) else { return false }
        if c == 0 || r == 0 || c == cols - 1 || r == rows - 1 { return true }
        return touchesUnclaimed(c: c, r: r)
    }

    /// Border-only: outer frame or claimed cells that face the open pit.
    func isWalkable(c: Int, r: Int) -> Bool {
        isBoundary(c: c, r: r)
    }

    /// Orthogonal or diagonal step onto another border cell (corner assist).
    func isBorderStep(fromC: Int, fromR: Int, toC: Int, toR: Int) -> Bool {
        guard isWalkable(c: toC, r: toR) else { return false }
        let dc = abs(toC - fromC)
        let dr = abs(toR - fromR)
        if dc + dr == 1 { return true }       // orthogonal
        if dc == 1 && dr == 1 { return true } // diagonal corner
        return false
    }

    func touchesUnclaimed(c: Int, r: Int) -> Bool {
        (inBounds(c: c - 1, r: r) && !isClaimed(c: c - 1, r: r))
            || (inBounds(c: c + 1, r: r) && !isClaimed(c: c + 1, r: r))
            || (inBounds(c: c, r: r - 1) && !isClaimed(c: c, r: r - 1))
            || (inBounds(c: c, r: r + 1) && !isClaimed(c: c, r: r + 1))
    }

    func isShoreline(c: Int, r: Int) -> Bool {
        guard inBounds(c: c, r: r), isClaimed(c: c, r: r) else { return false }
        return touchesUnclaimed(c: c, r: r)
    }

    /// Nearest border cell (prefer true shoreline facing the pit).
    func nearestWalkable(c: Int, r: Int) -> GridCell {
        if isWalkable(c: c, r: r) { return GridCell(c: c, r: r) }
        let maxRad = max(cols, rows)
        for rad in 1..<maxRad {
            for dr in -rad...rad {
                for dc in -rad...rad {
                    if abs(dc) != rad && abs(dr) != rad { continue }
                    let nc = c + dc
                    let nr = r + dr
                    if isShoreline(c: nc, r: nr) { return GridCell(c: nc, r: nr) }
                }
            }
        }
        for rad in 1..<maxRad {
            for dr in -rad...rad {
                for dc in -rad...rad {
                    if abs(dc) != rad && abs(dr) != rad { continue }
                    let nc = c + dc
                    let nr = r + dr
                    if isWalkable(c: nc, r: nr) { return GridCell(c: nc, r: nr) }
                }
            }
        }
        return GridCell(c: cols / 2, r: 0)
    }

    func cellToPixel(c: Int, r: Int) -> CGPoint {
        CGPoint(x: (CGFloat(c) + 0.5) * cellSize, y: (CGFloat(r) + 0.5) * cellSize)
    }

    func pixelToCell(x: CGFloat, y: CGFloat) -> GridCell {
        GridCell(
            c: clamp(Int(floor(x / cellSize)), 0, cols - 1),
            r: clamp(Int(floor(y / cellSize)), 0, rows - 1)
        )
    }

    func claimedCount() -> Int {
        var n = 0
        for kind in fill where kind != .empty { n += 1 }
        return n
    }

    func percent() -> CGFloat {
        guard totalCells > 0 else { return 0 }
        return CGFloat(claimedCount()) / CGFloat(totalCells) * 100
    }

    // MARK: - Claims

    /// After a closed draw path: claim path, keep Helix-reachable unclaimed, claim rest.
    func completeClaim(pathCells: [GridCell], helixPoints: [CGPoint], slow: Bool) -> ClaimResult {
        let before = claimedCount()
        let kind: FillKind = slow ? .slow : .fast

        var wasEmpty = [UInt8](repeating: 0, count: fill.count)
        for i in 0..<fill.count {
            wasEmpty[i] = fill[i] == .empty ? 1 : 0
        }

        for p in pathCells {
            if fill[index(p.c, p.r)] == .border { continue }
            fill[index(p.c, p.r)] = kind
        }

        // Flood from every Helix — territory either can reach stays open.
        var keep = [UInt8](repeating: 0, count: cols * rows)
        var anySeed = false
        for pt in helixPoints {
            let q = pixelToCell(x: pt.x, y: pt.y)
            var seedC = q.c
            var seedR = q.r
            if isClaimed(c: seedC, r: seedR) {
                guard let near = nearestUnclaimed(c: seedC, r: seedR) else { continue }
                seedC = near.c
                seedR = near.r
            }
            anySeed = true
            floodUnclaimedInto(sc: seedC, sr: seedR, keep: &keep)
        }

        if !anySeed {
            addPathWalls(pathCells)
            visualVersion += 1
            perimeterVersion += 1
            return ClaimResult(
                gained: claimedCount() - before,
                percent: percent(),
                slow: slow,
                split: false
            )
        }

        for r in 0..<rows {
            for c in 0..<cols {
                let id = index(c, r)
                if fill[id] == .empty && keep[id] == 0 {
                    fill[id] = kind
                }
            }
        }

        addPathWalls(pathCells)
        addSilhouetteWalls { id, _, _ in
            wasEmpty[id] == 1 && fill[id] == kind
        }

        perimeterVersion += 1
        visualVersion += 1

        let split = helixPoints.count >= 2 && areHelicesSeparated(helixPoints)

        return ClaimResult(
            gained: claimedCount() - before,
            percent: percent(),
            slow: slow,
            split: split
        )
    }

    /// True if two+ Helix midpoints cannot reach each other through unclaimed cells.
    func areHelicesSeparated(_ points: [CGPoint]) -> Bool {
        guard points.count >= 2 else { return false }
        var seeds: [GridCell] = []
        for pt in points {
            let q = pixelToCell(x: pt.x, y: pt.y)
            if !isClaimed(c: q.c, r: q.r) {
                seeds.append(q)
            } else if let near = nearestUnclaimed(c: q.c, r: q.r) {
                seeds.append(near)
            } else {
                return true
            }
        }
        let reach = floodUnclaimed(sc: seeds[0].c, sr: seeds[0].r)
        for i in 1..<seeds.count {
            let id = index(seeds[i].c, seeds[i].r)
            if reach[id] == 0 { return true }
        }
        return false
    }

    func nearestUnclaimed(c: Int, r: Int) -> GridCell? {
        let maxRad = max(cols, rows)
        for rad in 1..<maxRad {
            for dr in -rad...rad {
                for dc in -rad...rad {
                    if abs(dc) != rad && abs(dr) != rad { continue }
                    let nc = c + dc
                    let nr = r + dr
                    if inBounds(c: nc, r: nr), !isClaimed(c: nc, r: nr) {
                        return GridCell(c: nc, r: nr)
                    }
                }
            }
        }
        return nil
    }

    /// Axis-aligned bounds of remaining unclaimed cells (for confining Helix).
    func unclaimedPixelBounds() -> Bounds? {
        var minC = cols
        var minR = rows
        var maxC = -1
        var maxR = -1
        for r in 0..<rows {
            for c in 0..<cols {
                if !isClaimed(c: c, r: r) {
                    if c < minC { minC = c }
                    if r < minR { minR = r }
                    if c > maxC { maxC = c }
                    if r > maxR { maxR = r }
                }
            }
        }
        guard maxC >= 0 else { return nil }
        let s = cellSize
        return Bounds(
            left: CGFloat(minC) * s,
            top: CGFloat(minR) * s,
            right: CGFloat(maxC + 1) * s,
            bottom: CGFloat(maxR + 1) * s
        )
    }

    // MARK: - Collision helpers

    func segmentHitsClaimed(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> Bool {
        let dx = x2 - x1
        let dy = y2 - y1
        let dist = hypot(dx, dy)
        let steps = max(2, Int(ceil(dist / (cellSize * 0.5))))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cell = pixelToCell(x: x1 + dx * t, y: y1 + dy * t)
            if isClaimed(c: cell.c, r: cell.r) { return true }
        }
        return false
    }

    /// Does the live Helix segment intersect the open draw path?
    func helixHitsPath(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, path: [GridCell]) -> Bool {
        guard path.count >= 2 else { return false }
        let rad = cellSize * 0.9
        for p in path {
            let pt = cellToPixel(c: p.c, r: p.r)
            if pointNearSegment(px: pt.x, py: pt.y, x1: x1, y1: y1, x2: x2, y2: y2, rad: rad) {
                return true
            }
        }
        for i in 1..<path.count {
            let a = cellToPixel(c: path[i - 1].c, r: path[i - 1].r)
            let b = cellToPixel(c: path[i].c, r: path[i].r)
            if segmentsIntersect(a1x: a.x, a1y: a.y, a2x: b.x, a2y: b.y, b1x: x1, b1y: y1, b2x: x2, b2y: y2) {
                return true
            }
        }
        return false
    }

    // MARK: - Perimeter loop (Cinders)

    /// Ordered loop of points along the open-pit boundary.
    func buildOpenPerimeterLoop() -> [PerimeterPoint] {
        let loops = traceBoundaryEdgeLoops()
        guard !loops.isEmpty else { return fallbackPerimeterRing() }
        var best = loops[0]
        for i in 1..<loops.count {
            if loops[i].count > best.count { best = loops[i] }
        }
        return best.count >= 8 ? best : fallbackPerimeterRing()
    }

    // MARK: - Private geometry

    private func index(_ c: Int, _ r: Int) -> Int {
        r * cols + c
    }

    private func initBorder() {
        fill = Array(repeating: .empty, count: cols * rows)
        walls.removeAll(keepingCapacity: true)
        perimeterVersion += 1
        visualVersion += 1
        for c in 0..<cols {
            fill[index(c, 0)] = .border
            fill[index(c, rows - 1)] = .border
        }
        for r in 0..<rows {
            fill[index(0, r)] = .border
            fill[index(cols - 1, r)] = .border
        }
        for c in 0..<cols {
            walls.insert("h,\(c),-1")
            walls.insert("h,\(c),\(rows - 1)")
        }
        for r in 0..<rows {
            walls.insert("v,-1,\(r)")
            walls.insert("v,\(cols - 1),\(r)")
        }
    }

    private func addWallV(c: Int, r: Int) {
        walls.insert("v,\(c),\(r)")
    }

    private func addWallH(c: Int, r: Int) {
        walls.insert("h,\(c),\(r)")
    }

    private func addSilhouetteWalls(_ isInSet: (Int, Int, Int) -> Bool) {
        for r in 0..<rows {
            for c in 0..<cols {
                let id = index(c, r)
                guard isInSet(id, c, r) else { continue }

                if c == 0 || !isInSet(index(c - 1, r), c - 1, r) {
                    addWallV(c: c - 1, r: r)
                }
                if c == cols - 1 || !isInSet(index(c + 1, r), c + 1, r) {
                    addWallV(c: c, r: r)
                }
                if r == 0 || !isInSet(index(c, r - 1), c, r - 1) {
                    addWallH(c: c, r: r - 1)
                }
                if r == rows - 1 || !isInSet(index(c, r + 1), c, r + 1) {
                    addWallH(c: c, r: r)
                }
            }
        }
    }

    private func addPathWalls(_ pathCells: [GridCell]) {
        guard pathCells.count >= 2 else { return }
        for i in 1..<pathCells.count {
            let a = pathCells[i - 1]
            let b = pathCells[i]
            let dc = b.c - a.c
            let dr = b.r - a.r
            var c = a.c
            var r = a.r
            let steps = max(abs(dc), abs(dr), 1)
            let sc = dc == 0 ? 0 : (dc > 0 ? 1 : -1)
            let sr = dr == 0 ? 0 : (dr > 0 ? 1 : -1)
            for _ in 0..<steps {
                if sc > 0 { addWallV(c: c, r: r) }
                else if sc < 0 { addWallV(c: c - 1, r: r) }
                if sr > 0 { addWallH(c: c, r: r) }
                else if sr < 0 { addWallH(c: c, r: r - 1) }
                c += sc
                r += sr
            }
        }
    }

    private func floodUnclaimed(sc: Int, sr: Int) -> [UInt8] {
        var keep = [UInt8](repeating: 0, count: cols * rows)
        floodUnclaimedInto(sc: sc, sr: sr, keep: &keep)
        return keep
    }

    private func floodUnclaimedInto(sc: Int, sr: Int, keep: inout [UInt8]) {
        if isClaimed(c: sc, r: sr) { return }
        let start = index(sc, sr)
        if keep[start] != 0 { return }
        var stack: [Int] = [sc, sr]
        keep[start] = 1
        let dirs = [1, 0, -1, 0, 0, 1, 0, -1]
        while !stack.isEmpty {
            let r = stack.removeLast()
            let c = stack.removeLast()
            for i in 0..<4 {
                let nc = c + dirs[i * 2]
                let nr = r + dirs[i * 2 + 1]
                guard inBounds(c: nc, r: nr) else { continue }
                let id = index(nc, nr)
                if keep[id] != 0 || fill[id] != .empty { continue }
                keep[id] = 1
                stack.append(nc)
                stack.append(nr)
            }
        }
    }

    // MARK: - Boundary edge loops

    private struct Edge {
        var x0: Int, y0: Int, x1: Int, y1: Int
        var oc: Int, or: Int
    }

    private func traceBoundaryEdgeLoops() -> [[PerimeterPoint]] {
        func solid(_ c: Int, _ r: Int) -> Bool {
            c < 0 || r < 0 || c >= cols || r >= rows || fill[index(c, r)] != .empty
        }

        var edges: [String: Edge] = [:]
        var out: [String: [String]] = [:]

        func addEdge(x0: Int, y0: Int, x1: Int, y1: Int, oc: Int, or: Int) {
            let key = "\(x0),\(y0),\(x1),\(y1)"
            if edges[key] != nil { return }
            edges[key] = Edge(x0: x0, y0: y0, x1: x1, y1: y1, oc: oc, or: or)
            let sk = "\(x0),\(y0)"
            out[sk, default: []].append(key)
        }

        for r in 0...rows {
            for c in 0..<cols {
                let above = solid(c, r - 1)
                let below = solid(c, r)
                if above == below { continue }
                if !above && below {
                    addEdge(x0: c + 1, y0: r, x1: c, y1: r, oc: c, or: r - 1)
                } else {
                    addEdge(x0: c, y0: r, x1: c + 1, y1: r, oc: c, or: r)
                }
            }
        }

        for c in 0...cols {
            for r in 0..<rows {
                let left = solid(c - 1, r)
                let right = solid(c, r)
                if left == right { continue }
                if !left && right {
                    addEdge(x0: c, y0: r, x1: c, y1: r + 1, oc: c - 1, or: r)
                } else {
                    addEdge(x0: c, y0: r + 1, x1: c, y1: r, oc: c, or: r)
                }
            }
        }

        guard !edges.isEmpty else { return [] }

        var used = Set<String>()
        var loops: [[PerimeterPoint]] = []
        let s = cellSize

        for startKey in edges.keys {
            if used.contains(startKey) { continue }
            var loop: [PerimeterPoint] = []
            var key: String? = startKey
            var guardCount = 0
            let maxG = edges.count + 4

            while let k = key, !used.contains(k), guardCount < maxG {
                guardCount += 1
                used.insert(k)
                guard let e = edges[k] else { break }
                let mx = (CGFloat(e.x0 + e.x1) * 0.5) * s
                let my = (CGFloat(e.y0 + e.y1) * 0.5) * s
                loop.append(PerimeterPoint(x: mx, y: my, c: e.oc, r: e.or))

                let endK = "\(e.x1),\(e.y1)"
                let nexts = out[endK] ?? []
                var nextKey: String?
                for nk in nexts where !used.contains(nk) {
                    nextKey = nk
                    break
                }
                if nextKey == nil {
                    for nk in nexts where nk == startKey {
                        nextKey = nk
                        break
                    }
                }
                if nextKey == nil || nextKey == startKey {
                    if nextKey == startKey && loop.count >= 8 {
                        loops.append(loop)
                    }
                    break
                }
                key = nextKey
            }
            if loop.count >= 8 && guardCount >= loop.count {
                if !loops.contains(where: { $0.count == loop.count && $0.first?.x == loop.first?.x }) {
                    // Avoid double-add when already closed above
                    if loops.last?.count != loop.count {
                        // Only add if not already pushed
                        let already = loops.contains { arr in
                            arr.count == loop.count && abs((arr.first?.x ?? 0) - (loop.first?.x ?? 0)) < 0.1
                        }
                        if !already { loops.append(loop) }
                    }
                }
            }
        }

        return loops
    }

    private func fallbackPerimeterRing() -> [PerimeterPoint] {
        var ring: [PerimeterPoint] = []
        let s = cellSize
        func empty(_ c: Int, _ r: Int) -> Bool {
            inBounds(c: c, r: r) && fill[index(c, r)] == .empty
        }
        for c in 1..<(cols - 1) {
            if empty(c, 1) {
                ring.append(PerimeterPoint(x: (CGFloat(c) + 0.5) * s, y: 1 * s, c: c, r: 1))
            }
        }
        for r in 2..<(rows - 2) {
            if empty(cols - 2, r) {
                ring.append(PerimeterPoint(x: CGFloat(cols - 1) * s, y: (CGFloat(r) + 0.5) * s, c: cols - 2, r: r))
            }
        }
        for c in stride(from: cols - 2, through: 1, by: -1) {
            if empty(c, rows - 2) {
                ring.append(PerimeterPoint(x: (CGFloat(c) + 0.5) * s, y: CGFloat(rows - 1) * s, c: c, r: rows - 2))
            }
        }
        for r in stride(from: rows - 3, through: 2, by: -1) {
            if empty(1, r) {
                ring.append(PerimeterPoint(x: 1 * s, y: (CGFloat(r) + 0.5) * s, c: 1, r: r))
            }
        }
        return ring
    }
}

// MARK: - Geometry helpers

private func pointNearSegment(px: CGFloat, py: CGFloat, x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, rad: CGFloat) -> Bool {
    let dx = x2 - x1
    let dy = y2 - y1
    let l2 = dx * dx + dy * dy
    if l2 < 1e-6 { return hypot(px - x1, py - y1) <= rad }
    var t = ((px - x1) * dx + (py - y1) * dy) / l2
    t = max(0, min(1, t))
    let qx = x1 + t * dx
    let qy = y1 + t * dy
    return hypot(px - qx, py - qy) <= rad
}

private func segmentsIntersect(
    a1x: CGFloat, a1y: CGFloat, a2x: CGFloat, a2y: CGFloat,
    b1x: CGFloat, b1y: CGFloat, b2x: CGFloat, b2y: CGFloat
) -> Bool {
    let d = (a2x - a1x) * (b2y - b1y) - (a2y - a1y) * (b2x - b1x)
    if abs(d) < 1e-9 { return false }
    let t = ((b1x - a1x) * (b2y - b1y) - (b1y - a1y) * (b2x - b1x)) / d
    let u = ((b1x - a1x) * (a2y - a1y) - (b1y - a1y) * (a2x - a1x)) / d
    return t >= 0 && t <= 1 && u >= 0 && u <= 1
}

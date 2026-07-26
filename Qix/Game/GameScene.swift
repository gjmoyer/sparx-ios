//
//  GameScene.swift
//  Qix
//
//  Root SpriteKit scene — full game loop ported from Sparx `main.js`.
//

import SpriteKit
import UIKit

final class GameScene: SKScene {
    // MARK: - Constants

    private let cellSize: CGFloat = 4
    private let deathHoldDuration: CGFloat = 0.95
    private let respawnDuration: CGFloat = 0.85
    private let levelClearHold: CGFloat = 2.6
    private let levelIntroHold: CGFloat = 1.8

    /// TEMP: testing levels — set `false` before shipping.
    private let unlimitedLives = true

    // MARK: - World

    private var field: Playfield?
    private var helices: [Helix] = []
    private var helixNodes: [HelixNode] = []
    private var player: Player?
    private var cinderPack: CinderPack?
    private let sparks = SparkField()
    private let input = InputState()
    private let audio = AudioManager.shared
    private var levelConfig = LevelConfig.forLevel(1)

    private var isConfigured = false

    // MARK: - Meta

    private var score: Int = 0
    private var highScore: Int = HighScoreStore.highScore
    private var lives: Int = 3
    private var level: Int = 1
    private var scoreMult: Int = 1
    /// True when this run set a new personal best (shown on game over).
    private var isNewHighScore = false

    private var statusMsg = "CLAIM"
    private var statusTimer: CGFloat = 0
    private var levelClear = false
    private var deathHold: CGFloat = 0
    private var pendingReform = false
    private var reforming = false
    private var gameOverAge: CGFloat?
    private var banner: BannerState?

    /// Edge-detect fuse for looped SFX (no draw hum — original Qix is silent while drawing).
    private var wasFuseLit = false

    // MARK: - Nodes

    private let playfieldNode = PlayfieldNode()
    private let playerNode = PlayerNode()
    private let cinderNode = CinderNode()
    private let sparkNode = SparkNode()
    private var touchControls: TouchControlsNode?

    private var hudBrand: SKLabelNode?
    private var hudStats: SKLabelNode?
    private var hudState: SKLabelNode?
    private var hudHint: SKLabelNode?
    private var bannerRoot: SKNode?
    private var gameOverRoot: SKNode?

    private var lastUpdateTime: TimeInterval = 0
    private var hudAccum: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = .zero
        scaleMode = .resizeFill

        let w = max(size.width, view.bounds.width)
        let h = max(size.height, view.bounds.height)
        if w > 1, h > 1, size.width != w || size.height != h {
            size = CGSize(width: w, height: h)
        }

        configureIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isConfigured else { return }
        guard size.width > 1, size.height > 1 else { return }

        let dw = abs(size.width - oldSize.width)
        let dh = abs(size.height - oldSize.height)
        // iPad Stage Manager / safe-area flicker can fire tiny size changes while
        // the thumb is on the stick. Ignore noise — only rebuild on real resizes
        // (rotation, split-view if ever enabled, large window drag).
        guard dw >= 24 || dh >= 24 else {
            layoutControls()
            layoutHUD()
            return
        }

        startLevel(level, keepScore: true, intro: false)
        layoutControls()
        layoutHUD()
    }

    private func configureIfNeeded() {
        guard size.width > 1, size.height > 1 else { return }

        if !isConfigured {
            field = Playfield(width: size.width, height: size.height, cellSize: cellSize)
            player = Player(field: field!)
            cinderPack = CinderPack(field: field!)

            addChild(playfieldNode)
            playfieldNode.bind(field!)

            addChild(playerNode)
            addChild(cinderNode)
            addChild(sparkNode)

            let controls = TouchControlsNode(input: input)
            addChild(controls)
            touchControls = controls
            layoutControls()

            buildHUD()
            isConfigured = true
            startLevel(1, keepScore: false, intro: true)
        } else {
            startLevel(level, keepScore: true, intro: false)
            layoutControls()
            layoutHUD()
        }
    }

    private func layoutControls() {
        let insets = view?.safeAreaInsets ?? .zero
        touchControls?.layout(sceneSize: size, safeInsets: insets)
    }

    // MARK: - Audio hooks

    private func updateGameplayAudio(player: Player) {
        // Silent while drawing (classic). Fuse only when lit.
        if player.fuseLit {
            if !wasFuseLit { audio.startFuse() }
            wasFuseLit = true
        } else if wasFuseLit {
            audio.stopFuse()
            wasFuseLit = false
        }

        updateQixAudio(player: player)
    }

    private func updateQixAudio(player: Player) {
        guard let primary = helices.first else { return }
        // Drive from the most active helix (highest endpoint speed); dual-helix blends mid.
        var best = primary
        for h in helices.dropFirst() {
            if h.endpointSpeed > best.endpointSpeed { best = h }
        }
        var mid = best.mid
        if helices.count > 1 {
            let m2 = helices[1].mid
            mid = CGPoint(x: (mid.x + m2.x) * 0.5, y: (mid.y + m2.y) * 0.5)
        }
        audio.updateQix(
            mid: mid,
            player: player.position,
            screenWidth: size.width,
            mode: best.mode,
            segmentLength: best.segmentLength,
            minLen: best.minLen,
            maxLen: best.maxLen,
            omega: best.angularRate,
            endpointSpeed: best.endpointSpeed,
            endpointSpeedDelta: best.endpointSpeedDelta
        )
    }

    // MARK: - Level

    private func startLevel(_ lvl: Int, keepScore: Bool, intro: Bool) {
        guard let field, let player, let cinderPack else { return }

        level = max(1, lvl)
        levelConfig = LevelConfig.forLevel(level)

        if !keepScore {
            score = 0
            lives = 3
            scoreMult = 1
            isNewHighScore = false
            highScore = HighScoreStore.highScore
        }

        field.resize(width: size.width, height: size.height)
        playfieldNode.bind(field)
        spawnHelices()
        player.reset()
        sparks.clear()
        cinderPack.spawn(
            count: levelConfig.cinderCount,
            superMode: levelConfig.superCinder,
            speed: 16 + CGFloat(level) * 0.9
        )

        deathHold = 0
        pendingReform = false
        reforming = false
        levelClear = false
        gameOverAge = nil
        wasFuseLit = false
        input.clear()
        touchControls?.syncFromInput()
        syncHelixBounds()
        playfieldNode.refresh(force: true)

        audio.prepare()
        audio.stopFuse()

        if intro {
            banner = BannerState(
                kind: .intro,
                age: 0,
                maxAge: levelIntroHold,
                title: "LEVEL \(level)",
                sub: levelConfig.name,
                detail: levelConfig.tagline,
                accent: levelConfig.accent,
                nextLevel: nil
            )
            statusMsg = levelConfig.name
            statusTimer = levelIntroHold
            // Start jingle + Qix presence for the stage.
            audio.playStart()
            audio.startQix()
        } else {
            banner = nil
            statusMsg = "CLAIM"
            statusTimer = 0.5
            audio.startQix()
        }
        layoutHUD()
    }

    private func fullRestart() {
        startLevel(1, keepScore: false, intro: true)
    }

    private func spawnHelices() {
        guard let field else { return }
        helixNodes.forEach { $0.removeFromParent() }
        helixNodes.removeAll()
        helices.removeAll()

        let n = max(1, levelConfig.helixCount)
        for i in 0..<n {
            let helix = Helix(size: size)
            helix.setDifficulty(levelConfig.helixDifficulty)
            if n == 1 {
                helix.placeNear(x: size.width * 0.5, y: size.height * 0.45, spread: 100)
            } else {
                let x = size.width * (0.35 + CGFloat(i) * 0.3)
                let y = size.height * (0.4 + CGFloat(i % 2) * 0.12)
                helix.placeNear(x: x, y: y, spread: 70)
            }
            if let b = field.unclaimedPixelBounds() {
                helix.setBounds(b)
            }
            helices.append(helix)

            let node = HelixNode(helix: helix)
            node.showsModeLabel = false
            addChild(node)
            helixNodes.append(node)
        }
    }

    private func syncHelixBounds() {
        let b = field?.unclaimedPixelBounds()
        for helix in helices {
            helix.setBounds(b)
        }
    }

    // MARK: - Claims / clear

    private func onClaimComplete(path: [GridCell], slow: Bool) {
        guard let field else { return }
        audio.stopFuse()
        wasFuseLit = false

        let mids = helices.map(\.mid)
        let result = field.completeClaim(pathCells: path, helixPoints: mids, slow: slow)
        let cells = result.gained
        let pts = Int(CGFloat(cells) * (slow ? 4 : 2) * CGFloat(scoreMult))
        score += pts
        recordScoreIfBest()
        // Closing next to existing fills can leave the marker inside claimed
        // mass with no walkable exits — always free them onto the shoreline.
        player?.ensureOnWalkableBoundary()
        syncHelixBounds()
        playfieldNode.refresh(force: true)

        // Original Qix rewards the fill, not the draw stroke.
        audio.playClaim(slow: slow)

        statusMsg = slow ? "SLOW +\(pts)" : "FAST +\(pts)"
        statusTimer = 1.0

        if result.split && levelConfig.helixCount >= 2 {
            let prev = scoreMult
            scoreMult = min(9, scoreMult + 1)
            triggerLevelClear(
                reason: .split,
                bonus: 0,
                detail: prev < scoreMult ? "SPLIT! SCORE ×\(scoreMult)" : "SPLIT CLEAR"
            )
            return
        }

        if result.percent >= CGFloat(levelConfig.threshold) {
            let over = Int(result.percent) - levelConfig.threshold
            let bonus = Int(CGFloat(over) * CGFloat(levelConfig.overThresholdBonus) * CGFloat(scoreMult))
            score += max(0, bonus)
            recordScoreIfBest()
            triggerLevelClear(
                reason: .fill,
                bonus: max(0, bonus),
                detail: over > 0
                    ? String(format: "%.0f%%  +%d BONUS", result.percent, bonus)
                    : String(format: "%.0f%% CLEAR", result.percent)
            )
        }
    }

    private enum ClearReason { case fill, split }

    private func triggerLevelClear(reason: ClearReason, bonus: Int, detail: String) {
        guard !levelClear else { return }
        levelClear = true
        audio.playStageClear()

        if LevelConfig.bonusLifeOnClear(levelJustCleared: level) {
            lives += 1
        }

        for q in helices {
            sparks.burst(at: q.mid, count: 40, speedMin: 80, speedMax: 320)
        }
        sparks.pulseRings(at: CGPoint(x: size.width * 0.5, y: size.height * 0.5))

        banner = BannerState(
            kind: .clear,
            age: 0,
            maxAge: levelClearHold,
            title: reason == .split ? "SPLIT!" : "LEVEL CLEAR",
            sub: levelConfig.name,
            detail: detail,
            accent: levelConfig.accent,
            nextLevel: level + 1
        )
        statusMsg = "LEVEL CLEAR"
        statusTimer = levelClearHold
    }

    private func advanceLevel() {
        startLevel(level + 1, keepScore: true, intro: true)
    }

    // MARK: - Death / reform

    private func killPlayer() {
        guard let player, player.alive, !reforming, !levelClear else { return }
        let px = player.x
        let py = player.y
        player.kill()
        if !unlimitedLives {
            lives -= 1
        }
        audio.playMissRestart()
        wasFuseLit = false
        sparks.burst(at: CGPoint(x: px, y: py), count: 110, speedMin: 140, speedMax: 580)
        cinderPack?.resetAfterPlayerHit()
        deathHold = deathHoldDuration
        let stillAlive = unlimitedLives || lives > 0
        pendingReform = stillAlive
        reforming = false
        if stillAlive {
            statusMsg = "HIT!"
            statusTimer = deathHoldDuration + respawnDuration
            gameOverAge = nil
        } else {
            statusMsg = "GAME OVER"
            statusTimer = 99
            gameOverAge = -deathHoldDuration * 0.55
            recordScoreIfBest()
            audio.stopAllLoops()
        }
    }

    /// Persist score if it beats the on-device high score.
    private func recordScoreIfBest() {
        let previous = highScore
        highScore = HighScoreStore.submit(score)
        if score > previous {
            isNewHighScore = true
        }
    }

    private func beginReform() {
        guard let player else { return }
        pendingReform = false
        reforming = true
        player.respawnAt(c: player.spawnC, r: player.spawnR)
        sparks.reform(at: player.position, count: 80)
        sparks.pulseRings(at: player.position)
        statusMsg = "REFORM"
        statusTimer = respawnDuration
    }

    private func finishReform() {
        reforming = false
        player?.respawnT = nil
        cinderPack?.thawAfterRespawn()
        statusMsg = "CLAIM"
        statusTimer = 0.6
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        guard isConfigured, let field, let player, let cinderPack else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        var dt = CGFloat(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        dt = min(dt, 0.05)
        let time = currentTime

        if statusTimer > 0 && statusTimer < 90 {
            statusTimer -= dt
        }
        sparks.update(dt: dt)

        if let age = gameOverAge {
            gameOverAge = age + dt
        }

        if var b = banner {
            b.age += dt
            banner = b
            if b.age >= b.maxAge {
                if b.kind == .clear {
                    banner = nil
                    advanceLevel()
                    return
                } else {
                    banner = nil
                }
            }
        }

        if deathHold > 0 {
            deathHold -= dt
            if deathHold <= 0 && pendingReform {
                beginReform()
            }
        }

        if reforming, let t = player.respawnT {
            player.respawnT = min(1, t + dt / respawnDuration)
            if (player.respawnT ?? 0) >= 1 {
                finishReform()
            }
        }

        let introLock = banner?.kind == .intro
        let canPlay =
            player.alive
            && !levelClear
            && !reforming
            && deathHold <= 0
            && !introLock
            && (unlimitedLives || lives > 0)

        if canPlay {
            let result = player.update(input: input, dt: dt) { [weak self] path, slow in
                self?.onClaimComplete(path: path, slow: slow)
            }
            if result.fuseHit {
                killPlayer()
            }

            if player.alive {
                for q in helices {
                    q.setPlayer(player.position)
                    q.update(dt: dt)
                    q.resolveClaimed(
                        isClaimed: { x, y in
                            let cell = field.pixelToCell(x: x, y: y)
                            return field.isClaimed(c: cell.c, r: cell.r)
                        },
                        nearestUnclaimed: { x, y in
                            let cell = field.pixelToCell(x: x, y: y)
                            guard let near = field.nearestUnclaimed(c: cell.c, r: cell.r) else {
                                return nil
                            }
                            return field.cellToPixel(c: near.c, r: near.r)
                        }
                    )
                }
                syncHelixBounds()
                updateGameplayAudio(player: player)

                if cinderPack.update(dt: dt, player: player) {
                    killPlayer()
                }

                if player.alive && player.drawing && player.path.count > 1 {
                    for q in helices {
                        let seg = q.segment
                        if field.helixHitsPath(
                            x1: seg.x1, y1: seg.y1, x2: seg.x2, y2: seg.y2,
                            path: player.path
                        ) {
                            killPlayer()
                            break
                        }
                    }
                }
            }
        } else {
            // Not in active play — stop fuse; keep Qix unless game over.
            if wasFuseLit {
                audio.stopFuse()
                wasFuseLit = false
            }
            if deathHold <= 0 && !levelClear {
                for q in helices {
                    q.update(dt: dt)
                    q.resolveClaimed(
                        isClaimed: { x, y in
                            let cell = field.pixelToCell(x: x, y: y)
                            return field.isClaimed(c: cell.c, r: cell.r)
                        },
                        nearestUnclaimed: { x, y in
                            let cell = field.pixelToCell(x: x, y: y)
                            guard let near = field.nearestUnclaimed(c: cell.c, r: cell.r) else {
                                return nil
                            }
                            return field.cellToPixel(c: near.c, r: near.r)
                        }
                    )
                }
                if player.alive {
                    _ = cinderPack.update(dt: dt, player: player)
                }
                updateQixAudio(player: player)
            } else if levelClear {
                for q in helices {
                    q.update(dt: dt * 0.5)
                }
                updateQixAudio(player: player)
            }
        }

        // Render
        playfieldNode.refresh()
        for (i, _) in helices.enumerated() {
            if i < helixNodes.count { helixNodes[i].refresh() }
        }
        cinderNode.refresh(pack: cinderPack, time: time)
        playerNode.refresh(player: player, time: time)
        sparkNode.refresh(sparks)

        refreshBanner(time: time)
        refreshGameOver(time: time)

        hudAccum += dt
        if hudAccum > 0.08 {
            hudAccum = 0
            updateHUD()
        }
    }

    // MARK: - HUD / banners

    private func buildHUD() {
        hudBrand?.removeFromParent()
        hudStats?.removeFromParent()
        hudState?.removeFromParent()
        hudHint?.removeFromParent()

        let brand = SKLabelNode(fontNamed: "Menlo-Bold")
        brand.fontSize = 14
        brand.fontColor = UIColor(red: 0.24, green: 1, blue: 0.42, alpha: 1)
        brand.horizontalAlignmentMode = .left
        brand.verticalAlignmentMode = .center
        brand.zPosition = 200
        brand.text = "SPARX "
        addChild(brand)
        hudBrand = brand

        let stats = SKLabelNode(fontNamed: "Menlo")
        stats.fontSize = 11
        stats.fontColor = UIColor(white: 0.8, alpha: 1)
        stats.horizontalAlignmentMode = .left
        stats.verticalAlignmentMode = .center
        stats.zPosition = 200
        addChild(stats)
        hudStats = stats

        let state = SKLabelNode(fontNamed: "Menlo-Bold")
        state.fontSize = 12
        state.fontColor = UIColor(red: 0.30, green: 0.88, blue: 1, alpha: 1)
        state.horizontalAlignmentMode = .right
        state.verticalAlignmentMode = .center
        state.zPosition = 200
        addChild(state)
        hudState = state

        // Controls hint — top bar, right side (same place as JS #hud .hint)
        let hint = SKLabelNode(fontNamed: "Menlo")
        hint.fontSize = 10
        hint.fontColor = UIColor(white: 0.4, alpha: 1)
        hint.horizontalAlignmentMode = .right
        hint.verticalAlignmentMode = .center
        hint.zPosition = 200
        hint.text = "Stick move · tap FAST/SLOW to arm · WASD + Space/Shift"
        addChild(hint)
        hudHint = hint

        layoutHUD()
    }

    private func layoutHUD() {
        let insets = view?.safeAreaInsets ?? .zero
        let top = size.height - max(insets.top, 8) - 16
        hudBrand?.position = CGPoint(x: 14, y: top)
        // Sit stats after the brand glyph width so "SPARX" and "L1" don't collide.
        let brandWidth = hudBrand?.frame.width ?? 52
        hudStats?.position = CGPoint(x: 14 + brandWidth + 8, y: top)
        // Status left of hint; both top-right like the JS HUD
        hudHint?.position = CGPoint(x: size.width - 14, y: top - 16)
        hudState?.position = CGPoint(x: size.width - 14, y: top)
    }

    private func updateHUD() {
        guard let field else { return }
        let pct = field.percent()
        let livesText = unlimitedLives ? "∞" : "\(max(0, lives))"
        hudStats?.text = String(
            format: "L%d  SCR %d  ×%d  %.0f%%/%d%%  ♥%@",
            level, score, scoreMult, pct, levelConfig.threshold, livesText
        )

        var label = ""
        if statusTimer > 0 { label = statusMsg }
        else if reforming { label = "REFORM" }
        else if player?.drawing == true {
            label = player?.slow == true ? "DRAW SLOW" : "DRAW FAST"
        } else if player?.fuseLit == true {
            label = "FUSE"
        }
        hudState?.text = label
    }

    private func refreshBanner(time: TimeInterval) {
        bannerRoot?.removeFromParent()
        bannerRoot = nil
        guard let banner else { return }

        let t = banner.age
        let enter = min(1, t / 0.35)
        let ease = enter * enter * (3 - 2 * enter)
        let exit: CGFloat =
            banner.age > banner.maxAge - 0.35
            ? max(0, (banner.maxAge - banner.age) / 0.35)
            : 1
        let alpha = ease * exit
        guard alpha > 0.01 else { return }

        let root = SKNode()
        root.zPosition = 300
        root.alpha = alpha

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.5), size: size)
        dim.anchorPoint = .zero
        dim.position = .zero
        root.addChild(dim)

        let cx = size.width * 0.5
        let cy = size.height * 0.52
        let hover = sin(time * 1.6) * 6

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = banner.title
        title.fontSize = banner.kind == .clear ? 36 : 28
        title.fontColor = banner.kind == .clear ? .white : banner.accent
        title.position = CGPoint(x: cx, y: cy + hover)
        title.verticalAlignmentMode = .center
        root.addChild(title)

        let sub = SKLabelNode(fontNamed: "Menlo")
        sub.text = banner.sub
        sub.fontSize = 14
        sub.fontColor = UIColor(red: 0.8, green: 1, blue: 0.8, alpha: 1)
        sub.position = CGPoint(x: cx, y: cy + hover - 32)
        sub.verticalAlignmentMode = .center
        root.addChild(sub)

        if let detail = banner.detail {
            let d = SKLabelNode(fontNamed: "Menlo")
            d.text = detail
            d.fontSize = 11
            d.fontColor = UIColor(white: 0.55, alpha: 1)
            d.position = CGPoint(x: cx, y: cy + hover - 52)
            d.verticalAlignmentMode = .center
            root.addChild(d)
        }

        if banner.kind == .clear, let next = banner.nextLevel {
            let n = SKLabelNode(fontNamed: "Menlo-Bold")
            n.text = "→ LEVEL \(next)"
            n.fontSize = 13
            n.fontColor = banner.accent
            n.alpha = 0.5 + 0.5 * sin(time * 3)
            n.position = CGPoint(x: cx, y: cy + hover - 78)
            n.verticalAlignmentMode = .center
            root.addChild(n)
        }

        addChild(root)
        bannerRoot = root
    }

    private func refreshGameOver(time: TimeInterval) {
        gameOverRoot?.removeFromParent()
        gameOverRoot = nil
        guard let age = gameOverAge, age >= 0, lives <= 0 else { return }

        let enter = min(1, age / 0.7)
        let ease = enter * enter * (3 - 2 * enter)
        let root = SKNode()
        root.zPosition = 320
        root.alpha = ease

        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.45), size: size)
        dim.anchorPoint = .zero
        root.addChild(dim)

        let cx = size.width * 0.5
        let cy = size.height * 0.5
        let hoverY = sin(time * 1.35) * 10

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "GAME OVER"
        title.fontSize = min(48, size.width * 0.1)
        title.fontColor = UIColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)
        title.position = CGPoint(x: cx, y: cy + hoverY)
        title.verticalAlignmentMode = .center
        root.addChild(title)

        let sub = SKLabelNode(fontNamed: "Menlo")
        sub.text = "SCORE \(score)  ·  LEVEL \(level)"
        sub.fontSize = 13
        sub.fontColor = UIColor(red: 0.8, green: 1, blue: 0.8, alpha: 1)
        sub.position = CGPoint(x: cx, y: cy + hoverY - 48)
        sub.verticalAlignmentMode = .center
        root.addChild(sub)

        let best = SKLabelNode(fontNamed: "Menlo-Bold")
        if isNewHighScore {
            best.text = "NEW HIGH SCORE  \(highScore)"
            best.fontColor = UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        } else {
            best.text = "HIGH SCORE  \(highScore)"
            best.fontColor = UIColor(white: 0.7, alpha: 1)
        }
        best.fontSize = 14
        best.position = CGPoint(x: cx, y: cy + hoverY - 74)
        best.verticalAlignmentMode = .center
        root.addChild(best)

        let hint = SKLabelNode(fontNamed: "Menlo")
        hint.text = "TAP TO RESTART"
        hint.fontSize = 12
        hint.fontColor = UIColor(white: 0.55, alpha: 1)
        hint.alpha = 0.65 + 0.35 * sin(time * 2.8)
        hint.position = CGPoint(x: cx, y: cy + hoverY - 100)
        hint.verticalAlignmentMode = .center
        root.addChild(hint)

        addChild(root)
        gameOverRoot = root
    }

    /// Called from the view controller after safe-area insets settle.
    func relayoutControlsForSafeArea() {
        layoutControls()
    }

    // MARK: - Game-over restart touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Controls handle their own touches via isUserInteractionEnabled.
        // Restart on game over when tapping outside controls.
        if lives <= 0, gameOverAge != nil, (gameOverAge ?? 0) >= 0 {
            fullRestart()
        }
    }

    // MARK: - Keyboard (forwarded from GameViewController)

    func handlePresses(_ presses: Set<UIPress>, down: Bool) {
        for press in presses {
            guard let key = press.key else { continue }
            if mapKey(key, down: down) { continue }
            if down, lives <= 0,
               key.charactersIgnoringModifiers == "r" || key.charactersIgnoringModifiers == "R"
            {
                fullRestart()
            }
        }
    }

    @discardableResult
    private func mapKey(_ key: UIKey, down: Bool) -> Bool {
        let action: InputAction?
        switch key.keyCode {
        case .keyboardUpArrow, .keyboardW: action = .up
        case .keyboardDownArrow, .keyboardS: action = .down
        case .keyboardLeftArrow, .keyboardA: action = .left
        case .keyboardRightArrow, .keyboardD: action = .right
        case .keyboardSpacebar, .keyboardZ: action = .slow
        case .keyboardLeftShift, .keyboardRightShift, .keyboardX: action = .fast
        default: action = nil
        }
        guard let action else { return false }
        if action.isDrawMode {
            // Keyboard draw is hold-to-draw (easy to chord with arrows).
            if down {
                input.pressKeyboardDraw(action)
            } else {
                input.releaseKeyboardDraw(action)
            }
            touchControls?.syncFromInput()
        } else {
            if down { input.press(action) } else { input.release(action) }
        }
        return true
    }
}

// MARK: - Banner

private struct BannerState {
    enum Kind { case intro, clear }
    var kind: Kind
    var age: CGFloat
    var maxAge: CGFloat
    var title: String
    var sub: String
    var detail: String?
    var accent: UIColor
    var nextLevel: Int?
}

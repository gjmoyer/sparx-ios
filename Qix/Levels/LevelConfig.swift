//
//  LevelConfig.swift
//  Qix
//
//  Level design — ported from Sparx `levels.js`.
//  Scaffold now; fully wired when playfield / player land.
//
//  Classic arcade (Taito 1981) rough rules:
//  - Endless score-attack levels
//  - Clear at ~75% claimed
//  - Levels 1–2: single Helix
//  - Level 3+: two Helices; alternate clear by splitting them
//  - Splitting builds a permanent score multiplier (up to ×9)
//  - More Cinders over time; later Super Cinders that chase open Stix
//

import Foundation
import UIKit

struct LevelConfig: Sendable, Equatable {
    var level: Int
    var name: String
    var accent: UIColor
    /// Percent of playfield that must be claimed to clear.
    var threshold: Int
    var helixCount: Int
    var cinderCount: Int
    var superCinder: Bool
    /// Helix motion scale.
    var speed: CGFloat
    var aggression: CGFloat
    var omegaScale: CGFloat
    /// Bonus points per 1% over threshold (× score multiplier applied in game).
    var overThresholdBonus: Int
    var tagline: String

    var helixDifficulty: HelixDifficulty {
        HelixDifficulty(speed: speed, aggression: aggression, omegaScale: omegaScale)
    }

    static func forLevel(_ level: Int) -> LevelConfig {
        let n = max(1, level)

        // Classic: dual Helix from level 3
        let helixCount = n < 3 ? 1 : 2

        // L1: 70, L2: 75, L3: 75, then +1 every 2 levels, cap 85
        let threshold: Int
        if n == 1 {
            threshold = 70
        } else if n == 2 {
            threshold = 75
        } else {
            threshold = min(85, 75 + (n - 3) / 2)
        }

        // Cinders: none on L1, then ramp
        let cinderCount: Int
        if n == 1 {
            cinderCount = 0
        } else if n <= 3 {
            cinderCount = 2
        } else if n == 4 {
            cinderCount = 3
        } else {
            cinderCount = min(6, 2 + n / 2)
        }

        let superCinder = n >= 5
        let speed = 1 + CGFloat(n - 1) * 0.08
        let aggression = min(0.55, 0.22 + CGFloat(n - 1) * 0.04)
        let omegaScale = 1 + CGFloat(n - 1) * 0.06

        return LevelConfig(
            level: n,
            name: stageNames[(n - 1) % stageNames.count],
            accent: accentForLevel(n),
            threshold: threshold,
            helixCount: helixCount,
            cinderCount: cinderCount,
            superCinder: superCinder,
            speed: speed,
            aggression: aggression,
            omegaScale: omegaScale,
            overThresholdBonus: 1000,
            tagline: taglineFor(n: n, helixCount: helixCount, cinders: cinderCount, superS: superCinder)
        )
    }

    /// Extra life every 3 clears starting after level 3.
    static func bonusLifeOnClear(levelJustCleared: Int) -> Bool {
        levelJustCleared >= 3 && levelJustCleared % 3 == 0
    }
}

// MARK: - Private tables

private let stageNames = [
    "AWAKENING",
    "HUNT",
    "TWIN HELIX",
    "SPARK STORM",
    "PREDATOR",
    "DOUBLE FAULT",
    "NEON PIT",
    "OVERCLOCK",
    "VOID DANCE",
    "APEX",
]

private func accentForLevel(_ n: Int) -> UIColor {
    let accents: [UIColor] = [
        UIColor(red: 0.24, green: 1.0, blue: 0.42, alpha: 1),   // green classic
        UIColor(red: 0.30, green: 0.88, blue: 1.0, alpha: 1),   // cyan
        UIColor(red: 1.0, green: 0.42, blue: 0.84, alpha: 1),   // pink dual
        UIColor(red: 1.0, green: 0.80, blue: 0.27, alpha: 1),   // gold storm
        UIColor(red: 1.0, green: 0.35, blue: 0.09, alpha: 1),   // orange predator
        UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1),  // violet
        UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),  // neon
        UIColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 1),  // hot
        UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1),  // steel void
        UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1),  // apex gold
    ]
    return accents[(n - 1) % accents.count]
}

private func taglineFor(n: Int, helixCount: Int, cinders: Int, superS: Bool) -> String {
    if n == 1 { return "Claim the pit. Stay off the Stix." }
    if n == 2 { return "Cinders patrol the edges. Don't get pinched." }
    if n == 3 { return "Two Helices. Fill 75% — or split them for a multiplier." }
    if superS { return "Super Cinders can hunt your open line." }
    if helixCount >= 2 { return "Twin hunters. Split or smother." }
    if cinders >= 3 { return "Edges are crowded. Cut fast." }
    return "Push past the threshold for bonus points."
}

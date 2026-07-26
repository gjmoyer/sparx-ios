//
//  HelixMode.swift
//  Qix
//
//  Behavioral modes for the roaming Helix (classic Qix entity).
//

import Foundation

/// AI state machine for Helix motion.
///
/// - `wander`: free-end sweep around lagging pivot + meander (default prowl)
/// - `loiter`: short pause with slowed sweep so the rainbow fan stays open
/// - `lunge`: asymmetric charge toward player or playfield center
enum HelixMode: String, Sendable, CaseIterable {
    case wander
    case loiter
    case lunge

    var label: String { rawValue.uppercased() }
}

/// Difficulty knobs applied per level (from `LevelConfig`).
struct HelixDifficulty: Sendable, Equatable {
    /// Multiplier on dt for mode timers and integration.
    var speed: CGFloat
    /// Bias toward lunges at the player (0…~0.55).
    var aggression: CGFloat
    /// Scale for angular sweep rate.
    var omegaScale: CGFloat

    static let standard = HelixDifficulty(speed: 1, aggression: 0.25, omegaScale: 1)
}

/// Live segment sample stored in the delayed afterimage trail.
struct HelixSegment: Sendable, Equatable {
    var x1: CGFloat
    var y1: CGFloat
    var x2: CGFloat
    var y2: CGFloat

    var a: CGPoint { CGPoint(x: x1, y: y1) }
    var b: CGPoint { CGPoint(x: x2, y: y2) }

    init(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    init(a: CGPoint, b: CGPoint) {
        self.x1 = a.x
        self.y1 = a.y
        self.x2 = b.x
        self.y2 = b.y
    }
}

/// Which endpoint currently leads the asymmetric wedge fan.
enum HelixLead: String, Sendable {
    case a
    case b

    mutating func toggle() {
        self = self == .a ? .b : .a
    }
}

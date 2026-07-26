//
//  HighScoreStore.swift
//  Qix
//
//  Persists the all-time high score on-device (survives app unload).
//

import Foundation

enum HighScoreStore {
    private static let key = "sparx.highScore"

    static var highScore: Int {
        max(0, UserDefaults.standard.integer(forKey: key))
    }

    /// Updates the stored high score if `score` is higher. Returns the (possibly new) high score.
    @discardableResult
    static func submit(_ score: Int) -> Int {
        let previous = highScore
        let best = max(previous, max(0, score))
        if best > previous {
            UserDefaults.standard.set(best, forKey: key)
        }
        return best
    }
}

//
//  InputState.swift
//  Qix
//
//  Shared input actions for player movement and draw modes.
//
//  Draw modes (slow/fast) can be sticky toggles so the Simulator mouse
//  does not need two simultaneous button presses.
//

import Foundation

enum InputAction: String, Hashable, Sendable, CaseIterable {
    case up
    case down
    case left
    case right
    case slow
    case fast

    var isDrawMode: Bool {
        self == .slow || self == .fast
    }

    var isDirection: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}

/// Held-action set, updated by on-screen controls / keyboard.
final class InputState {
    private(set) var held: Set<InputAction> = []

    /// Draw modes latched by on-screen toggle (tap SLOW/FAST).
    /// Keyboard still uses momentary hold via `press`/`release`.
    private(set) var stickyDraw: InputAction?

    func press(_ action: InputAction) {
        held.insert(action)
    }

    func release(_ action: InputAction) {
        // Sticky draw is not cleared by finger-up on the D-pad.
        if action.isDrawMode, stickyDraw == action { return }
        held.remove(action)
    }

    /// Tap SLOW or FAST: arm that draw mode, or disarm if already selected.
    /// Exclusive — only one draw mode active at a time.
    func toggleStickyDraw(_ action: InputAction) {
        guard action.isDrawMode else { return }
        if stickyDraw == action {
            stickyDraw = nil
            held.remove(.slow)
            held.remove(.fast)
        } else {
            stickyDraw = action
            held.remove(.slow)
            held.remove(.fast)
            held.insert(action)
        }
    }

    /// Momentary keyboard draw (Space / Shift) overrides sticky until key up,
    /// then sticky is restored if still set.
    func pressKeyboardDraw(_ action: InputAction) {
        guard action.isDrawMode else {
            press(action)
            return
        }
        held.remove(.slow)
        held.remove(.fast)
        held.insert(action)
    }

    func releaseKeyboardDraw(_ action: InputAction) {
        guard action.isDrawMode else {
            release(action)
            return
        }
        held.remove(action)
        // Restore sticky latch if user still has one armed.
        if let sticky = stickyDraw {
            held.insert(sticky)
        }
    }

    /// Replace orthogonal direction from a virtual stick (or clear when neutral).
    func setDirection(_ action: InputAction?) {
        held.remove(.up)
        held.remove(.down)
        held.remove(.left)
        held.remove(.right)
        if let action, action.isDirection {
            held.insert(action)
        }
    }

    func clear() {
        held.removeAll()
        stickyDraw = nil
    }

    var isDrawingHeld: Bool {
        held.contains(.slow) || held.contains(.fast)
    }

    var activeDrawMode: InputAction? {
        if held.contains(.fast) { return .fast }
        if held.contains(.slow) { return .slow }
        return stickyDraw
    }
}

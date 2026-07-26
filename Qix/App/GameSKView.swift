//
//  GameSKView.swift
//  Qix
//
//  SKView that opts out of the UIKit focus engine.
//  Default SKView implements focusItems(in:) for tvOS/keyboard focus; on iPad
//  that logs "caching for linear focus movement is limited" for the whole time
//  the view is on screen. Touch games don't need focus navigation.
//

import SpriteKit
import UIKit

final class GameSKView: SKView {
    override var canBecomeFocused: Bool { false }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        // No-op — never participate in focus movement.
    }

    /// Empty focus items: disables linear focus caching over the full game view.
    override func focusItems(in rect: CGRect) -> [any UIFocusItem] {
        []
    }
}

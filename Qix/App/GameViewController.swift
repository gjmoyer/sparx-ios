//
//  GameViewController.swift
//  Qix
//
//  UIKit host for SpriteKit — preferred over SwiftUI `SpriteView` so scene
//  setup runs against a real `SKView` bounds (avoids early size / IUO crashes).
//
//  iPad notes:
//  - Defers edge system gestures so the virtual stick near the bezel doesn't
//    start multitasking / home / Control Center.
//  - Ignores sub-point layout jitter that would otherwise resize the scene mid-drag.
//  - Uses GameSKView to stay out of the UIKit focus engine (quiets SKView warnings).
//

import SpriteKit
import UIKit

final class GameViewController: UIViewController {
    private var skView: GameSKView { view as! GameSKView }
    private var gameScene: GameScene?

    /// Last size we applied to the scene (rounded) — ignore 1pt thrash.
    private var lastAppliedSize: CGSize = .zero
    private var lastAppliedInsets: UIEdgeInsets = .zero

    override func loadView() {
        let sk = GameSKView(frame: .zero)
        sk.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sk.ignoresSiblingOrder = true
        sk.showsFPS = false
        sk.showsNodeCount = false
        sk.preferredFramesPerSecond = 60
        sk.isMultipleTouchEnabled = true
        sk.isUserInteractionEnabled = true
        view = sk
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        // Warm audio engine early so the first Start / Qix cue isn't delayed.
        AudioManager.shared.prepare()
        // Re-assert gesture deferral after presentation.
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = skView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let insets = view.safeAreaInsets
        // Quantize so floating layout noise doesn't thrash the scene.
        let quantized = CGSize(
            width: bounds.width.rounded(.toNearestOrAwayFromZero),
            height: bounds.height.rounded(.toNearestOrAwayFromZero)
        )

        if gameScene == nil {
            let scene = GameScene(size: quantized)
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .black
            skView.presentScene(scene)
            gameScene = scene
            lastAppliedSize = quantized
            lastAppliedInsets = insets
            scene.relayoutControlsForSafeArea()
            return
        }

        guard let scene = gameScene else { return }

        let sizeDelta = hypot(
            quantized.width - lastAppliedSize.width,
            quantized.height - lastAppliedSize.height
        )
        let sizeChanged = sizeDelta >= 2.0
        let insetsChanged = !Self.insetsEqual(insets, lastAppliedInsets, tolerance: 1.0)

        // Only push size into the scene when it actually changed — setting
        // scene.size triggers didChangeSize → used to restart the whole level.
        if sizeChanged {
            lastAppliedSize = quantized
            if abs(scene.size.width - quantized.width) >= 2
                || abs(scene.size.height - quantized.height) >= 2
            {
                scene.size = quantized
            }
        }

        if sizeChanged || insetsChanged {
            lastAppliedInsets = insets
            scene.relayoutControlsForSafeArea()
        }
    }

    private static func insetsEqual(_ a: UIEdgeInsets, _ b: UIEdgeInsets, tolerance: CGFloat) -> Bool {
        abs(a.top - b.top) < tolerance
            && abs(a.left - b.left) < tolerance
            && abs(a.bottom - b.bottom) < tolerance
            && abs(a.right - b.right) < tolerance
    }

    // MARK: - System chrome / gestures (critical on iPad)

    override var prefersStatusBarHidden: Bool { true }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// Let the app own bottom/side swipes first so the joystick isn't stolen
    /// by home indicator, Control Center, or iPad multitasking edge drags.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    // Forward hardware keyboard into the scene (Simulator / external keyboard).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        gameScene?.handlePresses(presses, down: true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        gameScene?.handlePresses(presses, down: false)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        gameScene?.handlePresses(presses, down: false)
        super.pressesCancelled(presses, with: event)
    }
}

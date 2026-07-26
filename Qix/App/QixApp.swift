//
//  QixApp.swift
//  Qix
//
//  SwiftUI entry that hosts SpriteKit via UIViewControllerRepresentable.
//  Using SKView directly avoids SpriteView size/lifecycle races that can
//  call `didChangeSize` before the scene has finished setup.
//

import SwiftUI
import SpriteKit

@main
struct QixApp: App {
    var body: some Scene {
        WindowGroup {
            GameContainerView()
                .ignoresSafeArea()
                .statusBarHidden()
                .preferredColorScheme(.dark)
        }
    }
}

/// UIKit bridge — presents `GameViewController` / `SKView` with stable sizing.
struct GameContainerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController()
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {
        // Size is driven by Auto Layout + SKView.bounds; scene resizes in
        // `viewDidLayoutSubviews` / `didChangeSize` once configured.
    }
}

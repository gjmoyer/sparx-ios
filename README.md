# Sparx (iOS)

Sparx is a fun game inspired by the Arcade hit Qix (Taito, 1981). Native **Swift 6 / SpriteKit** implementation.

## Status

Full gameplay is implemented. **Audio is intentionally omitted** so a higher-quality sound design can be added later.

### Playable systems

- **Helix** — full wander / loiter / lunge AI, rainbow afterimage trail, length breathing
- **Playfield** — grid claims, flood-fill, permanent white walls, Helix confinement
- **Player** — boundary walk, Slow/Fast Stix draw, fuse
- **Cinders** — one-way perimeter patrol; Super Cinders from level 5 chase open Stix
- **Scoring / levels** — % clear threshold, dual-Helix split multiplier (×1–×9), lives, reform
- **Juice** — death / reform spark bursts and pulse rings
- **Controls** — on-screen D-pad + SLOW/FAST; keyboard on Simulator (WASD/arrows, Space/Z slow, Shift/X fast)

## Requirements

- Xcode 26+ (Swift 6, iOS 26 SDK)
- Deployment target: **iOS 26.0**

## Open & run

```bash
open /Users/greg/qix-ios/Qix.xcodeproj
```

Select an iPhone simulator or device, then Run (⌘R).

## How to play

1. Walk the green rim with the D-pad (or arrows / WASD).
2. Hold **SLOW** or **FAST** and move into the open pit to draw a Stix line.
3. Close the line back onto the rim to claim territory (Helix side stays open).
4. Clear the level by claiming enough % (HUD shows current / threshold), or on dual-Helix stages by **splitting** the two Helices into separate zones.
5. Avoid: Helix touching your open Stix, Cinders on the rim, and the fuse burning to you if you stop mid-draw.

## Project layout

```
Qix/
  App/              SwiftUI entry + UIKit SKView host
  Game/             GameScene, touch controls
  Core/             Geometry, Bounds, InputState
  Entities/
    Helix/          Roaming Qix entity
    Player/         Marker + Stix + fuse
    Cinder/         Edge patrol enemies
  Playfield/        Grid claims + texture renderer
  Levels/           LevelConfig
  Effects/          Spark bursts
  Audio/            Stub only (no SFX/music yet)
```



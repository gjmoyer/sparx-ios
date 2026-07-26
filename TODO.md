Cleanup before charging money

Must do
1. unlimitedLives = false — still hard-coded for testing; game over / high score barely exist in real play until this is off.
2. Playtest full life loop — death → reform → game over → high score → restart.
3. Privacy / App Store text — privacy policy URL (even a simple page: “no accounts, high score on device only”), support email, screenshots + 15–30s preview.
4. Bundle ID / signing — team, version 1.0.0, build number, release config.

Should do
5. Haptics — light tick on claim, stronger on death (big perceived polish for almost no code).
6. Mute control — Settings or long-press; audio exists, no player control.
7. First-run clarity — one short “draw to claim, avoid Helix & sparks” line (you already have a controls hint).
8. README / dead comments — drop TEMP comments, update README to Sparx ship state.
9. Performance pass on iPad — claim texture redraw is fine at phone size; watch big iPads after big fills.
10. Trap edge cases — one more long play on late levels (fills + cinders); you fixed a lot, but it’s the riskiest area.

Nice later (not required for $1.99)
• Game Center leaderboards
• Better authored SFX (replace procedural)
• Settings: left-hand stick, colorblind fills
• IAP — skip for this game

───

Honest pricing take

• Ship at $0.99 if you want fewer objections and faster first reviews.
• Ship at $1.99 if you do the must-list + haptics + a clean store listing and you feel proud of a 5-minute play session with no jank.

I’d not ask 1.99 while unlimited lives is still on and the store page is empty. After that checklist, **1.99 is defensible** for a complete niche arcade port with a distinctive Helix and local high score — not for a mass-market hit, but for the people who want exactly this game.

───

Suggested order this week
1. Flip lives off, play to game over twice
2. Haptics + mute
3. Screenshots (Helix, claim fill, dual-Helix level, game over + high score)
4. Submit at $0.99 or $1.99 — your call on confidence

If you want, next step can be: flip lives, add haptics + mute, and draft App Store description/screenshot shot list.
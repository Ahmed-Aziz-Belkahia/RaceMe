# RaceMe

iOS 26, SwiftUI, no dependencies. Open `RaceMe.xcodeproj` and run.

The project uses Xcode 16+ file-system-synchronized folders, so every `.swift` file under
`RaceMe/` compiles automatically — there is no file list in the project to keep in sync.

## Demoing it at a desk

`AppState.useSimulatedMovement` defaults to `true` in Debug and on the Simulator, so the
movement simulator stands in for GPS and the entire product is demonstrable without leaving
the room. Toggle it in **Profile → Settings → Developer** to switch to real Core Location.

Eight simulated races run on a loop from launch, so the **Live now** strip is never empty and
**Spectate** always has something in it.

To replay onboarding: delete the app, or clear `raceme.profile.v1` from `UserDefaults`.

Challenge links open with `raceme://challenge?c=<payload>` or `https://raceme.app/c/<payload>`.
Shipping the web form for real needs an `apple-app-site-association` file on that domain.

## Why this stack

Native SwiftUI is the only way to get the three things the brief made non-negotiable at once:
real `glassEffect` / `GlassEffectContainer` / `glassEffectID` morphing rather than a
hand-rolled blur, `CHHapticPattern` for custom haptic patterns rather than three canned impact
styles, and a `CADisplayLink`-driven `Canvas` that actually runs at 120Hz on ProMotion.

## Layout

```
Design/       palette, type registers, spring tokens, glass kit, ambient field, wordmark
Haptics/      the haptic vocabulary, as CoreHaptics patterns
Model/        Racer, Race, RunnerProfile, League — plain values
Simulation/   ghost runners, race engine, calibrator, movement sources, display link
Services/     protocols + mocks, live-race director, challenge links, notifications
Features/     Race · PhotoFinish · PostRace · Onboarding · Home · Spectate · Leaderboard · Profile
App/          AppState, RootView, entry point
```

## The two signature elements

**The lane** (`Features/Race/LaneView.swift`) pins the user to the centre and scrolls the world
past them, and compresses the horizontal scale with `asinh` rather than mapping it literally.
A one-metre gap gets about nine points of separation and two hundred metres still fits on
screen — close races read as close, blowouts stay legible, and the compression produces a
genuine down-the-lane perspective as a side effect.

**The photo finish** (`Features/PhotoFinish/PhotoFinish.swift`) is a real slit-scan. The
horizontal axis is time, not space, exactly as it is in a finish-line camera. Each racer's
smear is computed from the positions the engine sampled at 60Hz through the finish, so a fast
runner prints narrow and a fading one prints wide. Change the race and you get a different
picture.

## What's mocked

Everything behind `Services/Services.swift`. There is no backend, no auth, and no database —
the profile round-trips through `UserDefaults` and every service sits behind a protocol, so
real implementations drop in by changing the initialisers in `AppServices`. The UI never finds
out.

The race simulator is not mocked. `GhostRunner` integrates shaped pace curves, superlinear
fatigue, a final-400 kick, correlated (Ornstein–Uhlenbeck) noise, and scripted surges, plus a
deadzoned, lagged, late-fading pack response so leads genuinely trade without the finish
reading as rubber-banded.

## Not built

No sound, no light theme, no account creation — all three deliberate, per the brief. In-app
purchase is `MockSubscriptionService`; wiring StoreKit 2 is the one thing between this and a
build you could actually charge money in.

The app icon asset is an empty placeholder — `Assets.xcassets/AppIcon.appiconset` has the
correct 1024pt slots (including dark and tinted) but no artwork.

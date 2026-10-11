# Testing

## Automated checks

Run `bash scripts/test.sh`. The 14 XCTest cases cover mesh topology and UVs, mound contact and overlapping piles, folding and release, extreme movement, fixed steps and idle sleep, hit testing, Finder coordinate conversion, configuration round trips, vertex–triangle contact, fast crossings, edge–edge separation, and independent intersection checks in a deep fold.

GitHub Actions verifies deterministic project generation, runs the tests, builds the app, and packages it. CI does not prove graphical desktop behavior, Finder permission prompts, or GPU performance.

## Native checks

Build the app and close any running normal instance. In a graphical macOS session:

```bash
"build/Desktop Rug.app/Contents/MacOS/DesktopRug" --validate "$PWD/build/validation" --deep-fold
"build/Desktop Rug.app/Contents/MacOS/DesktopRug" --validate-ui "$PWD/build/ui-validation"
```

`--validate` uses isolated settings and deterministic test objects, saves real Metal frames, exercises folds/settling, and measures a short active render interval. `--deep-fold` adds a larger fold. `--validate-ui` captures all settings sections, checks show/reveal/lock and display selection, and verifies all four textures, saved selections, and flat/folded Metal rendering.

For real input, `--interaction-check` opens a labeled diagnostic window with explicit test mounds. `--desktop-input-check` uses the real desktop panel, ordinary saved settings, and any connected Finder. It writes counters to `/private/tmp/desktop-rug-interaction.json`; omit these flags for normal use.

Finder integration can be checked after granting Automation:

```bash
"build/Desktop Rug.app/Contents/MacOS/DesktopRug" --settings --connect-finder \
  --validate-finder "$PWD/build/finder-validation"
```

This uses real saved settings and moves the rug over a real main-display icon. It does not move the desktop files. Reports may include a personal desktop path; review them before sharing.

## Recorded local checks

Before the initial release, testing on Apple Silicon confirmed all 14 tests, actual Metal rendering, Finder integration, desktop input, show/reveal/lock behavior, persistence, and texture loading. A short Release run measured about 60 FPS. These are local observations, not guarantees for every Mac or macOS version.

Full manual coverage of Spaces, Mission Control, Stage Manager, fullscreen transitions, Intel runtime, arbitrary extreme cloth compression, and long-running leak behavior remains incomplete. The model uses approximate self-collision and shadows.

# Privacy

Desktop Rug runs locally. The app has no telemetry, analytics SDK, account system, or network client.

## Finder metadata

Finder integration is optional and uses Automation access to read desktop item names, file URLs, icon size, and desktop positions. This data is held in memory to construct collision mounds. Polling runs every two seconds while the rug is visible and stops when disconnected, hidden, or an error occurs. The Finder script performs no file writes, moves, or deletions.

The app does not capture the desktop or wallpaper and does not require Accessibility or Screen Recording permission. Native validation images are renders of the app's own cloth and settings.

## Settings

Configuration and rug position are stored locally using Codable/UserDefaults in `dev.desktoprug.app`. These include texture, dimensions, physics, visibility, display selection, Finder connection preference, and any manual mounds. Item names and URLs are not saved as part of the configuration. Deformed particle positions are not persisted.

## Explicit diagnostics

Normal launches do not write diagnostic reports. Command-line validation modes write reports to a requested directory. `--desktop-input-check` writes local interaction counters and configuration to `/private/tmp/desktop-rug-interaction.json`. Finder validation reports can include your desktop directory and display geometry. Review and redact these reports before sharing. Local `build/`, `Validation/`, and machine-specific validation notes are ignored by Git.

# Contributing

Bug reports, reproducible examples, documentation fixes, new rug designs, and focused pull requests are welcome. English and Russian are both fine. Be respectful and keep discussions about the work.

## Development

Use macOS with an Apple Swift compiler, the macOS SDK, and Python 3.9+. Clone the repository, then run:

```bash
bash scripts/test.sh
python3 scripts/build.py
open "build/Desktop Rug.app"
```

The Swift package covers the AppKit-independent physics core; the native app is built by the script or the included Xcode project. Debug physics changes in the desktop app as well as the tests.

Keep changes focused. Describe the behavior being changed and the checks you ran. Add regression tests for meaningful physics or persistence changes. Run the native checks for interaction, rendering, or settings changes when a graphical session is available. Do not upload desktop screenshots, real Finder snapshots, credentials, personal paths, or local settings in a report.

When adding source files or resources, update the relevant resource list and regenerate the Xcode project with `python3 scripts/generate_project.py`. New art must be redistributable under the project license; record its source and any generation process in `DesktopRug/Resources/TextureSources.md`.

Contributions are made under the [MIT license](LICENSE).

## Maintainer release procedure

1. Update `VERSION` and `CHANGELOG.md`, then regenerate the Xcode project.
2. Run the full test suite, build the app, and run the appropriate native checks.
3. Run `python3 scripts/package_release.py`; review the version, architecture, ZIP, and `.sha256` file.
4. Commit the release state and publish a matching `vX.Y.Z` tag.
5. Create a GitHub Release for that exact tag and upload the verified archive and checksum. State whether the binary is Developer ID signed and notarized.

The build artifact produced by CI is not automatically published as a release. Maintainers explicitly select and publish the release files.

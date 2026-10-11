#!/usr/bin/env python3
"""Assemble the static launch page using the app's original bundled assets."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "site"
ASSETS = {
    "heriz.png": "DesktopRug/Resources/heriz.png",
    "indigo.png": "DesktopRug/Resources/indigo.png",
    "soviet-red.png": "DesktopRug/Resources/soviet-red.png",
    "soviet-floral.png": "DesktopRug/Resources/soviet-floral.png",
    "icon.png": "DesktopRug/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
}


def main():
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    shutil.copytree(ROOT / "site", OUTPUT)
    for name, source in ASSETS.items():
        shutil.copy2(ROOT / source, OUTPUT / "assets" / name)
    (OUTPUT / ".nojekyll").touch()
    print(f"Static site ready: {OUTPUT}")


if __name__ == "__main__":
    main()

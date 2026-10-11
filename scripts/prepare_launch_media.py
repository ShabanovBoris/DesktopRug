#!/usr/bin/env python3
"""Cut genuine app footage into launch assets; never replace the app recording."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VIDEO_URL = "https://github.com/user-attachments/assets/1a1f23eb-104f-4441-aa71-702475a0e4bb"
SOURCE_SHA256 = "089926595c878d868e1fbd32c98b268ce7d0f6a71b54f169811fa489fd9ff2a0"
SITE = ROOT / "site" / "assets"
PRESS = ROOT / "docs" / "launch" / "media"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build" / "desktop-rug-demo.mp4")
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        parser.error("ffmpeg is required; use the already generated media if it is unavailable")
    if not args.source.is_file():
        parser.error("source demo is missing; generated assets are committed, so regeneration is optional")
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        parser.error("source differs from the reviewed public demo; review footage before changing its checksum")
    if not shutil.which("swift"):
        parser.error("Swift with AppKit is required to render the macOS text overlays")
    SITE.mkdir(parents=True, exist_ok=True)
    PRESS.mkdir(parents=True, exist_ok=True)
    outputs = []

    with tempfile.TemporaryDirectory(prefix="desktoprug-media-") as temp:
        temp = Path(temp)

        subprocess.run(["swift", "-module-cache-path", str(ROOT / "build" / "ModuleCache"),
                        str(ROOT / "Tools" / "GenerateLaunchOverlays.swift"), str(temp)], check=True)

        def export(path, start, duration, filters, video=False, overlay=None):
            command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", str(start), "-i", str(args.source)]
            if overlay:
                command += ["-i", str(overlay)]
            if duration is not None:
                command += ["-t", str(duration)]
            if overlay:
                command += ["-filter_complex", f"[0:v]{filters}[base];[base][1:v]overlay=0:0:format=auto[out]", "-map", "[out]"]
            else:
                command += ["-vf", filters]
            command += ["-an"]
            if video:
                command += ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
            elif path.suffix != ".gif":
                command += ["-frames:v", "1"]
            subprocess.run(command + [str(path)], check=True)
            outputs.append({"path": str(path.relative_to(ROOT)), "source_start_seconds": start,
                            "duration_seconds": duration, "bytes": path.stat().st_size,
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})

        export(SITE / "demo.mp4", 0, 18, "scale=1280:-2", video=True)
        export(SITE / "poster.jpg", 16, None, "scale=1280:-2")
        export(SITE / "demo.gif", 0, 6,
               "fps=12,scale=640:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3")
        vertical = "scale=1008:-2,pad=1080:1920:36:570:color=0xf4f0e7"
        export(PRESS / "vertical.mp4", 0, 18, vertical, video=True, overlay=temp / "vertical.png")
        for index, start in [(1, 0), (2, 6), (3, 16)]:
            gallery = "scale=1040:-2,pad=1270:760:115:78:color=0xf4f0e7"
            export(PRESS / f"product-hunt-{index:02}.png", start, None, gallery, overlay=temp / f"gallery-{index}.png")
        card = "scale=690:-2,pad=1200:630:480:116:color=0xf4f0e7"
        export(SITE / "social-card.png", 16, None, card, overlay=temp / "social.png")

    icon = ROOT / "DesktopRug/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"
    shutil.copy2(icon, PRESS / "thumbnail.png")
    thumbnail = PRESS / "thumbnail.png"
    outputs.append({"path": str(thumbnail.relative_to(ROOT)), "bytes": thumbnail.stat().st_size,
                    "sha256": hashlib.sha256(thumbnail.read_bytes()).hexdigest()})
    (PRESS / "manifest.json").write_text(json.dumps({"source_url": VIDEO_URL, "source_sha256": digest,
        "source_release": "v1.0.1", "note": "Real app footage. Vertical, gallery, and social exports add captions and framing.",
        "outputs": outputs}, indent=2) + "\n")
    print(f"Generated {len(outputs)} reviewed launch assets")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check the assembled page and exact upload assets without network access."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import struct
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "build" / "site"


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.ids = set()
        self.metas = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        for attr in ("src", "href", "poster"):
            if attr in attrs:
                self.references.append(attrs[attr])
        if tag == "meta":
            self.metas[attrs.get("property", attrs.get("name"))] = attrs.get("content")


def png_size(path):
    content = path.read_bytes()
    assert content[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {path}"
    return struct.unpack(">II", content[16:24])


def main():
    page = SITE / "index.html"
    parser = Links()
    parser.feed(page.read_text())
    for reference in parser.references:
        url = urlsplit(reference)
        if url.scheme or url.netloc:
            assert url.scheme == "https", f"Unexpected external scheme: {reference}"
            continue
        if url.path:
            assert (SITE / unquote(url.path)).is_file(), f"Missing asset: {reference}"
        elif url.fragment:
            assert url.fragment in parser.ids, f"Missing section: {reference}"
    assert parser.metas["og:image"].endswith("/assets/social-card.png")
    assert parser.metas["twitter:card"] == "summary_large_image"
    for pattern in ("heriz", "indigo", "soviet-red", "soviet-floral"):
        assert (SITE / "assets" / f"{pattern}.png").is_file(), f"Missing pattern: {pattern}"
    assert png_size(SITE / "assets" / "social-card.png") == (1200, 630)
    for index in (1, 2, 3):
        assert png_size(ROOT / "docs/launch/media" / f"product-hunt-{index:02}.png") == (1270, 760)
    icon = ROOT / "docs/launch/media/thumbnail.png"
    assert png_size(icon) == (256, 256)
    assert icon.stat().st_size < 3_000_000
    manifest = json.loads((ROOT / "docs/launch/media/manifest.json").read_text())
    for asset in manifest["outputs"]:
        path = ROOT / asset["path"]
        assert path.stat().st_size == asset["bytes"], f"Asset size changed: {path}"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], f"Asset changed: {path}"
    posts = json.loads((ROOT / "docs/launch/posts.json").read_text())
    product = posts["product_hunt"]
    assert len(product["tagline"]) <= 60, "Product Hunt tagline exceeds 60 characters"
    assert len(product["description"]) <= 500, "Product Hunt description exceeds 500 characters"
    assert product["video_url"] is None, "Product Hunt requires a public YouTube URL, not an MP4 asset URL"
    for post in posts["x"]:
        # X counts each URL as 23 characters; these English posts contain no emoji.
        words = post["text"].split()
        weighted = len(post["text"]) + sum(23 - len(word) for word in words if word.startswith("https://"))
        assert weighted <= 280, f"X post too long: {post['id']} ({weighted})"
    print(f"Launch checks passed: {len(parser.references)} links, four patterns, verified media, platform copy limits")


if __name__ == "__main__":
    main()

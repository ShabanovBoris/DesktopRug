#!/usr/bin/env python3
"""Read public GitHub counts. Archive downloads are not unique users or installs."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO = "ShabanovBoris/DesktopRug"
API = f"https://api.github.com/repos/{REPO}"


def fetch(url):
    request = Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "DesktopRug-launch-metrics"})
    with urlopen(request, timeout=20) as response:
        return json.load(response)


def snapshot(repository, releases):
    archives = [{"release": release["tag_name"], "asset": asset["name"],
                 "downloads": asset["download_count"]}
                for release in releases if not release["draft"] and not release["prerelease"]
                for asset in release["assets"] if asset["name"].lower().endswith(".zip")]
    return {"repository": REPO, "observed_at": datetime.now(timezone.utc).isoformat(),
            "stars": repository["stargazers_count"], "forks": repository["forks_count"],
            "watchers": repository["subscribers_count"],
            "archive_downloads": sum(asset["downloads"] for asset in archives), "archives": archives,
            "sources": [API, API + "/releases"],
            "note": "Public release ZIP downloads, including repeat downloads; not unique users or installations."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--previous", type=Path, help="Compare with an earlier JSON snapshot")
    args = parser.parse_args()
    try:
        repository = fetch(API)
        releases = []
        page = 1
        while True:
            batch = fetch(f"{API}/releases?per_page=100&page={page}")
            releases.extend(batch)
            if len(batch) < 100:
                break
            page += 1
        result = snapshot(repository, releases)
        if args.previous:
            previous = json.loads(args.previous.read_text())
            if previous["repository"] != REPO:
                raise ValueError("previous snapshot belongs to a different repository")
            result["change_since_previous"] = {key: result[key] - previous[key]
                for key in ("stars", "forks", "watchers", "archive_downloads")}
        rendered = json.dumps(result, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered)
        print(rendered, end="")
    except (HTTPError, URLError, OSError, KeyError, ValueError) as error:
        print(f"Could not collect launch metrics: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

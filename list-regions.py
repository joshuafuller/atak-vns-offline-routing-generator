#!/usr/bin/env python3
"""List available Geofabrik download regions.

This script fetches the Geofabrik index JSON and prints all available
region paths. These paths can be used directly with `run.sh` to generate
offline routing data.
"""
from __future__ import annotations

import json
import sys
import urllib.request

INDEX_URL = "https://download.geofabrik.de/index-v1.json"


def fetch_index() -> dict | None:
    try:
        with urllib.request.urlopen(INDEX_URL) as resp:  # nosec B310
            return json.load(resp)
    except Exception as exc:  # pragma: no cover - network errors
        print(f"Error fetching index: {exc}", file=sys.stderr)
        return None


def walk(region: dict, indent: int = 0) -> None:
    path = region.get("path")
    if path:
        print("  " * indent + f"- {path}")
    for sub in region.get("subregions", []):
        walk(sub, indent + 1)


def main() -> int:
    data = fetch_index()
    if not data:
        return 1
    for region in data.get("subregions", []):
        walk(region)
    return 0


if __name__ == "__main__":
    sys.exit(main())

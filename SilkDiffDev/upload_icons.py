#!/usr/bin/env python3
"""
SilkDiffDev - toolbar icon uploader

Converts the SVGs in ./icons to PNGs and uploads them to Roblox via the
Open Cloud Assets API, then prints the rbxassetid:// values to paste into
SilkDiffRBLX/ServerStorage/SilkDiffPlugin/Modules/UI/__Source__.luau.

Usage:
    python upload_icons.py --api-key <KEY> --user-id <USER_ID>
    python upload_icons.py --api-key <KEY> --group-id <GROUP_ID>
    python upload_icons.py --api-key <KEY> --user-id <USER_ID> --size 256

The API key can also be provided via the ROBLOX_OPEN_CLOUD_API_KEY env var.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import requests

ASSETS_ENDPOINT = "https://apis.roblox.com/assets/v1/assets"
DEFAULT_ICON_DIR = Path(__file__).resolve().parent / "icons"
DEFAULT_SIZE = 256

# Lua variable names used in UI/__Source__.luau for each icon stem.
# Only entries whose Lua name differs from the SVG file stem are needed;
# everything else falls back to the stem name automatically.
LUA_KEYS = {
    "watchless_push": "watchlessPush",
}

try:
    import cairosvg
except Exception:
    cairosvg = None


# ── SVG → PNG ───────────────────────────────────────────────────

def svg_to_png(svg_path: Path, size: int) -> bytes:
    """Convert an SVG file to PNG bytes at the given square size."""
    if cairosvg is not None:
        return cairosvg.svg2png(
            url=str(svg_path),
            output_width=size,
            output_height=size,
        )

    rsvg = shutil.which("rsvg-convert")
    if rsvg is None:
        raise RuntimeError(
            "No SVG converter found. Install cairosvg "
            "(pip install cairosvg) or librsvg (brew install librsvg)."
        )

    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        subprocess.run(
            [rsvg, "-w", str(size), "-h", str(size), str(svg_path), "-o", tmp_path],
            capture_output=True,
            check=True,
        )
        with open(tmp_path, "rb") as f:
            return f.read()
    finally:
        os.remove(tmp_path)


# ── Open Cloud upload ───────────────────────────────────────────

def upload_png(api_key: str, creator: dict, png_bytes: bytes, name: str) -> int:
    """Upload a PNG as a Decal asset. Returns the numeric asset id."""
    request_payload = {
        "assetType": "Decal",
        "displayName": name,
        "creationContext": {"creator": creator},
    }

    resp = requests.post(
        ASSETS_ENDPOINT,
        headers={"x-api-key": api_key},
        files={
            "request": (None, json.dumps(request_payload), "application/json"),
            "fileContent": ("icon.png", png_bytes, "image/png"),
        },
        timeout=60,
    )

    if resp.status_code >= 400:
        raise RuntimeError(f"Upload failed ({resp.status_code}): {resp.text}")

    data = resp.json()

    # The Assets API is asynchronous: the initial POST returns an operation
    # object with a `path` to poll until `done` is true, then the result
    # contains the assetId.
    operation_path = data.get("path")
    if operation_path:
        return _poll_operation(api_key, operation_path)

    asset_id = data.get("assetId")
    if asset_id is None:
        raise RuntimeError(f"Unexpected response: {data}")
    return int(asset_id)


def _poll_operation(api_key: str, operation_path: str, max_attempts: int = 60) -> int:
    """Poll an async operation until it completes and return the assetId."""
    import time

    # The Assets API returns a relative operation path such as
    # ``operations/<operationId>``.  It is relative to ``/assets/v1/``;
    # appending it directly to the hostname produces the invalid host
    # ``apis.roblox.comoperations``.
    url = f"{ASSETS_ENDPOINT.rsplit('/', 1)[0]}/{operation_path.lstrip('/')}"
    for attempt in range(max_attempts):
        resp = requests.get(
            url,
            headers={"x-api-key": api_key},
            timeout=30,
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"Operation poll failed ({resp.status_code}): {resp.text}")

        data = resp.json()
        if data.get("done"):
            response = data.get("response") or {}
            asset_id = response.get("assetId")
            if asset_id is None:
                raise RuntimeError(f"Operation completed without assetId: {data}")
            return int(asset_id)

        time.sleep(1)

    raise RuntimeError(f"Operation did not complete after {max_attempts}s: {data}")


# ── Main ────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="upload_icons",
        description="Convert SVG icons to PNGs and upload them to Roblox Open Cloud.",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY"),
        help="Open Cloud API key (or set ROBLOX_OPEN_CLOUD_API_KEY)",
    )
    parser.add_argument(
        "--user-id",
        help="Your Roblox user id (uploads to your account)",
    )
    parser.add_argument(
        "--group-id",
        help="Group id (uploads to the group instead)",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=DEFAULT_SIZE,
        help=f"PNG size in pixels (default: {DEFAULT_SIZE})",
    )
    parser.add_argument(
        "--icons-dir",
        default=str(DEFAULT_ICON_DIR),
        help="Folder containing the SVG files",
    )
    args = parser.parse_args()

    if not args.api_key:
        parser.error("Missing API key: pass --api-key or set ROBLOX_OPEN_CLOUD_API_KEY")
    if not args.user_id and not args.group_id:
        parser.error("Provide --user-id or --group-id")

    creator = (
        {"userId": str(args.user_id)}
        if args.user_id
        else {"groupId": str(args.group_id)}
    )

    icons_dir = Path(args.icons_dir)
    svgs = sorted(icons_dir.glob("*.svg"))
    if not svgs:
        print(f"[SilkDiffDev] ✗ No .svg files found in {icons_dir}")
        return 1

    print(f"[SilkDiffDev] Converting {len(svgs)} SVG(s) to {args.size}x{args.size} PNG …")

    results: list[tuple[str, int]] = []
    for svg in svgs:
        try:
            png = svg_to_png(svg, args.size)
        except Exception as exc:
            print(f"[SilkDiffDev] ✗ {svg.name}: conversion failed: {exc}")
            return 1

        name = f"SilkDiff {svg.stem.replace('_', ' ').title()}"
        try:
            asset_id = upload_png(args.api_key, creator, png, name)
        except Exception as exc:
            print(f"[SilkDiffDev] ✗ {svg.name}: upload failed: {exc}")
            return 1

        print(f"[SilkDiffDev] ✓ {svg.name} → rbxassetid://{asset_id}")
        results.append((svg.stem, asset_id))

    print()
    print("── Paste into UI/__Source__.luau ─────────────────────────")
    print("local ICONS = {")
    for stem, asset_id in results:
        key = LUA_KEYS.get(stem, stem)
        print(f'    {key} = "rbxassetid://{asset_id}",')
    print("}")
    print("──────────────────────────────────────────────────────────")
    return 0


if __name__ == "__main__":
    sys.exit(main())

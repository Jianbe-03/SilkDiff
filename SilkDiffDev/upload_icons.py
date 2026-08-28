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
import urllib.error
import urllib.request
import uuid
from pathlib import Path

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

    result = subprocess.run(
        [rsvg, "-w", str(size), "-h", str(size), str(svg_path), "-o", "-"],
        capture_output=True,
        check=True,
    )
    return result.stdout


# ── Multipart form data (no external deps) ──────────────────────

def _build_multipart(fields: dict, files: dict) -> tuple[bytes, str]:
    boundary = "----SilkDiff" + uuid.uuid4().hex
    body = bytearray()

    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += str(value).encode() + b"\r\n"

    for name, (filename, content, content_type) in files.items():
        body += f"--{boundary}\r\n".encode()
        body += (
            f'Content-Disposition: form-data; name="{name}"; '
            f'filename="{filename}"\r\n'
        ).encode()
        body += f"Content-Type: {content_type}\r\n\r\n".encode()
        body += content + b"\r\n"

    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


# ── Open Cloud upload ───────────────────────────────────────────

def upload_png(api_key: str, creator: dict, png_bytes: bytes, name: str) -> int:
    """Upload a PNG as a Decal asset. Returns the numeric asset id."""
    body, content_type = _build_multipart(
        fields={
            "assetType": "Decal",
            "name": name,
            "creationContext": json.dumps({"creator": creator}),
        },
        files={
            "file": ("icon.png", png_bytes, "image/png"),
        },
    )

    req = urllib.request.Request(
        ASSETS_ENDPOINT,
        data=body,
        method="POST",
        headers={
            "x-api-key": api_key,
            "Content-Type": content_type,
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"Upload failed ({exc.code}): {detail}") from exc

    asset_id = data.get("assetId")
    if asset_id is None:
        raise RuntimeError(f"Unexpected response: {data}")
    return int(asset_id)


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
        {"type": "User", "targetId": str(args.user_id)}
        if args.user_id
        else {"type": "Group", "targetId": str(args.group_id)}
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
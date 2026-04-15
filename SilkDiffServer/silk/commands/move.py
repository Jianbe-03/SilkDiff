"""
silk move — Move an instance to a new parent.

Usage:
    silk move --Instance ./ServerScriptService/MyScript --NewParent ./ReplicatedStorage

This command:
    1. Moves the folder on disk to the new parent
    2. Updates the Parent property in __Properties__.yaml
"""

import os
import shutil
from pathlib import Path

import yaml


def _normalize_path(raw: str) -> str:
    cleaned = raw.replace("\\", "/").strip("/")
    if cleaned.startswith("./"):
        cleaned = cleaned[2:]
    return cleaned


def cmd_move(args):
    """Move an instance to a new parent."""
    instance_raw = args.instance
    new_parent_raw = args.new_parent

    instance_path = _normalize_path(instance_raw)
    new_parent_path = _normalize_path(new_parent_raw)

    instance_dir = Path(os.getcwd()) / instance_path
    new_parent_dir = Path(os.getcwd()) / new_parent_path

    if not instance_dir.exists():
        print(f"[SilkDiff] ✗ Instance not found: {instance_dir}")
        return

    if not new_parent_dir.exists():
        print(f"[SilkDiff] ✗ New parent not found: {new_parent_dir}")
        return

    instance_name = instance_dir.name
    new_location = new_parent_dir / instance_name

    if new_location.exists():
        print(f"[SilkDiff] ✗ '{instance_name}' already exists in the target parent")
        return

    # ── figure out the new parent's Name ────────────────────────
    parent_props_file = new_parent_dir / "__Properties__.yaml"
    if parent_props_file.exists():
        with open(parent_props_file, "r", encoding="utf-8") as f:
            parent_props = yaml.safe_load(f) or {}
        new_parent_name = parent_props.get("Name", new_parent_dir.name)
    else:
        new_parent_name = new_parent_dir.name

    # ── move the folder ─────────────────────────────────────────
    shutil.move(str(instance_dir), str(new_location))

    # ── update __Properties__.yaml with new Parent ──────────────
    props_file = new_location / "__Properties__.yaml"
    if props_file.exists():
        with open(props_file, "r", encoding="utf-8") as f:
            props = yaml.safe_load(f) or {}
        old_parent = props.get("Parent", "?")
        props["Parent"] = new_parent_name
        with open(props_file, "w", encoding="utf-8") as f:
            yaml.dump(props, f, default_flow_style=False, allow_unicode=True, sort_keys=True)
    else:
        old_parent = "?"

    old_rel = instance_path
    new_rel = new_location.relative_to(Path(os.getcwd()))
    print(f"[SilkDiff] ✓ Moved '{instance_name}'")
    print(f"[SilkDiff]   From:   ./{old_rel}")
    print(f"[SilkDiff]   To:     ./{new_rel}")
    print(f"[SilkDiff]   Parent: {old_parent} → {new_parent_name}")

"""
silk rename — Rename an existing instance.

Usage:
    silk rename --Instance ./ServerScriptService/OldName --Name NewName

This command:
    1. Renames the folder on disk
    2. Updates the Name property in __Properties__.yaml
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


def cmd_rename(args):
    """Rename an existing instance."""
    instance_raw = args.instance
    new_name = args.name

    instance_path = _normalize_path(instance_raw)
    instance_dir = Path(os.getcwd()) / instance_path

    if not instance_dir.exists():
        print(f"[SilkDiff] ✗ Instance not found: {instance_dir}")
        return

    # ── update __Properties__.yaml ──────────────────────────────
    props_file = instance_dir / "__Properties__.yaml"
    if props_file.exists():
        with open(props_file, "r", encoding="utf-8") as f:
            props = yaml.safe_load(f) or {}
        old_name = props.get("Name", instance_dir.name)
        props["Name"] = new_name
        with open(props_file, "w", encoding="utf-8") as f:
            yaml.dump(props, f, default_flow_style=False, allow_unicode=True, sort_keys=True)
    else:
        old_name = instance_dir.name

    # ── rename the folder ───────────────────────────────────────
    new_dir = instance_dir.parent / new_name
    if new_dir.exists():
        print(f"[SilkDiff] ✗ A sibling with name '{new_name}' already exists")
        return

    shutil.move(str(instance_dir), str(new_dir))

    # ── update children's Parent property ───────────────────────
    # Children reference this instance as their Parent, so we need
    # to update any child whose Parent == old_name
    for child_dir in new_dir.iterdir():
        if child_dir.is_dir() and not child_dir.name.startswith("__"):
            child_props = child_dir / "__Properties__.yaml"
            if child_props.exists():
                with open(child_props, "r", encoding="utf-8") as f:
                    cp = yaml.safe_load(f) or {}
                if cp.get("Parent") == old_name:
                    cp["Parent"] = new_name
                    with open(child_props, "w", encoding="utf-8") as f:
                        yaml.dump(cp, f, default_flow_style=False,
                                  allow_unicode=True, sort_keys=True)

    rel = new_dir.relative_to(Path(os.getcwd()))
    print(f"[SilkDiff] ✓ Renamed '{old_name}' → '{new_name}'")
    print(f"[SilkDiff]   New path: ./{rel}")

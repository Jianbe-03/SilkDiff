"""
silk create — Create a new Roblox instance on disk.

Usage:
    silk create --Class Script --Parent ./ServerScriptService --Name MyScript
    silk create --Class Part --Parent ./Workspace
    silk create --Class Folder --Parent ./ReplicatedStorage --Name Utils

This command:
    1. Validates the ClassName against the full Roblox class list
    2. Creates the instance folder under the parent
    3. Generates __Properties__.yaml with default properties for the class
    4. Generates __Attributes__.yaml with a fresh SilkDiffId
    5. Generates __Tags__.yaml (empty list)
    6. Generates __Source__.luau if it's a Script / LocalScript / ModuleScript
"""

import os
import uuid
from pathlib import Path

import yaml

from silk.default_properties import DEFAULT_PROPERTIES

# ClassNames that carry source code
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}

# Default source stubs per script type
DEFAULT_SOURCE = {
    "Script": '-- Server Script\nprint("Hello from {name}!")\n',
    "LocalScript": '-- Local Script\nprint("Hello from {name}!")\n',
    "ModuleScript": "local module = {{}}\n\nreturn module\n",
}


def _normalize_path(raw: str) -> str:
    """Turn a filesystem-style path into a clean relative path.
    Strips leading './', normalises separators."""
    cleaned = raw.replace("\\", "/").strip("/")
    if cleaned.startswith("./"):
        cleaned = cleaned[2:]
    return cleaned


def cmd_create(args):
    """Create a new instance on disk."""
    class_name = args.class_name
    parent_raw = args.parent
    name = args.name or class_name

    # ── validate ClassName ──────────────────────────────────────
    if class_name not in DEFAULT_PROPERTIES:
        # Try case-insensitive match
        match = None
        for key in DEFAULT_PROPERTIES:
            if key.lower() == class_name.lower():
                match = key
                break
        if match:
            class_name = match
        else:
            print(f"[SilkDiff] ✗ Unknown ClassName: {class_name}")
            print(f"[SilkDiff]   Use one of the {len(DEFAULT_PROPERTIES)} supported classes.")
            print(f"[SilkDiff]   Hint: Script, LocalScript, ModuleScript, Part, Folder, Model, …")
            return

    # ── resolve paths ───────────────────────────────────────────
    parent_path = _normalize_path(parent_raw)
    instance_dir = Path(os.getcwd()) / parent_path / name

    if instance_dir.exists():
        print(f"[SilkDiff] ✗ Instance already exists: {instance_dir}")
        return

    instance_dir.mkdir(parents=True, exist_ok=True)

    # ── figure out the parent's Name (last segment) ─────────────
    parent_name = Path(parent_path).name or "game"

    # ── build properties from defaults ──────────────────────────
    props = dict(DEFAULT_PROPERTIES.get(class_name, {}))
    props["ClassName"] = class_name
    props["Name"] = name
    props["Parent"] = parent_name

    # Make sure Archivable is present
    if "Archivable" not in props:
        props["Archivable"] = True

    # ── properties file ─────────────────────────────────────────
    props_file = instance_dir / "__Properties__.yaml"
    with open(props_file, "w", encoding="utf-8") as f:
        yaml.dump(props, f, default_flow_style=False, allow_unicode=True, sort_keys=True)

    # ── attributes file (with fresh SilkDiffId) ─────────────────
    silk_id = str(uuid.uuid4())
    attrs = {"SilkDiffId": silk_id}
    attrs_file = instance_dir / "__Attributes__.yaml"
    with open(attrs_file, "w", encoding="utf-8") as f:
        yaml.dump(attrs, f, default_flow_style=False, allow_unicode=True)

    # ── tags file (empty) ───────────────────────────────────────
    tags_file = instance_dir / "__Tags__.yaml"
    with open(tags_file, "w", encoding="utf-8") as f:
        yaml.dump([], f, default_flow_style=False)

    # ── source file (scripts only) ──────────────────────────────
    if class_name in SCRIPT_CLASSES:
        source_file = instance_dir / "__Source__.luau"
        template = DEFAULT_SOURCE.get(class_name, "")
        source = template.format(name=name)
        source_file.write_text(source, encoding="utf-8")

    # ── done ────────────────────────────────────────────────────
    rel = instance_dir.relative_to(Path(os.getcwd()))
    print(f"[SilkDiff] ✓ Created {class_name} '{name}' at ./{rel}")
    print(f"[SilkDiff]   SilkDiffId: {silk_id}")

    files_created = ["__Properties__.yaml", "__Attributes__.yaml", "__Tags__.yaml"]
    if class_name in SCRIPT_CLASSES:
        files_created.append("__Source__.luau")
    print(f"[SilkDiff]   Files: {', '.join(files_created)}")

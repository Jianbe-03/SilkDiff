"""
SilkDiff File Manager

Manages reading and writing Roblox instance files on the local filesystem.

Every Roblox instance is stored as a **folder** containing up to 4 files:

    __Properties__.yaml   – instance properties (Name, ClassName, …)
    __Attributes__.yaml   – custom attributes
    __Tags__.yaml         – CollectionService tags
    __Source__.luau        – script source code  (only for Script types)

The folder hierarchy mirrors the Roblox game tree:

    Workspace/
        Baseplate/
            __Properties__.yaml
            __Attributes__.yaml
            __Tags__.yaml
        Models/
            Tree/
                __Properties__.yaml
                ...
"""

import shutil
from pathlib import Path
from typing import Any, Optional

from .config import Config
from .serializer import Serializer

# ClassNames that carry source code
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}


# ── value normalization (YAML raw → typed envelope) ──────────────

def _normalize_value(value: Any) -> Any:
    """Convert a raw YAML value into a typed envelope {t, v}.
    Already-typed values pass through unchanged.
    "nil" / None both become None."""
    if value is None or (isinstance(value, str) and value.lower() == "nil"):
        return None
    if isinstance(value, dict) and "t" in value and "v" in value:
        return value  # already typed
    if isinstance(value, bool):
        return {"t": "boolean", "v": value}
    if isinstance(value, (int, float)):
        return {"t": "number", "v": value}
    if isinstance(value, str):
        return {"t": "Enum" if value.startswith("Enum.") else "string", "v": value}
    if isinstance(value, dict):
        k = set(value)
        if k == {"Scale", "Offset"}:
            return {"t": "UDim", "v": {"Scale": float(value["Scale"]), "Offset": float(value["Offset"])}}
        if all(isinstance(v, dict) and set(v) == {"Scale", "Offset"} for v in value.values()):
            return {"t": "UDim2", "v": {k2: {"Scale": float(v2["Scale"]), "Offset": float(v2["Offset"])} for k2, v2 in value.items()}}
        if k == {"X", "Y", "Z"}:
            return {"t": "Vector3", "v": {"X": float(value["X"]), "Y": float(value["Y"]), "Z": float(value["Z"])}}
        if k == {"X", "Y"}:
            return {"t": "Vector2", "v": {"X": float(value["X"]), "Y": float(value["Y"])}}
        if k == {"R", "G", "B"}:
            return {"t": "Color3", "v": {"R": float(value["R"]), "G": float(value["G"]), "B": float(value["B"])}}
        if "Position" in k:
            return {"t": "CFrame", "v": value}
        return {"t": "dict", "v": value}
    return value


def _normalize_dict(raw: dict) -> dict:
    """Normalize every value in a flat dict to typed envelopes."""
    return {k: _normalize_value(v) for k, v in raw.items()} if isinstance(raw, dict) else raw


class FileManager:
    """Read / write instance folders on disk."""

    def __init__(self, config: Config):
        self.config = config
        self.serializer = Serializer(config)
        self.project_dir = Path(config.project_dir)

    # ------------------------------------------------------------------
    # path helpers
    # ------------------------------------------------------------------

    def _instance_dir(self, dot_path: str) -> Path:
        """Convert a dot-separated path ("Workspace.Baseplate") to a
        filesystem path under the project directory."""
        parts = dot_path.split(".")
        return self.project_dir / Path(*parts)

    @staticmethod
    def _instance_silk(inst: dict) -> str:
        """Extract the silk id from a serialized instance (envelope aware)."""
        silk = inst.get("silkId")
        if silk:
            return silk
        attrs = inst.get("attributes") or {}
        for key in ("SilkDiffId", "PestoId"):
            sid = attrs.get(key)
            if isinstance(sid, dict):
                sid = sid.get("v")
            if sid:
                return sid
        return ""

    def _find_unique_path(self, dot_path: str) -> str:
        """Given a dot-path whose folder already exists, return a sibling
        path with a numeric suffix that doesn't exist yet, matching Roblox
        Studio's duplicate naming, e.g.
        'Workspace.Part' → 'Workspace.Part (1)' → 'Workspace.Part (2)' …"""
        base = dot_path
        suffix = 1
        while self._instance_dir(f"{base} ({suffix})").exists():
            suffix += 1
        return f"{base} ({suffix})"

    # ------------------------------------------------------------------
    # single instance
    # ------------------------------------------------------------------

    def read_instance(self, instance_path: str) -> Optional[dict]:
        """Read a single instance from disk.  Returns None if the
        directory doesn't exist.

        All property and attribute values are normalized to typed
        envelopes ({t, v}) to match the format sent by the plugin."""
        directory = self._instance_dir(instance_path)
        if not directory.exists():
            return None

        result: dict = {"path": instance_path}

        props_file = directory / self.config.get_properties_file()
        if props_file.exists():
            result["properties"] = _normalize_dict(self.serializer.from_file(props_file) or {})

        attrs_file = directory / self.config.get_attributes_file()
        if attrs_file.exists():
            result["attributes"] = _normalize_dict(self.serializer.from_file(attrs_file) or {})

        tags_file = directory / self.config.get_tags_file()
        if tags_file.exists():
            result["tags"] = self.serializer.from_file(tags_file) or []

        source_file = directory / self.config.get_source_file()
        if source_file.exists():
            result["source"] = source_file.read_text(encoding="utf-8")

        return result

    def write_instance(self, data: dict) -> None:
        """Write a single instance to disk (creates the folder if needed).

        All property and attribute values are normalised to typed
        envelopes so the YAML files always match the plugin format."""
        dot_path = data.get("path", "")
        directory = self._instance_dir(dot_path)
        directory.mkdir(parents=True, exist_ok=True)

        # Properties
        if "properties" in data:
            self.serializer.to_file(
                _normalize_dict(data["properties"]),
                directory / self.config.get_properties_file(),
            )

        # Attributes
        if "attributes" in data:
            self.serializer.to_file(
                _normalize_dict(data["attributes"]),
                directory / self.config.get_attributes_file(),
            )

        # Tags
        if "tags" in data:
            self.serializer.to_file(
                data["tags"],
                directory / self.config.get_tags_file(),
            )

        # Source
        if data.get("source") is not None:
            source_file = directory / self.config.get_source_file()
            source_file.write_text(data["source"], encoding="utf-8")

    def apply_diff(self, diff: dict) -> None:
        """Apply a partial diff entry to the local files.

        Used when the user stages only some changes. The diff entry lists
        *which* properties/attributes/tags/source changed; the actual new
        values come from ``diff["instance"]`` (the full serialized instance
        the plugin attached). Only the staged parts are merged into the
        existing files on disk.

        Supported keys on *diff*:
            status "removed"   → delete instance folder
            status "added"     → full write of diff["instance"]
            propertyChanges    {key: {old, new, changeType}}  → merge keys from instance.properties
            attributeChanges   {key: ...}                      → merge keys from instance.attributes
            tagChanges         {added: [...], removed: [...]}  → adjust tags
            sourceChanged      True + instance.source          → overwrite source
        """
        dot_path = diff.get("path", "")
        if not dot_path:
            return
        directory = self._instance_dir(dot_path)
        instance = diff.get("instance") or {}

        # Removed: delete the folder entirely
        if diff.get("status") == "removed":
            if directory.exists():
                shutil.rmtree(directory)
            return

        # Added: full write of the attached instance
        if diff.get("status") == "added":
            if not instance:
                return

            # If the target folder already exists with a DIFFERENT silk id,
            # this is a duplicate (same name/path as an existing instance).
            # Write it to a unique path instead of clobbering the original.
            existing = self.read_instance(dot_path)
            incoming_silk = self._instance_silk(instance)
            existing_silk = self._instance_silk(existing) if existing else ""
            if existing and existing_silk and incoming_silk and existing_silk != incoming_silk:
                dot_path = self._find_unique_path(dot_path)
                instance = dict(instance)
                instance["path"] = dot_path

            self.write_instance(instance)
            return

        # ── Rename / move detection ─────────────────────────────
        # When an instance is renamed or moved, the diff path is the NEW
        # path, but the old folder may still exist on disk (matched via
        # the shared SilkDiffId). Move the old folder to the new path so
        # we keep its properties / attributes / children instead of
        # creating an empty new folder.
        silk_id = self._instance_silk(instance)
        if silk_id:
            old_path = self.find_by_silk_id(silk_id)
            if old_path and old_path != dot_path:
                old_dir = self._instance_dir(old_path)
                if old_dir.exists():
                    # Ensure the new parent exists before moving
                    directory.parent.mkdir(parents=True, exist_ok=True)
                    if directory.exists():
                        shutil.rmtree(directory)
                    old_dir.rename(directory)

        # Modified: merge only the staged parts into the existing files
        existing = self.read_instance(dot_path) or {}
        props = dict(existing.get("properties") or {})
        attrs = dict(existing.get("attributes") or {})
        tags = list(existing.get("tags") or [])

        # Property changes — new value taken from the attached instance data
        for key, change in (diff.get("propertyChanges") or {}).items():
            if change.get("changeType") == "removed" or change.get("new") is None:
                props.pop(key, None)
            else:
                new_val = (instance.get("properties") or {}).get(key)
                if new_val is not None:
                    props[key] = new_val

        # Attribute changes
        for key, change in (diff.get("attributeChanges") or {}).items():
            if change.get("changeType") == "removed" or change.get("new") is None:
                attrs.pop(key, None)
            else:
                new_val = (instance.get("attributes") or {}).get(key)
                if new_val is not None:
                    attrs[key] = new_val

        # Tag changes
        tag_changes = diff.get("tagChanges") or {}
        tag_set = set(tags)
        for tag in tag_changes.get("added", []):
            tag_set.add(tag)
        for tag in tag_changes.get("removed", []):
            tag_set.discard(tag)

        # Write back only what changed
        directory.mkdir(parents=True, exist_ok=True)
        if diff.get("propertyChanges"):
            self.serializer.to_file(
                _normalize_dict(props),
                directory / self.config.get_properties_file(),
            )
        if diff.get("attributeChanges"):
            self.serializer.to_file(
                _normalize_dict(attrs),
                directory / self.config.get_attributes_file(),
            )
        if diff.get("tagChanges"):
            self.serializer.to_file(
                sorted(tag_set),
                directory / self.config.get_tags_file(),
            )

        # Source change
        if diff.get("sourceChanged"):
            new_source = instance.get("source") or diff.get("newSource")
            source_file = directory / self.config.get_source_file()
            if new_source is not None:
                source_file.write_text(new_source, encoding="utf-8")

    # ------------------------------------------------------------------
    # trees (recursive)
    # ------------------------------------------------------------------

    def write_tree(self, tree: dict, _siblings: Optional[dict] = None, _parent_path: str = "") -> None:
        """Recursively write an entire instance tree to disk.

        Roblox allows siblings with the same name (e.g. two Parts both
        called "Part"). On disk that would collide, so when a sibling
        shares a name but has a different silk id we write it to a unique
        path ('Part (1)') instead of clobbering. Children are re-parented
        to follow their parent's (possibly unique) path.
        """
        siblings = _siblings if _siblings is not None else {}

        # Build this node's path from the parent's actual path + its name.
        # The serialized path's last segment is the instance's Name.
        name = tree.get("path", "").split(".")[-1]

        dot_path = f"{_parent_path}.{name}" if _parent_path else name
        silk = self._instance_silk(tree)

        if siblings.get(dot_path) and siblings[dot_path] != silk:
            dot_path = self._find_unique_path(dot_path)

        siblings[dot_path] = silk

        instance = dict(tree)
        instance["path"] = dot_path
        instance.pop("children", None)
        self.write_instance(instance)

        child_siblings: dict = {}
        for child in tree.get("children", []):
            self.write_tree(child, child_siblings, dot_path)

    def read_tree(self, root_path: str) -> Optional[dict]:
        """Recursively read an instance tree from disk."""
        directory = self._instance_dir(root_path)
        if not directory.exists():
            return None

        result = self.read_instance(root_path)
        if result is None:
            return None

        children = []
        for child_dir in sorted(directory.iterdir()):
            # Only recurse into directories that aren't metadata files
            if child_dir.is_dir() and not child_dir.name.startswith("__"):
                child_path = f"{root_path}.{child_dir.name}"
                child_data = self.read_tree(child_path)
                if child_data:
                    children.append(child_data)

        if children:
            result["children"] = children

        return result

    # ------------------------------------------------------------------
    # Export helpers
    # ------------------------------------------------------------------

    def clear_service_roots(self, trees: list) -> None:
        """Delete the top-level folder for each exported service tree so the
        next write is a clean rebuild rather than a partial overwrite."""
        for tree in trees:
            path = tree.get("path", "")
            if not path:
                continue
            root_name = path.split(".")[0]
            directory = self.project_dir / root_name
            if directory.exists():
                shutil.rmtree(directory)

    # ------------------------------------------------------------------
    # ID-based lookup
    # ------------------------------------------------------------------

    def find_by_silk_id(self, silk_id: str) -> Optional[str]:
        """Scan all instance directories for the one whose attributes contain
        ``SilkDiffId == silk_id`` or ``PestoId == silk_id``.
        Returns the dot-separated path, or None."""
        for path in self.get_all_instance_paths():
            inst = self.read_instance(path)
            if inst and isinstance(inst.get("attributes"), dict):
                attrs = inst["attributes"]
                # Attributes are normalized typed envelopes; unwrap to compare
                sid = attrs.get("SilkDiffId", {})
                pid = attrs.get("PestoId", {})
                sid_v = sid.get("v") if isinstance(sid, dict) else sid
                pid_v = pid.get("v") if isinstance(pid, dict) else pid
                if sid_v == silk_id or pid_v == silk_id:
                    return path
        return None

    # ------------------------------------------------------------------
    # deletion
    # ------------------------------------------------------------------

    def delete_instance(self, instance_path: str) -> None:
        """Remove an instance folder (and all children) from disk."""
        directory = self._instance_dir(instance_path)
        if directory.exists():
            shutil.rmtree(directory)

    # ------------------------------------------------------------------
    # enumeration
    # ------------------------------------------------------------------

    def get_all_instance_paths(self, root_path: str = "") -> list[str]:
        """Return a flat list of every instance path under *root_path*."""
        directory = (
            self._instance_dir(root_path) if root_path else self.project_dir
        )
        if not directory.exists():
            return []

        paths: list[str] = []
        for item in sorted(directory.iterdir()):
            if item.is_dir() and not item.name.startswith(("__", ".")):
                ipath = f"{root_path}.{item.name}" if root_path else item.name
                paths.append(ipath)
                paths.extend(self.get_all_instance_paths(ipath))

        return paths

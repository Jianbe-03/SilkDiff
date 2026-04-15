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
from typing import Optional

from .config import Config
from .serializer import Serializer

# ClassNames that carry source code
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}


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

    # ------------------------------------------------------------------
    # single instance
    # ------------------------------------------------------------------

    def read_instance(self, instance_path: str) -> Optional[dict]:
        """Read a single instance from disk.  Returns None if the
        directory doesn't exist."""
        directory = self._instance_dir(instance_path)
        if not directory.exists():
            return None

        result: dict = {"path": instance_path}

        # Properties
        props_file = directory / self.config.get_properties_file()
        if props_file.exists():
            result["properties"] = self.serializer.from_file(props_file)

        # Attributes
        attrs_file = directory / self.config.get_attributes_file()
        if attrs_file.exists():
            result["attributes"] = self.serializer.from_file(attrs_file)

        # Tags
        tags_file = directory / self.config.get_tags_file()
        if tags_file.exists():
            result["tags"] = self.serializer.from_file(tags_file) or []

        # Source
        source_file = directory / self.config.get_source_file()
        if source_file.exists():
            result["source"] = source_file.read_text(encoding="utf-8")

        return result

    def write_instance(self, data: dict) -> None:
        """Write a single instance to disk (creates the folder if needed)."""
        dot_path = data.get("path", "")
        directory = self._instance_dir(dot_path)
        directory.mkdir(parents=True, exist_ok=True)

        # Properties
        if "properties" in data:
            self.serializer.to_file(
                data["properties"],
                directory / self.config.get_properties_file(),
            )

        # Attributes
        if "attributes" in data:
            self.serializer.to_file(
                data["attributes"],
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

    # ------------------------------------------------------------------
    # trees (recursive)
    # ------------------------------------------------------------------

    def write_tree(self, tree: dict) -> None:
        """Recursively write an entire instance tree to disk."""
        self.write_instance(tree)
        for child in tree.get("children", []):
            self.write_tree(child)

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

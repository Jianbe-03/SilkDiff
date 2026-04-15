"""
SilkDiff Serializer

Handles reading / writing YAML and JSON for instance data.
Thin wrapper so the rest of the codebase never touches file
formats directly.
"""

import json
from pathlib import Path
from typing import Any

import yaml


class Serializer:
    """Read and write instance data in YAML or JSON."""

    def __init__(self, config):
        self.config = config

    # ---- file I/O ----

    def to_file(self, data: Any, path: Path) -> None:
        """Write *data* to *path* in the format indicated by its suffix."""
        ext = path.suffix.lower()
        with open(path, "w", encoding="utf-8") as fh:
            if ext in (".yaml", ".yml"):
                yaml.dump(data, fh, default_flow_style=False, allow_unicode=True)
            elif ext == ".json":
                json.dump(data, fh, indent=4, ensure_ascii=False)
            else:
                fh.write(str(data))

    def from_file(self, path: Path) -> Any:
        """Read and parse *path* according to its suffix."""
        ext = path.suffix.lower()
        with open(path, "r", encoding="utf-8") as fh:
            if ext in (".yaml", ".yml"):
                return yaml.safe_load(fh) or {}
            elif ext == ".json":
                return json.load(fh)
            else:
                return fh.read()

    # ---- string helpers ----

    @staticmethod
    def to_yaml(data: Any) -> str:
        return yaml.dump(data, default_flow_style=False, allow_unicode=True)

    @staticmethod
    def from_yaml(text: str) -> Any:
        return yaml.safe_load(text) or {}

    @staticmethod
    def to_json(data: Any) -> str:
        return json.dumps(data, indent=4, ensure_ascii=False)

    @staticmethod
    def from_json(text: str) -> Any:
        return json.loads(text)

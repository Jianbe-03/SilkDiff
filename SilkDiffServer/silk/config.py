"""
SilkDiff Config

Default configuration for the SilkDiff local server.
Values can be overridden via CLI arguments.
"""

import os
from dataclasses import dataclass, field


@dataclass
class Config:
    """All server configuration in one place."""

    # Network
    host: str = "127.0.0.1"
    port: int = 6969

    # File-format settings (should match the Roblox plugin settings)
    properties_extension: str = ".yaml"
    source_extension: str = ".luau"
    properties_filename: str = "__Properties__"
    attributes_filename: str = "__Attributes__"
    tags_filename: str = "__Tags__"
    source_filename: str = "__Source__"

    # Root directory where instance folders live on disk
    project_dir: str = field(default_factory=os.getcwd)

    # ---- helpers ----

    def get_properties_file(self) -> str:
        """Full filename for properties, e.g. '__Properties__.yaml'."""
        return f"{self.properties_filename}{self.properties_extension}"

    def get_attributes_file(self) -> str:
        """Full filename for attributes, e.g. '__Attributes__.yaml'."""
        return f"{self.attributes_filename}{self.properties_extension}"

    def get_tags_file(self) -> str:
        """Full filename for tags, e.g. '__Tags__.yaml'."""
        return f"{self.tags_filename}{self.properties_extension}"

    def get_source_file(self) -> str:
        """Full filename for source, e.g. '__Source__.luau'."""
        return f"{self.source_filename}{self.source_extension}"

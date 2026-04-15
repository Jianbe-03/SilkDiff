"""
SilkDiff Diff Engine

Compares two instance states and returns structured diff entries
that can be displayed to the user.

Diff statuses:
    "added"    – instance exists only in the new data
    "removed"  – instance exists only in the old data
    "modified" – instance exists in both but has differences
"""

from typing import Any, Optional


class DiffEngine:
    """Stateless differ — call methods directly."""

    # ------------------------------------------------------------------
    # properties / attributes (flat dicts)
    # ------------------------------------------------------------------

    @staticmethod
    def compare_properties(old: dict, new: dict) -> dict:
        """Compare two flat key→value dicts.
        Returns ``{key: {old, new, changeType}}`` for every difference."""
        changes: dict[str, dict[str, Any]] = {}
        all_keys = set(old) | set(new)

        for key in all_keys:
            old_val = old.get(key)
            new_val = new.get(key)

            if old_val is None and new_val is not None:
                changes[key] = {"old": None, "new": new_val, "changeType": "added"}
            elif old_val is not None and new_val is None:
                changes[key] = {"old": old_val, "new": None, "changeType": "removed"}
            elif str(old_val) != str(new_val):
                changes[key] = {"old": old_val, "new": new_val, "changeType": "modified"}

        return changes

    # ------------------------------------------------------------------
    # tags (lists of strings)
    # ------------------------------------------------------------------

    @staticmethod
    def compare_tags(old_tags: list, new_tags: list) -> dict:
        """Return ``{added: [...], removed: [...]}``."""
        old_set = set(old_tags or [])
        new_set = set(new_tags or [])
        return {
            "added": sorted(new_set - old_set),
            "removed": sorted(old_set - new_set),
        }

    # ------------------------------------------------------------------
    # single instances
    # ------------------------------------------------------------------

    def compare_instances(
        self,
        old_data: Optional[dict],
        new_data: Optional[dict],
    ) -> Optional[dict]:
        """Compare two serialized instances (without children).
        Returns a diff dict or ``None`` if nothing changed."""

        # Added
        if old_data is None and new_data is not None:
            return {
                "path": new_data.get("path", ""),
                "name": new_data.get("name", ""),
                "className": new_data.get("className", ""),
                "status": "added",
            }

        # Removed
        if old_data is not None and new_data is None:
            return {
                "path": old_data.get("path", ""),
                "name": old_data.get("name", ""),
                "className": old_data.get("className", ""),
                "status": "removed",
            }

        if old_data is None or new_data is None:
            return None

        prop_changes = self.compare_properties(
            old_data.get("properties", {}),
            new_data.get("properties", {}),
        )
        attr_changes = self.compare_properties(
            old_data.get("attributes", {}),
            new_data.get("attributes", {}),
        )
        tag_changes = self.compare_tags(
            old_data.get("tags", []),
            new_data.get("tags", []),
        )
        source_changed = old_data.get("source") != new_data.get("source")

        has_changes = bool(
            prop_changes
            or attr_changes
            or tag_changes["added"]
            or tag_changes["removed"]
            or source_changed
        )

        if not has_changes:
            return None

        result: dict[str, Any] = {
            "path": new_data.get("path", ""),
            "name": new_data.get("name", ""),
            "className": new_data.get("className", ""),
            "status": "modified",
        }
        if prop_changes:
            result["propertyChanges"] = prop_changes
        if attr_changes:
            result["attributeChanges"] = attr_changes
        if tag_changes["added"] or tag_changes["removed"]:
            result["tagChanges"] = tag_changes
        if source_changed:
            result["sourceChanged"] = True
            result["oldSource"] = old_data.get("source")
            result["newSource"] = new_data.get("source")

        return result

    # ------------------------------------------------------------------
    # trees (recursive)
    # ------------------------------------------------------------------

    def compare_trees(
        self,
        old_tree: Optional[dict],
        new_tree: Optional[dict],
    ) -> list[dict]:
        """Recursively diff two instance trees.
        Returns a flat list of diff entries."""
        diffs: list[dict] = []

        root_diff = self.compare_instances(old_tree, new_tree)
        if root_diff:
            diffs.append(root_diff)

        old_children: dict[str, dict] = {}
        new_children: dict[str, dict] = {}

        if old_tree and "children" in old_tree:
            for c in old_tree["children"]:
                old_children[c.get("path", "")] = c
        if new_tree and "children" in new_tree:
            for c in new_tree["children"]:
                new_children[c.get("path", "")] = c

        for path in sorted(set(old_children) | set(new_children)):
            diffs.extend(
                self.compare_trees(
                    old_children.get(path),
                    new_children.get(path),
                )
            )

        return diffs

    # ------------------------------------------------------------------
    # summary
    # ------------------------------------------------------------------

    @staticmethod
    def summarize(diffs: list[dict]) -> str:
        """One-line human-readable summary."""
        if not diffs:
            return "No changes detected."

        added = sum(1 for d in diffs if d.get("status") == "added")
        removed = sum(1 for d in diffs if d.get("status") == "removed")
        modified = sum(1 for d in diffs if d.get("status") == "modified")

        parts = []
        if added:
            parts.append(f"{added} added")
        if modified:
            parts.append(f"{modified} modified")
        if removed:
            parts.append(f"{removed} removed")

        return f"{', '.join(parts)} ({len(diffs)} total)"

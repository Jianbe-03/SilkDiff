"""
SilkDiff Diff Engine

Compares two instance states and returns structured diff entries
that can be displayed to the user.

All values are typed envelopes ({t, v}) — normalization happens
in FileManager.read_instance().

Diff statuses:
    "added"    – instance exists only in the new data
    "removed"  – instance exists only in the old data
    "modified" – instance exists in both but has differences
"""

from typing import Any, Optional


class DiffEngine:
    """Stateless differ — call methods directly."""

    @staticmethod
    def _typed_equal(a: Any, b: Any) -> bool:
        """Compare two typed envelopes {t, v}."""
        if a is None and b is None:
            return True
        if a is None or b is None:
            return False

        if a["t"] != b["t"]:
            return False

        t = a["t"]
        av, bv = a.get("v"), b.get("v")

        if t == "number":
            try:
                return abs(float(av) - float(bv)) < 1e-4
            except (TypeError, ValueError):
                pass

        if t in ("Vector3", "Vector2"):
            axes = ("X", "Y", "Z") if t == "Vector3" else ("X", "Y")
            return all(
                abs(float(av.get(ax, 0)) - float(bv.get(ax, 0))) < 1e-4
                for ax in axes
            )

        if t == "Color3":
            return (av.get("R") == bv.get("R") and
                    av.get("G") == bv.get("G") and
                    av.get("B") == bv.get("B"))

        if t == "CFrame":
            return _cframe_equal(av, bv)

        # UDim, UDim2, string, boolean, Enum, BrickColor, dict, …
        return av == bv

    @staticmethod
    def _typed_display(val: Any) -> str:
        """Human-readable string for a typed envelope {t, v}."""
        if val is None:
            return "nil"

        t, v = val["t"], val.get("v")

        if t == "boolean":
            return "true" if v else "false"
        if t in ("number", "string", "Enum"):
            return str(v)
        if t == "Vector3":
            return f"({float(v.get('X', 0)):.3f}, {float(v.get('Y', 0)):.3f}, {float(v.get('Z', 0)):.3f})"
        if t == "Vector2":
            return f"({float(v.get('X', 0)):.3f}, {float(v.get('Y', 0)):.3f})"
        if t == "Color3":
            return f"rgb({v.get('R')}, {v.get('G')}, {v.get('B')})"
        if t == "UDim":
            return f"{{{v.get('Scale')},{v.get('Offset')}}}"
        if t == "UDim2":
            x, y = v.get("X", {}), v.get("Y", {})
            return f"{{{x.get('Scale')},{x.get('Offset')}}},{{{y.get('Scale')},{y.get('Offset')}}}"
        if t == "CFrame":
            p = v.get("Position", {})
            return f"CFrame({float(p.get('X', 0)):.2f},{float(p.get('Y', 0)):.2f},{float(p.get('Z', 0)):.2f})"
        return str(v)

    @staticmethod
    def compare_properties(old: dict, new: dict) -> dict:
        """Compare two flat key→typed-value dicts.
        Diff output uses display strings for the plugin."""
        changes: dict[str, dict[str, Any]] = {}
        all_keys = set(old) | set(new)

        for key in all_keys:
            old_val = old.get(key)
            new_val = new.get(key)

            if old_val is None and new_val is not None:
                changes[key] = {
                    "old": None,
                    "new": DiffEngine._typed_display(new_val),
                    "changeType": "added",
                }
            elif old_val is not None and new_val is None:
                changes[key] = {
                    "old": DiffEngine._typed_display(old_val),
                    "new": None,
                    "changeType": "removed",
                }
            elif not DiffEngine._typed_equal(old_val, new_val):
                changes[key] = {
                    "old": DiffEngine._typed_display(old_val),
                    "new": DiffEngine._typed_display(new_val),
                    "changeType": "modified",
                }

        return changes

    @staticmethod
    def compare_tags(old_tags: list, new_tags: list) -> dict:
        """Return ``{added: [...], removed: [...]}``."""
        old_set = set(old_tags or [])
        new_set = set(new_tags or [])
        return {
            "added": sorted(new_set - old_set),
            "removed": sorted(old_set - new_set),
        }

    def compare_instances(
        self,
        old_data: Optional[dict],
        new_data: Optional[dict],
    ) -> Optional[dict]:
        """Compare two serialized instances (without children).
        Returns a diff dict or ``None`` if nothing changed."""

        def _silk_of(data: dict) -> str:
            silk = data.get("silkId")
            if silk:
                return silk
            attrs = data.get("attributes") or {}
            for key in ("SilkDiffId", "PestoId"):
                sid = attrs.get(key)
                if isinstance(sid, dict):
                    sid = sid.get("v")
                if sid:
                    return sid
            return ""

        if old_data is None and new_data is not None:
            return {
                "path": new_data.get("path", ""),
                "name": new_data.get("name", ""),
                "className": new_data.get("className", ""),
                "silkId": _silk_of(new_data),
                "status": "added",
            }
        if old_data is not None and new_data is None:
            return {
                "path": old_data.get("path", ""),
                "name": old_data.get("name", ""),
                "className": old_data.get("className", ""),
                "silkId": _silk_of(old_data),
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
            prop_changes or attr_changes
            or tag_changes["added"] or tag_changes["removed"]
            or source_changed
        )
        if not has_changes:
            return None

        result: dict[str, Any] = {
            "path": new_data.get("path", ""),
            "name": new_data.get("name", ""),
            "className": new_data.get("className", ""),
            "silkId": _silk_of(new_data),
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

    def compare_trees(
        self,
        old_tree: Optional[dict],
        new_tree: Optional[dict],
    ) -> list[dict]:
        """Recursively diff two instance trees."""
        diffs: list[dict] = []

        root_diff = self.compare_instances(old_tree, new_tree)
        if root_diff:
            diffs.append(root_diff)

        old_children = {c["path"]: c for c in (old_tree or {}).get("children", [])}
        new_children = {c["path"]: c for c in (new_tree or {}).get("children", [])}

        for path in sorted(set(old_children) | set(new_children)):
            diffs.extend(self.compare_trees(
                old_children.get(path), new_children.get(path)))

        return diffs

    @staticmethod
    def summarize(diffs: list[dict]) -> str:
        """One-line human-readable summary."""
        if not diffs:
            return "No changes detected."
        added = sum(1 for d in diffs if d.get("status") == "added")
        removed = sum(1 for d in diffs if d.get("status") == "removed")
        modified = sum(1 for d in diffs if d.get("status") == "modified")
        parts = []
        if added: parts.append(f"{added} added")
        if modified: parts.append(f"{modified} modified")
        if removed: parts.append(f"{removed} removed")
        return f"{', '.join(parts)} ({len(diffs)} total)"


def _cframe_equal(a: dict, b: dict) -> bool:
    """Compare two CFrame value dicts with float epsilon."""
    for axis in ("X", "Y", "Z"):
        try:
            if abs(float(a.get("Position", {}).get(axis, 0)) -
                   float(b.get("Position", {}).get(axis, 0))) > 1e-4:
                return False
        except (TypeError, ValueError):
            return False

    # Orientation matrix
    for r in (0, 1, 2):
        for c in (0, 1, 2):
            try:
                if abs(float(a.get("Orientation", {}).get(f"R{r}{c}", 0)) -
                       float(b.get("Orientation", {}).get(f"R{r}{c}", 0))) > 1e-4:
                    return False
            except (TypeError, ValueError):
                return False

    # RightVector / UpVector / LookVector
    for vec in ("RightVector", "UpVector", "LookVector"):
        for axis in ("X", "Y", "Z"):
            try:
                if abs(float(a.get(vec, {}).get(axis, 0)) -
                       float(b.get(vec, {}).get(axis, 0))) > 1e-4:
                    return False
            except (TypeError, ValueError):
                return False

    return True

"""
SilkDiff Server

HTTP server that sits between the Roblox Studio plugin and the
local filesystem.

Endpoints:
    GET  /api/status   - health check
    POST /api/push     - write instance changes to local files
    GET  /api/pull     - read local files and return them + diffs
    POST /api/diff     - compare Roblox state against local files
    POST /api/export   - full game export (writes whole tree)
    POST /api/confirm  - acknowledge an approved diff
"""

import json
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Any

from .config import Config
from .file_manager import FileManager
from .diff_engine import DiffEngine
from .serializer import Serializer


def _get_silk_id(inst: dict) -> str:
    """Extract the silk id from a serialized instance (typed envelope aware)."""
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


class SilkDiffHandler(BaseHTTPRequestHandler):
    """Request handler - dependencies injected as class attributes."""

    # Set by create_server() before the server starts
    config: Config
    file_manager: FileManager
    diff_engine: DiffEngine
    serializer: Serializer

    # ------------------------------------------------------------------
    # helpers
    # ------------------------------------------------------------------

    def _send_json(self, status: int, data: Any) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        return json.loads(raw) if raw else {}

    def _log_error(self, exc: Exception) -> None:
        """Log a traceback to stderr when debug mode is enabled."""
        if self.config.debug:
            traceback.print_exc()

    # ------------------------------------------------------------------
    # routing
    # ------------------------------------------------------------------

    def do_GET(self):  # noqa: N802
        routes = {
            "/api/status": self._handle_status,
            "/api/pull": self._handle_pull,
        }
        handler = routes.get(self.path)
        if handler:
            handler()
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self):  # noqa: N802
        routes = {
            "/api/push": self._handle_push,
            "/api/pull": self._handle_pull,
            "/api/diff": self._handle_diff,
            "/api/export": self._handle_export,
            "/api/confirm": self._handle_confirm,
        }
        handler = routes.get(self.path)
        if handler:
            handler()
        else:
            self._send_json(404, {"error": "Not found"})

    # Allow CORS pre-flight
    def do_OPTIONS(self):  # noqa: N802
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    # ------------------------------------------------------------------
    # endpoint implementations
    # ------------------------------------------------------------------

    def _handle_status(self):
        """GET /api/status"""
        self._send_json(200, {
            "status": "ok",
            "name": "SilkDiff Server",
            "version": "0.1.0",
            "project_dir": str(self.file_manager.project_dir),
        })

    def _handle_push(self):
        """POST /api/push - write changes to local files.

        Accepts either:
          - full instance dicts (legacy / non-staged flow), or
          - staged diff entries: {path, status, propertyChanges, ...,
            instance: {full serialized instance}} — only the staged parts
            are merged into the local files.
        """
        try:
            body = self._read_body()
            items = body.get("data", [])

            written = 0
            for item in items:
                # Staged diff entries carry an "instance" attachment and
                # a "status" field
                if isinstance(item, dict) and "status" in item and "path" in item:
                    self.file_manager.apply_diff(item)
                    written += 1
                else:
                    instance_data = item.get("instance", item)
                    self.file_manager.write_instance(instance_data)
                    written += 1

            self._send_json(200, {
                "status": "ok",
                "message": f"Wrote {written} instance(s)",
                "written": written,
            })
        except Exception as exc:
            self._log_error(exc)
            self._send_json(500, {"error": str(exc)})

    def _handle_pull(self):
        """GET or POST /api/pull

        GET  – returns raw local instances (no diff computed).
        POST – accepts current Roblox state in body.data, computes a diff
               of (roblox_current vs local_files) and returns diff entries
               so the plugin can show exactly what would change.
        """
        try:
            # Read local file map once
            local_map: dict = {}
            for path in self.file_manager.get_all_instance_paths():
                inst = self.file_manager.read_instance(path)
                if inst:
                    local_map[path] = inst

            # GET – plain list, no diff
            if self.command == "GET":
                self._send_json(200, {
                    "status": "ok",
                    "data": list(local_map.values()),
                    "entries": [],
                    "count": len(local_map),
                })
                return

            # POST – flatten incoming Roblox tree and compute diffs
            body = self._read_body()
            roblox_trees = body.get("data", [])

            roblox_map: dict = {}

            def _flatten(tree: dict) -> None:
                if not tree:
                    return
                path = tree.get("path", "")
                if path:
                    roblox_map[path] = tree
                for child in tree.get("children", []):
                    _flatten(child)

            for svc_tree in roblox_trees:
                _flatten(svc_tree)

            # Match Roblox instances to local instances by SilkDiffId first
            # (survives renames / moves), falling back to path matching.
            # Index local instances by their silk id.
            local_by_silk: dict = {}
            for path, inst in local_map.items():
                silk = _get_silk_id(inst)
                if silk:
                    local_by_silk[silk] = (path, inst)

            # Pair up: roblox instance ↔ local instance
            roblox_unmatched: dict = dict(roblox_map)
            pairs: list = []  # (roblox_path, local_path, roblox_inst, local_inst)

            for rpath, rinst in roblox_map.items():
                r_silk = _get_silk_id(rinst)
                matched = None
                if r_silk and r_silk in local_by_silk:
                    lpath, linst = local_by_silk[r_silk]
                    # Same silk id but different path ⇒ rename / move
                    if lpath != rpath:
                        matched = (lpath, linst)
                    elif lpath in roblox_map:
                        matched = (lpath, linst)
                # Fall back to exact path match
                if matched is None and rpath in local_map:
                    matched = (rpath, local_map[rpath])

                if matched:
                    lpath, linst = matched
                    pairs.append((rpath, lpath, rinst, linst))
                    roblox_unmatched.pop(rpath, None)

            # old = roblox, new = local  →  "added" means local has it, Roblox doesn't
            diffs = []

            # Paired instances: compare directly (catches renames as "modified")
            for rpath, lpath, rinst, linst in pairs:
                diff = self.diff_engine.compare_instances(rinst, linst)
                if diff:
                    diffs.append(diff)

            # Unmatched roblox instances → removed from local
            for rpath, rinst in roblox_unmatched.items():
                diff = self.diff_engine.compare_instances(rinst, None)
                if diff:
                    diffs.append(diff)

            # Local instances never matched → added (only in local)
            matched_local_paths = {lp for _, lp, _, _ in pairs}
            for lpath, linst in local_map.items():
                if lpath not in matched_local_paths:
                    diff = self.diff_engine.compare_instances(None, linst)
                    if diff:
                        diffs.append(diff)

            summary = self.diff_engine.summarize(diffs)

            self._send_json(200, {
                "status": "ok",
                "entries": diffs,
                "summary": summary,
                "instances": list(local_map.values()),
                "count": len(diffs),
            })
        except Exception as exc:
            self._log_error(exc)
            self._send_json(500, {"error": str(exc)})

    def _handle_diff(self):
        """POST /api/diff - compare Roblox data against local files."""
        try:
            body = self._read_body()
            roblox_items = body.get("data", [])

            diffs = []
            for roblox_item in roblox_items:
                inst = roblox_item.get("instance", roblox_item)

                # Prefer SilkDiffId-based lookup (survives renames / moves)
                silk_id = inst.get("silkId") or (inst.get("attributes") or {}).get("SilkDiffId")
                if silk_id:
                    local_path = self.file_manager.find_by_silk_id(silk_id)
                    local_inst = self.file_manager.read_instance(local_path) if local_path else None
                else:
                    local_inst = self.file_manager.read_instance(inst.get("path", ""))

                diff = self.diff_engine.compare_instances(local_inst, inst)
                if diff:
                    diffs.append(diff)

            summary = self.diff_engine.summarize(diffs)

            self._send_json(200, {
                "status": "ok",
                "entries": diffs,
                "summary": summary,
                "count": len(diffs),
            })
        except Exception as exc:
            self._log_error(exc)
            self._send_json(500, {"error": str(exc)})

    def _handle_export(self):
        """POST /api/export - full game export (wipes + rebuilds)."""
        try:
            body = self._read_body()
            services = body.get("data", [])

            # Wipe existing service folders so this is a clean rebuild
            self.file_manager.clear_service_roots(services)

            total = 0
            for tree in services:
                self.file_manager.write_tree(tree)
                total += self._count(tree)

            self._send_json(200, {
                "status": "ok",
                "message": f"Exported {total} instance(s) (full rebuild)",
                "written": total,
            })
        except Exception as exc:
            self._log_error(exc)
            self._send_json(500, {"error": str(exc)})

    def _handle_confirm(self):
        """POST /api/confirm - acknowledge a user-approved diff."""
        try:
            self._send_json(200, {
                "status": "ok",
                "message": "Diff confirmed",
            })
        except Exception as exc:
            self._log_error(exc)
            self._send_json(500, {"error": str(exc)})

    # ------------------------------------------------------------------
    # helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _count(tree: dict) -> int:
        n = 1
        for child in tree.get("children", []):
            n += SilkDiffHandler._count(child)
        return n

    def log_message(self, fmt, *args):
        """Prefix every log line with [SilkDiff]."""
        print(f"[SilkDiff] {args[0]} {args[1]} {args[2]}")


# ------------------------------------------------------------------
# factory
# ------------------------------------------------------------------

def create_server(config: Config) -> HTTPServer:
    """Build a ready-to-start HTTPServer with all dependencies wired."""
    SilkDiffHandler.config = config
    SilkDiffHandler.file_manager = FileManager(config)
    SilkDiffHandler.diff_engine = DiffEngine()
    SilkDiffHandler.serializer = Serializer(config)

    return HTTPServer((config.host, config.port), SilkDiffHandler)

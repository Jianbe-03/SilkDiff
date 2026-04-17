"""
SilkDiff - CLI entry point

All silk functionality is accessed through sub-commands:

    silk server              Start the SilkDiff HTTP server
    silk create              Create a new instance on disk
    silk rename              Rename an existing instance
    silk move                Move an instance to a new parent
    silk update              Update SilkDiff to the latest version
    silk uninstall           Remove SilkDiff from this machine
    silk version             Print the current version

Aliases for server: start, open, conn
"""

import argparse
import sys
import os

# Make sure the silk package is importable regardless of install location
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from silk import __version__
from silk.commands.server import cmd_server
from silk.commands.create import cmd_create
from silk.commands.rename import cmd_rename
from silk.commands.move import cmd_move
from silk.commands.update import cmd_update
from silk.commands.uninstall import cmd_uninstall

BANNER = r"""
  ╔══════════════════════════════════════╗
  ║         🧵  SilkDiff  v{ver}         ║
  ║    Local sync tool for Roblox        ║
  ╚══════════════════════════════════════╝
""".format(ver=__version__)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="silk",
        description="SilkDiff - local sync tool for Roblox Studio",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=BANNER,
    )
    parser.add_argument(
        "--version", "-v",
        action="version",
        version=f"SilkDiff {__version__}",
    )

    sub = parser.add_subparsers(dest="command", help="Available commands")

    # ── server ──────────────────────────────────────────────────
    p_server = sub.add_parser(
        "server", aliases=["start", "open", "conn"],
        help="Start the SilkDiff HTTP server",
    )
    p_server.add_argument("--host", default="127.0.0.1",
                          help="Host to bind to (default: 127.0.0.1)")
    p_server.add_argument("--port", type=int, default=6969,
                          help="Port to listen on (default: 6969)")
    p_server.add_argument("--project", default=os.getcwd(),
                          help="Project directory (default: current dir)")

    # ── create ──────────────────────────────────────────────────
    p_create = sub.add_parser(
        "create",
        help="Create a new Roblox instance on disk",
    )
    p_create.add_argument("--Class", dest="class_name", required=True,
                          help="ClassName of the instance (e.g. Script, Part, Folder)")
    p_create.add_argument("--Parent", dest="parent", required=True,
                          help="Path to the parent (e.g. ./ServerScriptService or Workspace/Models)")
    p_create.add_argument("--Name", dest="name", default=None,
                          help="Name of the instance (defaults to ClassName)")

    # ── rename ──────────────────────────────────────────────────
    p_rename = sub.add_parser(
        "rename",
        help="Rename an existing instance",
    )
    p_rename.add_argument("--Instance", dest="instance", required=True,
                          help="Path to the instance (e.g. ./ServerScriptService/MyScript)")
    p_rename.add_argument("--Name", dest="name", required=True,
                          help="New name for the instance")

    # ── move ────────────────────────────────────────────────────
    p_move = sub.add_parser(
        "move",
        help="Move an instance to a new parent",
    )
    p_move.add_argument("--Instance", dest="instance", required=True,
                        help="Path to the instance (e.g. ./ServerScriptService/MyScript)")
    p_move.add_argument("--NewParent", dest="new_parent", required=True,
                        help="Path to the new parent (e.g. ./ReplicatedStorage)")

    # ── update ──────────────────────────────────────────────────
    sub.add_parser(
        "update",
        help="Update SilkDiff to the latest version from GitHub",
    )

    # ── uninstall ───────────────────────────────────────────────
    sub.add_parser(
        "uninstall",
        help="Remove SilkDiff from this machine",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    cmd = args.command

    # server / start / open / conn all route to the same handler
    if cmd in ("server", "start", "open", "conn"):
        cmd_server(args)
    elif cmd == "create":
        cmd_create(args)
    elif cmd == "rename":
        cmd_rename(args)
    elif cmd == "move":
        cmd_move(args)
    elif cmd == "update":
        cmd_update(args)
    elif cmd == "uninstall":
        cmd_uninstall(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()

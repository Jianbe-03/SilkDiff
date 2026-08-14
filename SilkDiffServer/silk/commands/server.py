"""
silk server - Start the SilkDiff HTTP server.

Aliases: silk start, silk open, silk conn
"""

from silk.config import Config
from silk.server import create_server
from silk import __version__


BANNER = r"""
  ╔══════════════════════════════════════╗
  ║         🧵  SilkDiff  v{ver}         ║
  ║    Local sync server for Roblox      ║
  ╚══════════════════════════════════════╝
""".format(ver=__version__)


def cmd_server(args):
    """Start the SilkDiff HTTP server."""
    config = Config(
        host=args.host,
        port=args.port,
        project_dir=args.project,
        debug=args.debug,
    )

    print(BANNER)
    print(f"  Host:        {config.host}")
    print(f"  Port:        {config.port}")
    print(f"  Project dir: {config.project_dir}")
    print(f"  URL:         http://{config.host}:{config.port}")
    print()
    print("  Waiting for connections from Roblox Studio …")
    print()

    server = create_server(config)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[SilkDiff] Shutting down …")
        server.shutdown()
        print("[SilkDiff] Goodbye!")

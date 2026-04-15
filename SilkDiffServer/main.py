"""
SilkDiff Server — Entry Point

Starts the local HTTP server that communicates with the
Roblox Studio plugin over HTTP.

Usage:
    python main.py                           # defaults (127.0.0.1:6969)
    python main.py --port 8080               # custom port
    python main.py --host 0.0.0.0            # all interfaces
    python main.py --project /path/to/game   # custom project dir

To compile into a portable executable:
    pip install pyinstaller
    pyinstaller --onedir main.py --name silkdiff
"""

import argparse
import os
import sys

# Make sure the silk package is importable
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from silk.config import Config
from silk.server import create_server

BANNER = r"""
╔══════════════════════════════════════════╗
║           🧵  SilkDiff Server            ║
║     Local sync server for Roblox         ║
╚══════════════════════════════════════════╝
"""


def main():
    parser = argparse.ArgumentParser(
        description="SilkDiff — local sync server for Roblox Studio",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host address to bind to (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=6969,
        help="Port to listen on (default: 6969)",
    )
    parser.add_argument(
        "--project",
        default=os.getcwd(),
        help="Project directory where instance files live (default: cwd)",
    )

    args = parser.parse_args()

    config = Config(
        host=args.host,
        port=args.port,
        project_dir=args.project,
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


if __name__ == "__main__":
    main()

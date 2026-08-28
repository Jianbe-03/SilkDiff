# 🧵 SilkDiff

**Sync your Roblox game with local files using diffs.**

SilkDiff lets you export your entire Roblox game to your local machine, then push and pull changes with a visual diff review - just like version control, but for Roblox instances.

---

## Installation

SilkDiff ships as a standalone binary - **no Python, no dependencies required.**

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.sh | bash
```

For a local, user-only dev install from your current checkout:

```bash
./install-local.sh
```

That installs a `silk-local` command backed directly by `SilkDiffServer/`, so local code changes are available immediately without creating a release first.

To install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.sh | bash -s -- v0.1.0
```

To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.sh | bash -s -- --uninstall
```

To remove the local dev launcher:

```bash
./install-local.sh --uninstall
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.ps1 | iex
```

To install a specific version:

```powershell
.\install.ps1 -Version v0.1.0
```

To uninstall:

```powershell
.\install.ps1 -Uninstall
```

### What the installer does

| Step | macOS/Linux | Windows |
|------|-------------|---------|
| Downloads | `silk-<os>-<arch>.tar.gz` from the latest GitHub Release | `silk-windows-amd64.zip` |
| Installs to | `~/.local/share/silkdiff/` | `%LOCALAPPDATA%\SilkDiff\` |
| Adds to PATH | Symlink at `~/.local/bin/silk` + shell profile | `setx PATH` |

> **Supported platforms:** macOS arm64 (Apple Silicon), macOS Intel via Rosetta 2, Linux amd64, Windows amd64.

---

## CLI Reference

```
silk <command> [flags]
```

| Command | Flags | Description |
|---------|-------|-------------|
| `silk server` | `--host`, `--port`, `--project` | Start the local HTTP server |
| `silk start` / `silk open` / `silk conn` | same as server | Aliases for `server` |
| `silk create` | `--Class` *, `--Parent` *, `--Name` | Create a new instance on disk |
| `silk rename` | `--Instance` *, `--Name` * | Rename an instance |
| `silk move` | `--Instance` *, `--NewParent` * | Move an instance to a new parent |
| `silk update` | - | Download and install the latest release |
| `silk uninstall` | - | Remove SilkDiff from this machine |

\* required flag

### Examples

```bash
# Start the server pointing at your project folder
silk server --project /path/to/MyGame

# Create a Script inside ServerScriptService
silk create --Class Script --Parent ./ServerScriptService --Name PlayerController

# Create a non-script instance (generates properties + attributes + tags, no source file)
silk create --Class Part --Parent ./Workspace --Name Platform

# Rename an existing instance
silk rename --Instance ./ServerScriptService/OldName --Name NewName

# Move an instance to a different parent
silk move --Instance ./ServerScriptService/OldScript --NewParent ./ReplicatedStorage

# Check for and install the latest version
silk update

# Remove SilkDiff
silk uninstall
```

`silk create` supports every Roblox class and pre-fills all default properties for that class automatically.

---

## Architecture

```
SilkDiff/
├── install.sh                       # One-liner installer for macOS / Linux
├── install.ps1                      # One-liner installer for Windows
├── install-local.sh                 # Local development launcher installer
├── .github/
│   └── workflows/
│       └── release.yml              # CI: builds & releases binaries on tag push
│
├── SilkDiffRBLX/                    # Roblox Studio plugin (Pesto-managed)
│   └── ServerStorage/
│       └── SilkDiffPlugin/          # Main plugin Script
│           ├── __Source__.luau       # Plugin entry point
│           └── Modules/             # All plugin modules
│               ├── Signal/          # Custom event system
│               ├── Settings/        # 8 configurable options
│               ├── InstanceWatcher/ # Watches 18 game services for changes
│               ├── Serializer/      # Converts instances to JSON
│               ├── HttpClient/      # HTTP communication with server
│               ├── DiffEngine/      # Compares instance states
│               ├── Popup/           # Confirmation and notification dialogs
│               ├── Console/         # Docked SilkDiff log console
│               └── UI/              # Toolbar, Settings panel, and Diff viewer
│
├── SilkDiffDev/                     # Development assets and icon uploader
│   ├── icons/                        # SVG toolbar icon sources
│   ├── silkdiff.svg                  # SilkDiff logo source
│   └── upload_icons.py               # Converts and uploads toolbar icons
│
└── SilkDiffServer/                  # Python source (compiled into the binary)
    ├── main.py                      # CLI entry point
    ├── requirements.txt
    └── silk/
        ├── config.py                # Server configuration
        ├── server.py                # HTTP server & endpoints
        ├── file_manager.py          # Read/write instance files
        ├── diff_engine.py           # Generate diffs
        ├── serializer.py            # YAML/JSON conversion
        ├── default_properties.py    # Default properties for every Roblox class
        └── commands/
            ├── server.py            # silk server
            ├── create.py            # silk create
            ├── rename.py            # silk rename
            ├── move.py              # silk move
            ├── update.py            # silk update
            └── uninstall.py         # silk uninstall
```

## How It Works

### Push (Roblox → Local)
1. The plugin watches all game instances for changes
2. You click **Push** in the toolbar
3. Changed instances are serialized and sent to the local server
4. The server compares them against your local files
5. A diff is shown in the **Diff Viewer**
6. You approve → changes are written to disk

### Pull (Local → Roblox)
1. You click **Pull** in the toolbar
2. The server reads all local files and sends the state
3. The plugin shows a diff of what will change
4. You approve → changes are applied in Roblox Studio

### Export (Full Game → Local)
1. Click **Export** to dump the entire game tree to local files
2. Every instance becomes a folder with:
   - `__Properties__.yaml` - instance properties
   - `__Attributes__.yaml` - custom attributes
   - `__Tags__.yaml` - CollectionService tags
   - `__Source__.luau` - source code (scripts only)

---

## Quick Start

### 1. Install SilkDiff

See the [Installation](#installation) section above for the one-liner commands.

After installation, verify it works:

```bash
silk --version
```

### 2. Start the local server

```bash
silk server --project /path/to/MyGame
```

Defaults to `127.0.0.1:6969` and the current working directory if no flags are given.

### 3. Install the plugin

The plugin lives in `SilkDiffRBLX/ServerStorage/SilkDiffPlugin`. Sync it
into Roblox Studio using Pesto, then export it as a `.rbxm` plugin file,
or run it directly in a development place.

### 3. Use the toolbar

Once loaded, the **SilkDiff** toolbar appears in Studio with four buttons:

| Button     | Action |
|------------|--------|
| **Push**   | Send your changes to local files (with diff review) |
| **Pull**   | Apply local file changes to Roblox (with diff review) |
| **Export**  | Full game export to local files |
| **Settings**| Open the settings panel |

---

## Plugin Settings

| Setting              | Default            | Description |
|----------------------|--------------------|-------------|
| Server Host          | `127.0.0.1`        | Address of the SilkDiff server |
| Server Port          | `6969`             | Port of the SilkDiff server |
| Properties Extension | `.yaml`            | File format for properties (`.yaml` or `.json`) |
| Source Extension     | `.luau`            | Script file extension (`.luau`, `.lua`, or `.txt`) |
| Properties File Name | `__Properties__`   | Base name for properties files |
| Attributes File Name | `__Attributes__`   | Base name for attributes files |
| Tags File Name       | `__Tags__`         | Base name for tags files |
| Source File Name     | `__Source__`        | Base name for source files |

All settings are persisted across Studio sessions.

---

## Building & Releasing

Binaries are built automatically by GitHub Actions whenever a version tag is pushed.

### Release a new version

1. Update `__version__` in `SilkDiffServer/silk/__init__.py`
2. Commit and tag:

```bash
git add SilkDiffServer/silk/__init__.py
git commit -m "chore: bump version to v0.2.0"
git tag v0.2.0
git push && git push --tags
```

The CI workflow (`.github/workflows/release.yml`) will:
- Build `silk` for **macOS arm64**, **macOS amd64**, **Linux amd64**, and **Windows amd64**
- Create a GitHub Release with all 4 artifacts attached

### Build locally (for development)

```bash
cd SilkDiffServer
pip install pyinstaller
pyinstaller --name silk --onedir --clean --noconfirm main.py
./dist/silk/silk --version
```

---

## Plugin Modules

### Signal
Lightweight event/signal system for decoupled inter-module communication.

### Settings
Manages all 8 plugin settings with persistent storage via `plugin:GetSetting` / `SetSetting`.

### InstanceWatcher
Connects to `.Changed`, `.AttributeChanged`, `.ChildAdded`, and `.ChildRemoved` signals across all game services. Maintains a list of everything that changed since the last sync.

### Serializer
Converts Roblox instances into JSON-safe dictionaries. Handles all common Roblox types (Vector3, CFrame, Color3, UDim2, enums, etc.). Tracks a curated set of properties per ClassName.

### HttpClient
Talks to the local Python server over HTTP. All endpoints are JSON-based.

### DiffEngine
Compares two instance states (properties, attributes, tags, source) and produces structured diff entries with a human-readable summary.

### UI
Creates the Studio toolbar, a dockable Settings panel with inputs and dropdowns for all 8 settings, and a floating Diff Viewer that shows colour-coded change entries with approve/cancel buttons.

---

## Server API

| Method | Endpoint        | Description |
|--------|-----------------|-------------|
| GET    | `/api/status`   | Health check |
| POST   | `/api/push`     | Write instance changes to local files |
| GET    | `/api/pull`     | Read all local instances |
| POST   | `/api/diff`     | Compare Roblox state vs local files |
| POST   | `/api/export`   | Full game tree export |
| POST   | `/api/confirm`  | Confirm an approved diff |

---

## License

Private project - all rights reserved.

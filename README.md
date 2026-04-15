# 🧵 SilkDiff

**Sync your Roblox game with local files using diffs.**

SilkDiff lets you export your entire Roblox game to your local machine, then push and pull changes with a visual diff review — just like version control, but for Roblox instances.

---

## Architecture

```
SilkDiff/
├── SilkDiffRBLX/                    # Roblox Studio plugin (Pesto-managed)
│   └── ServerStorage/
│       └── SilkDiffPlugin/          # Main plugin Script
│           ├── __Source__.luau       # Plugin entry point
│           └── Modules/             # All plugin modules
│               ├── Signal/          # Custom event system
│               ├── Settings/        # 8 configurable options
│               ├── InstanceWatcher/ # Watches game tree for changes
│               ├── Serializer/      # Converts instances to JSON
│               ├── HttpClient/      # HTTP communication with server
│               ├── DiffEngine/      # Compares instance states
│               └── UI/              # Toolbar, Settings panel, Diff viewer
│
└── SilkDiffServer/                  # Local Python server
    ├── main.py                      # Entry point
    ├── requirements.txt
    └── silk/
        ├── config.py                # Server configuration
        ├── server.py                # HTTP server & endpoints
        ├── file_manager.py          # Read/write instance files
        ├── diff_engine.py           # Generate diffs
        └── serializer.py            # YAML/JSON conversion
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
   - `__Properties__.yaml` — instance properties
   - `__Attributes__.yaml` — custom attributes
   - `__Tags__.yaml` — CollectionService tags
   - `__Source__.luau` — source code (scripts only)

---

## Quick Start

### 1. Start the local server

```bash
cd SilkDiffServer
pip install -r requirements.txt
python main.py
```

Options:
```bash
python main.py --host 127.0.0.1 --port 6969 --project /path/to/game
```

### 2. Install the plugin

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

## Building the Server Executable

To distribute the server as a standalone `.exe`:

```bash
pip install pyinstaller
pyinstaller --onedir main.py --name silkdiff
```

The executable will be in `dist/silkdiff/`.

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

Private project — all rights reserved.

# SilkDiffDev

Developer tooling for SilkDiff — **not shipped to users**. This folder holds
the SVG source icons for the Studio toolbar buttons and a script that converts
them to PNGs and uploads them to Roblox.

## What's here

| Path | Purpose |
|------|---------|
| `icons/` | SVG sources for the toolbar buttons (Push, Watchless Push, Pull, Export, Settings, Console) |
| `upload_icons.py` | Converts SVGs → PNGs and uploads them via the Open Cloud Assets API |
| `requirements.txt` | Dev-only Python dependencies (`cairosvg`) |

The icons are based on [Feather Icons](https://feathericons.com/) (MIT licensed).

## Getting an Open Cloud API key

1. Go to **https://create.roblox.com/credentials** (Creator Dashboard → Credentials)
2. Click **Create API Key**
3. Give it a name (e.g. `SilkDiff Dev`)
4. Under **Permissions**, add the **Assets API** with **Write** access
5. Optionally restrict **Allowed IP addresses** (recommended; leave empty only for local dev)
6. Click **Create** and **copy the key immediately** — it is only shown once

You also need your **User ID** (or a **Group ID** if uploading to a group):

- User ID: open your profile at `https://www.roblox.com/users/<ID>/profile` — the number in the URL
- Group ID: open your group at `https://www.roblox.com/groups/<ID>/...` — the number in the URL

## Usage

```bash
cd SilkDiffDev
pip install -r requirements.txt

# Upload to your personal account
python upload_icons.py --api-key <KEY> --user-id <USER_ID>

# Or upload to a group
python upload_icons.py --api-key <KEY> --group-id <GROUP_ID>
```

The API key can also be set via the `ROBLOX_OPEN_CLOUD_API_KEY` environment
variable instead of passing `--api-key`.

## Wiring the icons into the plugin

The script prints a Lua snippet like this:

```lua
local ICONS = {
    console = "rbxassetid://123456788",
    push = "rbxassetid://123456789",
    watchlessPush = "rbxassetid://123456790",
    pull = "rbxassetid://123456791",
    export = "rbxassetid://123456792",
    settings = "rbxassetid://123456793",
}
```

Paste those IDs into
`SilkDiffRBLX/ServerStorage/SilkDiffPlugin/Modules/UI/__Source__.luau`
in the `_createToolbarButtons()` calls (the third argument of each
`CreateButton(...)`). The uploader creates `Image` assets, so these returned
IDs can be used directly as `rbxassetid://...` values.

> Note: Roblox does **not** support SVG uploads — only PNG/JPG/BMP. That's why
> the SVGs live here and get rasterized to PNGs before uploading. Also, image
> assets can't be updated in place; if you change an icon, upload it again and
> swap the new asset ID in the plugin.

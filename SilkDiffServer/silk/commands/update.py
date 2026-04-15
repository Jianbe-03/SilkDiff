"""
silk update — Update SilkDiff to the latest version from GitHub.

Downloads the latest platform-specific binary release and replaces
the current installation.  No Python or pip needed on the user's machine.
"""

import json
import os
import platform
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from silk import __version__

# ── GitHub repository ───────────────────────────────────────────
GITHUB_REPO = "SilkDiff/SilkDiff"  # owner/repo — update when published
GITHUB_API_LATEST = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"


def _parse_version(v: str) -> tuple:
    """Turn '0.1.0' into (0, 1, 0) for comparison."""
    parts = v.strip().lstrip("v").split(".")
    return tuple(int(p) for p in parts if p.isdigit())


def _detect_platform() -> str:
    """Return a string like 'macos-arm64', 'linux-amd64', 'windows-amd64'."""
    system = platform.system()
    machine = platform.machine().lower()

    os_map = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}
    os_name = os_map.get(system)
    if os_name is None:
        raise RuntimeError(f"Unsupported OS: {system}")

    if machine in ("arm64", "aarch64"):
        arch = "arm64"
    elif machine in ("x86_64", "amd64", "x64"):
        arch = "amd64"
    else:
        raise RuntimeError(f"Unsupported architecture: {machine}")

    return f"{os_name}-{arch}"


def _get_install_dir() -> Path:
    """Return the directory that contains the silk binary.

    For a PyInstaller --onedir build the executable lives directly
    in the install directory (e.g. ~/.local/share/silkdiff/silk).
    When running from source the install dir is SilkDiffServer/.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    else:
        # Dev / source mode — silk package is SilkDiffServer/silk/
        return Path(__file__).resolve().parent.parent.parent


def _get_latest_release() -> dict | None:
    """Fetch the latest release object from the GitHub API."""
    try:
        req = urllib.request.Request(
            GITHUB_API_LATEST,
            headers={
                "Accept": "application/vnd.github.v3+json",
                "User-Agent": "SilkDiff",
            },
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except Exception as exc:
        print(f"[SilkDiff] ✗ Could not reach GitHub: {exc}")
        return None


def _find_asset_url(release: dict, plat: str) -> str | None:
    """Find the download URL for the matching platform asset."""
    ext = "zip" if plat.startswith("windows") else "tar.gz"
    target_name = f"silk-{plat}.{ext}"

    for asset in release.get("assets", []):
        if asset["name"] == target_name:
            return asset["browser_download_url"]
    return None


# ── Command handler ─────────────────────────────────────────────

def cmd_update(_args):
    """Check for updates and install the latest binary release."""
    print(f"[SilkDiff] Current version: {__version__}")
    print("[SilkDiff] Checking for updates …")

    release = _get_latest_release()
    if release is None:
        return

    latest_tag = release.get("tag_name", "")
    latest_version = latest_tag.lstrip("v")

    if _parse_version(latest_version) <= _parse_version(__version__):
        print(f"[SilkDiff] ✓ Already up to date (latest: {latest_tag})")
        return

    print(f"[SilkDiff] New version available: {latest_tag}")

    try:
        plat = _detect_platform()
    except RuntimeError as exc:
        print(f"[SilkDiff] ✗ {exc}")
        return

    print(f"[SilkDiff] Platform: {plat}")

    asset_url = _find_asset_url(release, plat)
    if asset_url is None:
        available = [a["name"] for a in release.get("assets", [])]
        print(f"[SilkDiff] ✗ No binary found for '{plat}' in {latest_tag}")
        print(f"[SilkDiff]   Available: {available}")
        return

    print(f"[SilkDiff] Downloading …")

    install_dir = _get_install_dir()

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        archive_path = tmp_path / "silk_update_archive"
        extract_path = tmp_path / "extracted"
        extract_path.mkdir()

        # ── Download ────────────────────────────────────────────
        try:
            urllib.request.urlretrieve(asset_url, str(archive_path))
        except Exception as exc:
            print(f"[SilkDiff] ✗ Download failed: {exc}")
            return

        # ── Extract ─────────────────────────────────────────────
        print("[SilkDiff] Extracting …")
        if plat.startswith("windows"):
            with zipfile.ZipFile(str(archive_path), "r") as zf:
                zf.extractall(str(extract_path))
        else:
            with tarfile.open(str(archive_path), "r:gz") as tf:
                tf.extractall(str(extract_path))

        # The archive contains a silk/ subdirectory
        inner = extract_path / "silk"
        if not inner.exists():
            inner = extract_path  # fallback: flat archive

        # ── Replace installation ────────────────────────────────
        print(f"[SilkDiff] Installing to {install_dir} …")

        if platform.system() == "Windows":
            # Windows locks the running .exe — use a delayed batch
            # script that waits for us to exit, then copies the files.
            bat_path = tmp_path / "_silk_update.bat"
            bat_lines = [
                "@echo off",
                "timeout /t 2 /nobreak >nul",
                f'xcopy /E /Y /Q "{inner}\\*" "{install_dir}\\" >nul',
                f"echo [SilkDiff] Updated to {latest_tag}!",
                'del "%~f0"',
            ]
            bat_path.write_text("\r\n".join(bat_lines), encoding="utf-8")
            os.startfile(str(bat_path))  # noqa: S606
            print(f"[SilkDiff] ✓ Update staged — it will finish momentarily.")
            print("[SilkDiff]   Please restart silk after the update completes.")
            sys.exit(0)
        else:
            # Unix: we can replace files in-place while running (onedir)
            backup = install_dir.parent / "silkdiff_backup"
            try:
                if backup.exists():
                    shutil.rmtree(backup)
                shutil.copytree(install_dir, backup)

                for item in inner.iterdir():
                    dest = install_dir / item.name
                    if item.is_dir():
                        if dest.exists():
                            shutil.rmtree(dest)
                        shutil.copytree(item, dest)
                    else:
                        shutil.copy2(item, dest)
                        if item.name == "silk":
                            dest.chmod(
                                dest.stat().st_mode
                                | stat.S_IEXEC
                                | stat.S_IXGRP
                                | stat.S_IXOTH
                            )

                # Success — remove backup
                shutil.rmtree(backup)
            except Exception as exc:
                print(f"[SilkDiff] ✗ Update failed: {exc}")
                if backup.exists():
                    print(f"[SilkDiff]   Backup preserved at: {backup}")
                return

    print(f"[SilkDiff] ✓ Updated to {latest_tag}!")
    print("[SilkDiff]   Restart silk to use the new version.")

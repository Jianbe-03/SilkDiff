"""
silk uninstall — Remove SilkDiff from this machine.

Removes:
    1. The silk symlink / PATH entry
    2. The installation directory (after confirmation)
"""

import os
import platform
import shutil
import sys
from pathlib import Path


def _get_install_dir() -> Path:
    """Return the directory that contains the silk binary."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    else:
        # Dev / source mode
        return Path(__file__).resolve().parent.parent.parent


def cmd_uninstall(_args):
    """Remove SilkDiff from the machine."""
    print("[SilkDiff] Uninstalling SilkDiff …")
    print()

    install_dir = _get_install_dir()
    system = platform.system()

    # ── Remove symlink / PATH entry ─────────────────────────────
    if system == "Windows":
        # Try to remove install dir from user PATH via registry
        install_str = str(install_dir)
        try:
            import winreg

            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Environment",
                0,
                winreg.KEY_ALL_ACCESS,
            )
            user_path, _ = winreg.QueryValueEx(key, "PATH")
            parts = [p for p in user_path.split(";") if p and p != install_str]
            winreg.SetValueEx(key, "PATH", 0, winreg.REG_EXPAND_SZ, ";".join(parts))
            winreg.CloseKey(key)
            print(f"  ✓ Removed {install_str} from user PATH")
        except Exception:
            print(f"  ⚠ Could not auto-remove from PATH.")
            print(f"    Please remove '{install_str}' from your system PATH manually.")
    else:
        # macOS / Linux — remove symlink
        symlink = Path.home() / ".local" / "bin" / "silk"
        if symlink.is_symlink() or symlink.exists():
            symlink.unlink()
            print(f"  ✓ Removed symlink: {symlink}")
        else:
            print(f"  - Symlink not found: {symlink}")

    # ── Remove install directory ────────────────────────────────
    print(f"\n  Install directory: {install_dir}")

    try:
        answer = input("  Remove the installation directory? [y/N] ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        answer = "n"

    if answer in ("y", "yes"):
        if system == "Windows":
            # Can't delete the running .exe on Windows — use delayed batch
            import tempfile

            bat = Path(tempfile.gettempdir()) / "_silk_uninstall.bat"
            bat.write_text(
                f"@echo off\n"
                f"timeout /t 2 /nobreak >nul\n"
                f'rmdir /S /Q "{install_dir}"\n'
                f"echo [SilkDiff] Uninstall complete.\n"
                f'del "%~f0"\n',
                encoding="utf-8",
            )
            os.startfile(str(bat))  # noqa: S606
            print(f"  ✓ Directory will be removed momentarily.")
        else:
            shutil.rmtree(install_dir, ignore_errors=True)
            print(f"  ✓ Removed {install_dir}")
    else:
        print(f"  - Kept {install_dir}")

    print()
    print("[SilkDiff] ✓ Uninstall complete.")
    if system != "Windows":
        print("[SilkDiff]   You may want to remove the PATH entry from your shell profile.")

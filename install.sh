#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# SilkDiff Installer — macOS & Linux
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Jianbe-03/SilkDiff/main/install.sh | bash
#   curl -fsSL … | bash -s -- v0.2.0          # specific version
#   curl -fsSL … | bash -s -- --uninstall     # remove
#
# What it does:
#   1. Detects your OS and architecture
#   2. Downloads the matching silk binary from GitHub Releases
#   3. Extracts to ~/.local/share/silkdiff/
#   4. Symlinks silk into ~/.local/bin/ (on PATH)
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="Jianbe-03/SilkDiff"
INSTALL_DIR="${HOME}/.local/share/silkdiff"
BIN_DIR="${HOME}/.local/bin"
BINARY_NAME="silk"

# ── Colours ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}[SilkDiff]${RESET} $1"; }
ok()   { echo -e "${GREEN}[SilkDiff] ✓${RESET} $1"; }
err()  { echo -e "${RED}[SilkDiff] ✗${RESET} $1"; }
warn() { echo -e "${YELLOW}[SilkDiff] ⚠${RESET} $1"; }

# ── Detect platform ────────────────────────────────────────────
detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin) os="macos" ;;
        Linux)  os="linux" ;;
        *)      err "Unsupported OS: $os"; exit 1 ;;
    esac

    case "$arch" in
        arm64|aarch64)  arch="arm64" ;;
        x86_64|amd64)   arch="amd64" ;;
        *)              err "Unsupported architecture: $arch"; exit 1 ;;
    esac

    # No hosted Intel Mac runner exists — the ARM64 binary runs on Intel
    # Macs transparently via Rosetta 2, so map macos-amd64 → macos-arm64.
    if [[ "$os" == "macos" && "$arch" == "amd64" ]]; then
        warn "Intel Mac detected — using ARM64 binary (runs via Rosetta 2)."
        arch="arm64"
    fi

    # Linux ARM64 builds are not provided yet
    if [[ "$os" == "linux" && "$arch" == "arm64" ]]; then
        err "Linux ARM64 is not supported yet. Only amd64 builds are available."
        exit 1
    fi

    echo "${os}-${arch}"
}

# ── Build download URL ─────────────────────────────────────────
get_download_url() {
    local platform="$1"
    local version="${2:-latest}"

    if [[ "$version" == "latest" ]]; then
        echo "https://github.com/${REPO}/releases/latest/download/silk-${platform}.tar.gz"
    else
        echo "https://github.com/${REPO}/releases/download/${version}/silk-${platform}.tar.gz"
    fi
}

# ── Download helper ─────────────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$dest"
    else
        err "Neither curl nor wget found. Please install one."
        exit 1
    fi
}

# ── Uninstall ───────────────────────────────────────────────────
do_uninstall() {
    echo ""
    echo -e "${BOLD}  🧵 SilkDiff Uninstaller${RESET}"
    echo ""

    if [[ -L "${BIN_DIR}/${BINARY_NAME}" || -f "${BIN_DIR}/${BINARY_NAME}" ]]; then
        rm -f "${BIN_DIR}/${BINARY_NAME}"
        ok "Removed symlink: ${BIN_DIR}/${BINARY_NAME}"
    else
        info "Symlink not found (already removed): ${BIN_DIR}/${BINARY_NAME}"
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        ok "Removed: ${INSTALL_DIR}"
    else
        info "Install directory not found (already removed): ${INSTALL_DIR}"
    fi

    ok "SilkDiff uninstalled."
    info "You may want to remove the PATH entry from your shell profile."
    echo ""
    exit 0
}

# ── Main install ────────────────────────────────────────────────
main() {
    local version="${1:-latest}"

    echo ""
    echo -e "${BOLD}  🧵 SilkDiff Installer${RESET}"
    echo ""

    local platform
    platform="$(detect_platform)"
    info "Platform: ${platform}"

    local url
    url="$(get_download_url "$platform" "$version")"
    info "Downloading: ${url}"

    # Temp dir with cleanup trap
    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '$tmp'" EXIT

    # Download
    download "$url" "$tmp/silk.tar.gz"
    ok "Downloaded"

    # Extract
    info "Installing to ${INSTALL_DIR} …"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    tar xzf "$tmp/silk.tar.gz" -C "$INSTALL_DIR" --strip-components=1
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    ok "Extracted"

    # Symlink
    mkdir -p "$BIN_DIR"
    ln -sf "$INSTALL_DIR/$BINARY_NAME" "$BIN_DIR/$BINARY_NAME"
    ok "Linked: ${BIN_DIR}/${BINARY_NAME} → ${INSTALL_DIR}/${BINARY_NAME}"

    # Ensure ~/.local/bin is on PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "${BIN_DIR} is not on your PATH."

        local shell_profile=""
        case "${SHELL:-/bin/bash}" in
            */zsh)  shell_profile="$HOME/.zshrc" ;;
            */fish) shell_profile="$HOME/.config/fish/config.fish" ;;
            *)      shell_profile="$HOME/.bashrc" ;;
        esac

        if [[ -n "$shell_profile" ]] && ! grep -q "silkdiff" "$shell_profile" 2>/dev/null; then
            {
                echo ""
                echo "# SilkDiff"
                echo "export PATH=\"\$PATH:${BIN_DIR}\""
            } >> "$shell_profile"
            ok "Added to ${shell_profile}"
            info "Run:  source ${shell_profile}"
        fi
    else
        ok "Already on PATH"
    fi

    # Verify
    echo ""
    if "$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null; then
        echo ""
        ok "Installation complete!"
    else
        warn "Binary exists but --version check failed."
    fi

    echo ""
    info "Run:  silk --help"
    echo ""
}

# ── Entry point ─────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    do_uninstall
fi

main "$@"

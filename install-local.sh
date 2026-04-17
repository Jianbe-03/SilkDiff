#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${REPO_ROOT}/SilkDiffServer"
REQUIREMENTS_FILE="${SERVER_DIR}/requirements.txt"
VENV_DIR="${SERVER_DIR}/.venv"
LOCAL_INSTALL_DIR="${HOME}/.local/share/silkdiff-local"
BIN_DIR="${HOME}/.local/bin"
DEFAULT_COMMAND_NAME="silk-local"

COMMAND_NAME="${DEFAULT_COMMAND_NAME}"
UNINSTALL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}[SilkDiff Local]${RESET} $1"; }
ok()   { echo -e "${GREEN}[SilkDiff Local] ✓${RESET} $1"; }
warn() { echo -e "${YELLOW}[SilkDiff Local] ⚠${RESET} $1"; }
err()  { echo -e "${RED}[SilkDiff Local] ✗${RESET} $1"; }

usage() {
    cat <<EOF
Usage: ./install-local.sh [options]

Installs a local, user-only SilkDiff launcher backed by this checkout.

Options:
  --command NAME   Command name to install in ~/.local/bin (default: ${DEFAULT_COMMAND_NAME})
  --uninstall      Remove the local launcher created by this script
  --help           Show this help message

Notes:
  - Uses ${SERVER_DIR}
  - Creates/updates ${VENV_DIR}
  - Installs a launcher in ~/.local/bin/${DEFAULT_COMMAND_NAME} by default
  - Reads directly from this repo, so your local code changes are picked up immediately
EOF
}

find_python() {
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return
    fi

    if command -v python >/dev/null 2>&1; then
        command -v python
        return
    fi

    err "Python 3 is required but was not found on PATH."
    exit 1
}

detect_shell_profile() {
    case "${SHELL:-/bin/bash}" in
        */zsh)  echo "${HOME}/.zshrc" ;;
        */fish) echo "${HOME}/.config/fish/config.fish" ;;
        *)      echo "${HOME}/.bashrc" ;;
    esac
}

ensure_path() {
    if [[ ":$PATH:" == *":${BIN_DIR}:"* ]]; then
        ok "${BIN_DIR} already on PATH"
        return
    fi

    warn "${BIN_DIR} is not on your PATH."

    local shell_profile
    shell_profile="$(detect_shell_profile)"

    if [[ ! -f "${shell_profile}" ]]; then
        touch "${shell_profile}"
    fi

    if ! grep -q "SilkDiff Local" "${shell_profile}" 2>/dev/null; then
        {
            echo ""
            echo "# SilkDiff Local"
            echo "export PATH=\"\$PATH:${BIN_DIR}\""
        } >> "${shell_profile}"
        ok "Added ${BIN_DIR} to ${shell_profile}"
    else
        warn "PATH marker already exists in ${shell_profile}; reload your shell if needed."
    fi

    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${YELLOW}│ ACTION REQUIRED: reload your shell to use silk-local          │${RESET}"
    echo -e "${YELLOW}│                                                               │${RESET}"
    echo -e "${YELLOW}│  Run:  source ${shell_profile}${RESET}"
    echo -e "${YELLOW}│                                                               │${RESET}"
    echo -e "${YELLOW}│  Or use the full path right now:                              │${RESET}"
    echo -e "${YELLOW}│    ${BIN_DIR}/${COMMAND_NAME} --help${RESET}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

write_launcher() {
    local launcher_path="$1"
    local python_bin="$2"

    cat > "${launcher_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SILKDIFF_DEV_INSTALL=1
export SILKDIFF_DEV_COMMAND=$(printf '%q' "${COMMAND_NAME}")
export SILKDIFF_DEV_INSTALLER=$(printf '%q' "${REPO_ROOT}/install-local.sh")
REPO_ROOT=$(printf '%q' "${REPO_ROOT}")
SERVER_DIR=$(printf '%q' "${SERVER_DIR}")
PYTHON_BIN=$(printf '%q' "${python_bin}")
exec "\$PYTHON_BIN" "\$SERVER_DIR/main.py" "\$@"
EOF

    chmod +x "${launcher_path}"
}

do_uninstall() {
    local launcher_path="${LOCAL_INSTALL_DIR}/${COMMAND_NAME}"
    local symlink_path="${BIN_DIR}/${COMMAND_NAME}"

    echo ""
    echo -e "${BOLD}  🧵 SilkDiff Local Uninstaller${RESET}"
    echo ""

    if [[ -L "${symlink_path}" || -f "${symlink_path}" ]]; then
        rm -f "${symlink_path}"
        ok "Removed launcher link: ${symlink_path}"
    else
        info "Launcher link not found: ${symlink_path}"
    fi

    if [[ -f "${launcher_path}" ]]; then
        rm -f "${launcher_path}"
        ok "Removed launcher script: ${launcher_path}"
    else
        info "Launcher script not found: ${launcher_path}"
    fi

    if [[ -d "${LOCAL_INSTALL_DIR}" ]] && [[ -z "$(ls -A "${LOCAL_INSTALL_DIR}")" ]]; then
        rmdir "${LOCAL_INSTALL_DIR}"
        ok "Removed empty directory: ${LOCAL_INSTALL_DIR}"
    fi

    warn "Kept your repo checkout and virtual environment intact."
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --command)
            if [[ $# -lt 2 ]]; then
                err "--command requires a value"
                exit 1
            fi
            COMMAND_NAME="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
done

if [[ ! -d "${SERVER_DIR}" ]]; then
    err "Expected server directory at ${SERVER_DIR}, but it was not found."
    exit 1
fi

if [[ ${UNINSTALL} -eq 1 ]]; then
    do_uninstall
    exit 0
fi

echo ""
echo -e "${BOLD}  🧵 SilkDiff Local Installer${RESET}"
echo ""

PYTHON_BOOTSTRAP="$(find_python)"
info "Using Python: ${PYTHON_BOOTSTRAP}"

if [[ ! -d "${VENV_DIR}" ]]; then
    info "Creating virtual environment at ${VENV_DIR}"
    "${PYTHON_BOOTSTRAP}" -m venv "${VENV_DIR}"
    ok "Virtual environment created"
else
    ok "Using existing virtual environment: ${VENV_DIR}"
fi

PYTHON_BIN="${VENV_DIR}/bin/python"

if [[ ! -x "${PYTHON_BIN}" ]]; then
    err "Expected Python executable at ${PYTHON_BIN}, but it is missing."
    exit 1
fi

info "Installing Python dependencies"
"${PYTHON_BIN}" -m pip install -r "${REQUIREMENTS_FILE}"
ok "Dependencies installed"

mkdir -p "${LOCAL_INSTALL_DIR}" "${BIN_DIR}"

LAUNCHER_PATH="${LOCAL_INSTALL_DIR}/${COMMAND_NAME}"
SYMLINK_PATH="${BIN_DIR}/${COMMAND_NAME}"

write_launcher "${LAUNCHER_PATH}" "${PYTHON_BIN}"
ln -sf "${LAUNCHER_PATH}" "${SYMLINK_PATH}"
ok "Installed launcher: ${SYMLINK_PATH} → ${LAUNCHER_PATH}"

ensure_path

echo ""
if "${LAUNCHER_PATH}" --version; then
    echo ""
    ok "Local install is ready"
else
    warn "Launcher was created, but the version check failed."
fi

info "Command: ${COMMAND_NAME} --help"
warn "This launcher points at ${REPO_ROOT}; if you move the repo, rerun install-local.sh."
echo ""
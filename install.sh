#!/usr/bin/env bash
# install.sh — Install s3cp to /usr/local/bin
# Usage: curl -fsSL https://raw.githubusercontent.com/AlRos14/s3cp/main/install.sh | bash

set -euo pipefail

REPO="AlRos14/s3cp"
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="s3cp"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main/${SCRIPT_NAME}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info() { echo -e "${CYAN}ℹ $*${RESET}"; }
ok()   { echo -e "${GREEN}✔ $*${RESET}"; }

# Check dependencies
for cmd in aws jq; do
  command -v "$cmd" &>/dev/null || {
    echo "✖ Required command not found: $cmd" >&2
    exit 1
  }
done

info "Downloading s3cp…"
tmp=$(mktemp)
curl -fsSL "$RAW_URL" -o "$tmp"
chmod +x "$tmp"

# Validate it's a real s3cp script
bash -n "$tmp" || { echo "✖ Downloaded script failed syntax check" >&2; rm -f "$tmp"; exit 1; }

if [[ -w "$INSTALL_DIR" ]]; then
  mv "$tmp" "${INSTALL_DIR}/${SCRIPT_NAME}"
else
  sudo mv "$tmp" "${INSTALL_DIR}/${SCRIPT_NAME}"
fi

ok "Installed to ${INSTALL_DIR}/${SCRIPT_NAME}"
echo ""
echo -e "Run ${BOLD}s3cp configure${RESET} to set up your bucket and region."

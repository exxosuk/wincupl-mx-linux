#!/usr/bin/env bash
#
# One-line install for WinCUPL on MX Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/exxosuk/wincupl-mx-linux/master/install.sh | bash
#
# Downloads this repository, then runs the installer inside it. Everything it
# needs comes with it - there is nothing else to fetch and nothing to mount.
#
set -euo pipefail

REPO="exxosuk/wincupl-mx-linux"
BRANCH="master"
TARBALL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"

echo "==> Downloading WinCUPL for MX Linux..."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL "$TARBALL" -o "$tmp/wincupl.tar.gz"; then
    echo "ERROR: could not download from GitHub. Check the network and try again." >&2
    exit 1
fi

tar -xzf "$tmp/wincupl.tar.gz" -C "$tmp"
src=$(find "$tmp" -maxdepth 1 -type d -name "wincupl-mx-linux-*" | head -n1)
if [ -z "$src" ] || [ ! -x "$src/wincupl-install.sh" ]; then
    echo "ERROR: the download does not look right - no installer inside it." >&2
    exit 1
fi

echo "==> Unpacked $(du -sh "$src" | cut -f1). Installing..."
exec "$src/wincupl-install.sh" install

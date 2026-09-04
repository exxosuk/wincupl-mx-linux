#!/usr/bin/env bash
#
# wincupl-install.sh
#
# Sets up Atmel WinCUPL 5.30.4 - the classic version - under Wine on MX Linux,
# with a menu entry and a desktop icon.
#
#   ./wincupl-install.sh install [/path/to/Wincupl]   (default: ./Wincupl or ~/Desktop/Wincupl)
#   ./wincupl-install.sh uninstall
#
# WHY THIS EXISTS.  WinCUPL is a Visual Basic 6 program from 2014. Wine ships
# no VB6 runtime, so double-clicking it does nothing at all: it fails to
# resolve MSVBVM60.DLL and exits before it can draw a window or print an
# error. Get past that and it stops again on "runtime error 339" for the VB6
# common controls. Both come from Microsoft redistributables that winetricks
# knows how to fetch. Neither problem announces itself, which is why this
# script exists rather than a paragraph of instructions.
#
set -euo pipefail

PREFIX="$HOME/.wine-wincupl"
APPS_DIR="$HOME/.local/share/applications"
DESKTOP_DIR="$HOME/Desktop"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$APPS_DIR/wincupl.desktop"
SERIAL="60008009"

usage() {
    echo "Usage: $0 [install [source-folder]|uninstall]"
    exit 1
}

find_source() {
    # The program ships with this installer, so it works on a machine that has
    # never seen WinCUPL and needs nothing mounted. A path can still be given
    # to install from a copy of your own.
    here="$(cd "$(dirname "$0")" && pwd)"
    for c in "${1:-}" "$here/wincupl-files" "./Wincupl" "$HOME/Wincupl"; do
        [ -n "$c" ] && [ -f "$c/WinCupl/Wincupl.exe" ] && { printf '%s' "$c"; return; }
    done
    echo "ERROR: no WinCUPL files found. Expected them beside this script in" >&2
    echo "wincupl-files/, or pass a path: $0 install /path/to/Wincupl" >&2
    exit 1
}

do_install() {
    src=$(find_source "${1:-}")
    echo "==> Using WinCUPL from: $src"

# Is 32-bit Wine present?
#
# NOT the same question as "is the wine32 package installed". WinCUPL needs the
# 32-bit loader, and there is more than one way to have it: Debian's wine32,
# wine32-development, or a WineHQ build (wine-staging, wine-devel) that installs
# under /opt and carries its own i386 tree. This PC runs winehq-staging 9.21 with
# wine-staging-i386:i386 and has full 32-bit support, but no package called
# wine32 -- so a dpkg name check said "missing" and would have gone on to apt
# install wine32:i386 on top of a working WineHQ install.
#
# So ask the filesystem what the wine on PATH actually has, and only fall back to
# package names for wine builds old enough not to use the i386-windows layout.
wine_has_32bit() {
    command -v wine >/dev/null 2>&1 || return 1
    local bin root d
    bin=$(readlink -f "$(command -v wine)")
    root=$(dirname "$(dirname "$bin")")          # /opt/wine-staging, or /usr
    for d in "$root/lib/wine/i386-windows" \
             "$root/lib64/wine/i386-windows" \
             "$root/lib/i386-linux-gnu/wine" \
             /usr/lib/wine/i386-windows \
             /usr/lib/i386-linux-gnu/wine; do
        [ -d "$d" ] && return 0
    done
    # wine 5 and older: no i386-windows tree, so trust the package name.
    dpkg -l wine32 wine32-development 2>/dev/null | grep -q '^ii' && return 0
    return 1
}

    echo "==> Checking for Wine..."
    ARCH=$(dpkg --print-architecture)

    if [ "$ARCH" = "amd64" ]; then
        # 64-bit system: need both wine64 and wine32.
        # WinCUPL is a 32-bit executable. On a 64-bit system Wine needs the
        # 32-bit loader (wine32) to run it through WoW64. Without it the
        # process exits silently -- "failed to load syswow64/ntdll.dll" in
        # the log, nothing on screen.
        if ! command -v wine >/dev/null 2>&1; then
            sudo apt update
            sudo apt install -y wine
        fi
        if ! wine_has_32bit; then
            echo "    Installing wine32 (needed for 32-bit programs on 64-bit)..."
            sudo dpkg --add-architecture i386 2>/dev/null || true
            sudo apt update
            if ! sudo apt install -y wine32:i386 2>/dev/null; then
                # MX Linux ships custom libsystemd0/libudev1 that conflict
                # with Debian's i386 versions. apt refuses to install wine32
                # because it cannot reconcile the version numbers. Work around
                # it by installing the two blocking i386 deps directly, then
                # retry wine32.
                echo "    apt failed -- working around MX systemd version conflict..."
                tmp=$(mktemp -d)
                (cd "$tmp" && apt download libsystemd0:i386 libudev1:i386 2>/dev/null \
                    && sudo dpkg --force-depends -i libsystemd0_*_i386.deb libudev1_*_i386.deb) \
                    && sudo apt install -y --fix-broken wine32:i386 \
                    || { echo "ERROR: could not install wine32. Install it by hand and re-run." >&2; exit 1; }
                rm -rf "$tmp"
            fi
        fi
    else
        # 32-bit system (i386): wine32 is the native package.
        if ! command -v wine >/dev/null 2>&1; then
            sudo apt update
            sudo apt install -y wine32
        fi
    fi
    command -v wrestool >/dev/null 2>&1 || sudo apt install -y icoutils

    # A default (64-bit) prefix, not a 32-bit one. WinCUPL is a 32-bit
    # program and a 32-bit prefix looks like the obvious choice, but tested
    # both ways it only works in the 64-bit one: in a win32 prefix the process
    # starts, sits idle and never draws a window. The 32-bit runtimes land in
    # syswow64 and WoW64 runs the program perfectly well.
    if [ ! -d "$PREFIX" ]; then
        echo "==> Creating a dedicated Wine prefix at $PREFIX..."
        WINEPREFIX="$PREFIX" wineboot --init 2>&1 | grep -v '^wine:' || true
        # Give wineboot time to finish writing the prefix.
        WINEPREFIX="$PREFIX" wineserver -w 2>/dev/null || sleep 3
    fi

    echo "==> Installing the VB6 runtime and controls..."
    # Everything WinCUPL needs is bundled in deps/. No network downloads,
    # no winetricks. The list came from reading the EXE's imports (objdump -p),
    # not from clicking until it stopped complaining.
    #
    # msvbvm60.dll  - VB6 runtime; without it the program exits silently
    # comctl32.ocx  - common controls; "runtime error 339" without it
    # comdlg32.ocx  - common dialogs; same error on file-open
    # richtx32.ocx  - rich text editor; without it a .PLD opens into nothing
    # tabctl32.ocx  - tabbed dialogs
    # mscomctl.ocx  - MS common controls (treeview, listview)
    # mscomct2.ocx  - MS common controls 2 (date picker, etc.)
    # dwsbc32.ocx   - Desaware StatusBar; "Dwsbc32.ocx missing" without it
    # dwspy32.dll   - Desaware Spy (needed by dwsbc32)
    # mfc40.dll     - MFC runtime (needed by dwsbc32)
    # comct232.ocx  - common controls 2 (animation, up-down)
    #
    # Sources: msvbvm60.dll and the OCXs are from the VB6 SP6 redistributable
    # (Microsoft KB2708437). dwsbc32/dwspy32 are Desaware controls that shipped
    # with WinCUPL's original Windows installer. See README.md for details.
    depsdir="$(cd "$(dirname "$0")" && pwd)/deps"
    sys32="$PREFIX/drive_c/windows/syswow64"
    [ -d "$sys32" ] || sys32="$PREFIX/drive_c/windows/system32"

    for f in msvbvm60.dll comctl32.ocx comdlg32.ocx richtx32.ocx tabctl32.ocx \
             mscomctl.ocx mscomct2.ocx dwsbc32.ocx dwspy32.dll mfc40.dll comct232.ocx; do
        if [ -f "$depsdir/$f" ]; then
            cp "$depsdir/$f" "$sys32/$f"
            echo "    + $f"
        else
            echo "    WARNING: $f not found in deps/. WinCUPL may not start."
        fi
    done

    echo "==> Copying WinCUPL into the prefix as C:\\Wincupl..."
    target="$PREFIX/drive_c/Wincupl"
    rm -rf "$target"
    cp -a "$src" "$target"
    chmod -R u+rw "$target"

    # WinCUPL looks for its compilers and fitters on PATH, exactly as its
    # Windows installer used to set up.
    WINEPREFIX="$PREFIX" wine reg add "HKCU\\Environment" /v PATH \
        /t REG_SZ /d "C:\\Wincupl\\WINCUPL\\EXE;C:\\Wincupl\\WINCUPL\\FITTERS;C:\\Wincupl\\Shared" /f >/dev/null 2>&1 || true
    # LIBCUPL must name the library FILE, not the folder holding it. Without
    # it the compiler stops with "Unable to read environment variable:
    # LIBCUPL"; pointed at the folder it gets further and then fails with
    # "could not open: C:\Wincupl\Shared", which reads like a permissions
    # problem and is not one.
    WINEPREFIX="$PREFIX" wine reg add "HKCU\\Environment" /v LIBCUPL \
        /t REG_SZ /d "C:\\Wincupl\\Shared\\cupl.dl" /f >/dev/null 2>&1 || true

    echo "==> Registering the controls..."
    # Copying files is not enough for an ActiveX control: the Windows installer
    # registered them, so we must too. It has to be the 32-bit regsvr32 - the
    # 64-bit one answers "failed to load DLL" on a 32-bit control.
    for ocx in dwsbc32.ocx comct232.ocx; do
        [ -f "$sys32/$ocx" ] || continue
        # /s or it pops a "Successfully registered" box mid-install.
        WINEPREFIX="$PREFIX" wine "C:\\windows\\syswow64\\regsvr32.exe" /s \
            "C:\\windows\\syswow64\\$ocx" >/dev/null 2>&1 \
            || WINEPREFIX="$PREFIX" wine regsvr32 /s "$ocx" >/dev/null 2>&1 || true
    done

    echo "==> Registering WinCUPL..."
    # WinCUPL stops on an organisation-and-serial box the first time it runs.
    # The serial is free and published by Microchip; there is no reason to make
    # somebody hunt for it. Found by snapshotting the prefix, registering by
    # hand and diffing: it is two string values under the name of the company
    # that wrote CUPL before Atmel bought it.
    org="${ORGANIZATION:-$USER}"
    WINEPREFIX="$PREFIX" wine reg add \
        "HKCU\\Software\\Logical Devices\\WinCupl\\5.0\\Settings" \
        /v Organization /t REG_SZ /d "$org" /f >/dev/null 2>&1 || true
    WINEPREFIX="$PREFIX" wine reg add \
        "HKCU\\Software\\Logical Devices\\WinCupl\\5.0\\Settings" \
        /v SerialNo /t REG_SZ /d "$SERIAL" /f >/dev/null 2>&1 || true

    echo "==> Creating the launcher..."
    mkdir -p "$BIN_DIR" "$APPS_DIR"
    cat > "$BIN_DIR/wincupl" <<EOF
#!/bin/sh
exec env WINEPREFIX="$PREFIX" wine "C:\\\\Wincupl\\\\WinCupl\\\\Wincupl.exe" "\$@"
EOF
    chmod +x "$BIN_DIR/wincupl"

    # The CUPL logo lives inside the executable, as it did on Windows. Pull it
    # out and install it properly, so the menu entry carries the program's own
    # icon rather than a generic gear.
    echo "==> Installing the icon..."
    icon="wincupl"
    icondir="$HOME/.local/share/icons/hicolor"
    tmpicon=$(mktemp -d)
    if wrestool -x -t 14 "$target/WinCupl/Wincupl.exe" -o "$tmpicon/wincupl.ico" 2>/dev/null \
       && icotool -x -o "$tmpicon" "$tmpicon/wincupl.ico" 2>/dev/null; then
        src=$(ls -S "$tmpicon"/*.png 2>/dev/null | head -n1)
    fi
    # Bundled copy, for a machine without icoutils or a stripped executable.
    [ -z "${src:-}" ] && [ -f "$(dirname "$0")/wincupl.png" ] && src="$(dirname "$0")/wincupl.png"
    if [ -n "${src:-}" ]; then
        for sz in 32 48 64; do
            mkdir -p "$icondir/${sz}x${sz}/apps"
            if [ "$sz" = 32 ]; then
                cp "$src" "$icondir/32x32/apps/wincupl.png"
            else
                # -filter point: this is a 32px 8-bit icon from 1999, and
                # smooth scaling turns it to mush.
                convert "$src" -filter point -resize ${sz}x${sz} \
                    "$icondir/${sz}x${sz}/apps/wincupl.png" 2>/dev/null \
                    || cp "$src" "$icondir/${sz}x${sz}/apps/wincupl.png"
            fi
        done
        gtk-update-icon-cache -f -t "$icondir" >/dev/null 2>&1 || true
    else
        icon="applications-electronics"
    fi
    rm -rf "$tmpicon"
    cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Type=Application
Name=WinCUPL
Comment=Atmel WinCUPL 5.30.4 - CUPL logic design for SPLDs and CPLDs
Exec=$BIN_DIR/wincupl
Icon=$icon
Terminal=false
Categories=Development;Electronics;
StartupNotify=true
EOF
    chmod +x "$LAUNCHER"
    if [ -d "$DESKTOP_DIR" ]; then
        cp "$LAUNCHER" "$DESKTOP_DIR/wincupl.desktop"
        chmod +x "$DESKTOP_DIR/wincupl.desktop"
    fi
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

    echo ""
    echo "==> Done. WinCUPL is in your application menu and on the desktop."
    echo "    Registered as '${ORGANIZATION:-$USER}' with Microchip's published"
    echo "    serial $SERIAL, so it will not stop and ask."
    echo "    Set ORGANIZATION=... before running to use a different name."
    echo "    Prefix: $PREFIX"
}

do_uninstall() {
    # `set -e` plus `read` is a trap: with no terminal, read returns non-zero at
    # EOF and the script dies right here -- no removal, no "Cancelled.", no error,
    # exit status 0. It looks exactly like a successful uninstall that removed
    # nothing. Keep the prompt for people, and take --yes or a non-tty as consent.
    local confirm=""
    if [ "${1:-}" = "--yes" ] || [ ! -t 0 ]; then
        confirm=y
    else
        read -r -p "Remove WinCUPL and its Wine prefix ($PREFIX)? [y/N] " confirm || confirm=""
    fi
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    rm -rf "$PREFIX"
    rm -f "$LAUNCHER" "$DESKTOP_DIR/wincupl.desktop" "$BIN_DIR/wincupl"
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    echo "WinCUPL removed. Wine itself was left installed."
}

case "${1:-install}" in
    install)   do_install "${2:-}" ;;
    uninstall) do_uninstall "${2:-}" ;;
    *)         usage ;;
esac

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

    echo "==> Checking for Wine..."
    if ! command -v wine >/dev/null 2>&1; then
        sudo dpkg --add-architecture i386
        sudo apt update
        sudo apt install -y wine
    fi
    command -v curl >/dev/null 2>&1 || sudo apt install -y curl
    command -v cabextract >/dev/null 2>&1 || sudo apt install -y cabextract
    command -v wrestool >/dev/null 2>&1 || sudo apt install -y icoutils

    echo "==> Getting winetricks (it fetches the Microsoft runtimes)..."
    winetricks_bin=$(command -v winetricks || true)
    if [ -z "$winetricks_bin" ]; then
        mkdir -p "$BIN_DIR"
        curl -sL --fail -o "$BIN_DIR/winetricks" \
            https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
        chmod +x "$BIN_DIR/winetricks"
        winetricks_bin="$BIN_DIR/winetricks"
    fi

    # A default (64-bit) prefix, not a 32-bit one. WinCUPL is a 32-bit
    # program and a 32-bit prefix looks like the obvious choice, but tested
    # both ways it only works in the 64-bit one: in a win32 prefix the process
    # starts, sits idle and never draws a window. The 32-bit runtimes land in
    # syswow64 and WoW64 runs the program perfectly well.
    if [ ! -d "$PREFIX" ]; then
        echo "==> Creating a dedicated Wine prefix at $PREFIX..."
        WINEPREFIX="$PREFIX" wineboot --init >/dev/null 2>&1
    fi

    echo "==> Installing the VB6 runtime and common controls..."
    # vb6run      - MSVBVM60.DLL, without which the program exits silently
    # comctl32ocx - COMCTL32.OCX, or it stops with "runtime error 339"
    # comdlg32ocx - COMDLG32.OCX, the same error again the moment you open a
    #               file dialog
    # richtx32    - RICHTX32.OCX, the editor. Missing, a .PLD opens into
    #               nothing and the Edit/Run/Utilities menus never appear
    # tabctl32    - TABCTL32.OCX, the tabbed dialogs
    # Each one only shows up once the previous is satisfied, which is why they
    # are all installed up front rather than waiting to be asked for. The list
    # came from reading the controls named inside Wincupl.exe, not from
    # clicking about until it stopped complaining.
    # richtx32 is the one that matters most after the runtime: it is the
    # editor control, and without it opening a .PLD silently does nothing at
    # all - the file dialog works, the file is read, and no window appears.
    WINEPREFIX="$PREFIX" "$winetricks_bin" -q \
        vb6run comctl32ocx comdlg32ocx richtx32 tabctl32 >/dev/null 2>&1 || true

    echo "==> Installing the extra controls WinCUPL needs..."
    # WinCUPL's Windows installer registered a Desaware control that does not
    # ship in the program folder: DWSBC32.OCX, which in turn needs DWSPY32.DLL
    # and MFC40.DLL. Without them the program starts and then stops on
    # "Dwsbc32.ocx missing". They are not redistributable, so they are taken
    # from a Windows installation - COPIED IN, never referenced in place, so
    # nothing here depends on that drive still being mounted afterwards.
    sys32="$PREFIX/drive_c/windows/syswow64"
    [ -d "$sys32" ] || sys32="$PREFIX/drive_c/windows/system32"
    for ocx in dwsbc32.ocx dwspy32.dll mfc40.dll comct232.ocx; do
        [ -f "$sys32/$ocx" ] && continue
        found=""
        # These ship in deps/ beside this script. Nothing is read from a
        # Windows partition during a normal install - the scan below is only a
        # rescue for someone who has deleted deps/, and even then the file is
        # COPIED IN, so the install never depends on that drive afterwards.
        for d in "$(cd "$(dirname "$0")" && pwd)/deps" "$src/deps"; do
            [ -f "$d/$ocx" ] && found="$d/$ocx" && break
        done
        if [ -z "$found" ]; then
            found=$(find /media /mnt -maxdepth 5 -ipath "*/Windows/SysWOW64/$ocx" \
                    -o -maxdepth 5 -ipath "*/Windows/System32/$ocx" 2>/dev/null | head -n1)
        fi
        if [ -n "$found" ]; then
            cp "$found" "$sys32/$ocx"
            echo "    $ocx <- $found"
        else
            echo "    WARNING: $ocx not found. WinCUPL will stop on it."
            echo "    Copy it from a Windows machine into: $(dirname "$0")/deps/"
        fi
    done
    # mfc40 can come from winetricks if no Windows install is around
    [ -f "$sys32/mfc40.dll" ] || \
        WINEPREFIX="$PREFIX" "$winetricks_bin" -q mfc40 >/dev/null 2>&1 || true

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
    read -p "Remove WinCUPL and its Wine prefix ($PREFIX)? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    rm -rf "$PREFIX"
    rm -f "$LAUNCHER" "$DESKTOP_DIR/wincupl.desktop" "$BIN_DIR/wincupl"
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    echo "WinCUPL removed. Wine itself was left installed."
}

case "${1:-install}" in
    install)   do_install "${2:-}" ;;
    uninstall) do_uninstall ;;
    *)         usage ;;
esac

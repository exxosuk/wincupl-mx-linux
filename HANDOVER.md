# WinCUPL on MX Linux — handover

repo `exxosuk/wincupl-mx-linux` · working copy `~/claude/wincupl`

## What this is

A fully self-contained installer for the classic **WinCUPL 5.30.4** under Wine.
Portable by design: every dependency is bundled in the repo, nothing is read from
the user's Windows drive, and it is expected to be installed on other machines.

One-line install:

```
curl -fsSL https://raw.githubusercontent.com/exxosuk/wincupl-mx-linux/master/install.sh | bash
```

## How it works — `wincupl-install.sh`

1. Installs `wine curl cabextract icoutils`; fetches `winetricks` if missing.
2. Creates a **64-bit** prefix and installs `vb6run comctl32ocx comdlg32ocx
   richtx32 tabctl32`.
3. Copies and registers the four remaining dependencies from the bundled `deps/`:
   `dwsbc32.ocx`, `dwspy32.dll`, `mfc40.dll`, `comct232.ocx`. It falls back to
   scanning `/media` but **always copies in** — never registers a file in place
   from someone's Windows drive, which would break the installer elsewhere.
4. Copies `wincupl-files/` to `C:\Wincupl`, sets `PATH` and
   `LIBCUPL=C:\Wincupl\Shared\cupl.dl`, writes the registration keys.
5. Extracts the CUPL logo from the EXE (`wrestool -x -t 14` then `icotool -x`)
   into hicolor 32/48/64 with `-filter point`, and installs
   `~/.local/bin/wincupl` plus desktop entries.

Verified from a clean GitHub clone: 5.4 MB tarball, 14 MB unpacked, installer
executable, all four deps present, a PLD loads and compiles.

## Notes

- `regsvr32` must be the 32-bit one for these controls even in a 64-bit prefix.
- The dependency list came from reading the EXE's imports (`objdump -p`) rather
  than chasing one error dialog at a time — do that first if a new one appears.
- WinCUPL II was tried and deliberately **removed**: the UI is unrecognisable
  next to 5.30.4 and the user does not want it. Do not reintroduce it.
- The 5.30.4 installer is copied into the repo rather than downloaded from
  Microchip at install time, in case the URL moves; the original download URL is
  credited in the README.

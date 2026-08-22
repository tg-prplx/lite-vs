# Changelog

## 1.0.3 - 2026-08-22

- Fixed Backspace, Enter, and `Ctrl+C`/interrupt handling in the integrated
  terminal panel.
- Made the terminal subclass compatible with the upstream terminal plugin's
  strict command predicate while retaining the custom animated panel.
- Added regression validation for the terminal type compatibility bridge.

## 1.0.2 - 2026-08-22

- Fixed clean-install plugin ordering on Windows, Linux, and macOS. Lite XL
  stops parsing plugin metadata at `mod-version`, so priorities now precede it.
- Disabled the stock toolbar before plugin loading and restored the activity
  bar plus non-overlapping Explorer layout on fresh profiles.
- Added a checksum-pinned open-source Inter UI font with Lite XL's bundled
  JetBrains Mono for consistent cross-platform typography.
- Added clean install/uninstall CI smoke tests for all three operating systems.

## 1.0.1 - 2026-08-21

- Replaced destructive terminal restarts with independent integrated sessions.
- Added a session selector plus active-session restart and kill actions.
- Preserved running sessions when another session is closed or exits.
- Preferred Windows PowerShell over the terminal plugin's `cmd.exe` fallback,
  with an opt-out setting.

## 1.0.0 - 2026-08-21

- Initial cross-platform release.
- Responsive workbench layout, animated sidebars and integrated bottom panel.
- Dark palette and corrected Python highlighting.
- Safe installers and exact-file uninstallers for Windows, Linux, and macOS.
- Original unbranded title-bar mark and no vendored binaries or fonts.

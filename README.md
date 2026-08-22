# lite-vs

<img width="2559" height="1439" alt="image" src="https://github.com/user-attachments/assets/0fc8cc51-8e0d-4956-b49e-57ca1fcefca7" />


[Русская версия](README.ru.md)

An independent, cross-platform workbench layer for Lite XL 2.1.8+. It adds a
compact borderless title bar, responsive editor tabs, animated sidebars and
bottom panel, command and file pickers, multi-session integrated terminals, source
control, extension management, and a matching dark syntax palette.

The project is runtime-only: it does not patch Lite XL's installed core files.
Every project file lives in the normal Lite XL user directory and can be
removed cleanly.

## Quick install

Close Lite XL before installing, then restart it when the script finishes.
Existing files with the same names are backed up automatically.

### Windows

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.ps1 | iex
```

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.sh | sh
```

### macOS

The same installer supports Intel and Apple Silicon:

```sh
curl -fsSL https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.sh | sh
```

The installer downloads the matching official LPM binary when one is not
already available, then uses it to install the cross-platform terminal, source
control, plugin manager, navigation, JSON, and icon dependencies. It also
downloads a checksum-pinned copy of the open-source Inter variable font and
its SIL Open Font License so the workbench has consistent metrics on every OS.

## Auditable local install

If you prefer to inspect everything first:

```sh
git clone https://github.com/tg-prplx/lite-vs.git
cd lite-vs
```

Windows:

```powershell
.\scripts\install.ps1
```

Linux or macOS:

```sh
./scripts/install.sh
```

If Lite XL uses a non-default user directory, pass it explicitly:

```powershell
.\scripts\install.ps1 -UserDir 'D:\portable\lite-xl-data'
```

```sh
LITE_USERDIR=/path/to/lite-xl-data ./scripts/install.sh
```

Use `-SkipDependencies` on Windows or `LITE_VS_SKIP_DEPENDENCIES=1` on Unix
only when all dependencies are already installed.

## Uninstall or restore

From a local clone:

```powershell
.\scripts\uninstall.ps1
# Or restore the newest pre-install backup:
.\scripts\uninstall.ps1 -RestoreLatestBackup
```

```sh
./scripts/uninstall.sh
# Or restore the newest pre-install backup:
./scripts/uninstall.sh --restore-latest
```

Uninstall removes only the eight files owned or installed by this project.
Shared LPM
dependencies and the `lite-vs-backups` directory are intentionally kept.

## Main shortcuts

On Windows and Linux, use `Ctrl`; on macOS, use `Cmd` for the matching primary
bindings.

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Command palette | `Ctrl+Shift+P` | `Cmd+Shift+P` |
| Files | `Ctrl+Shift+E` | `Cmd+Shift+E` |
| Search | `Ctrl+Shift+F` | `Cmd+Shift+F` |
| Source control | `Ctrl+Shift+G` | `Cmd+Shift+G` |
| Run and debug | `Ctrl+Shift+D` | `Cmd+Shift+D` |
| Extensions | `Ctrl+Shift+X` | `Cmd+Shift+X` |
| Toggle sidebar | `Ctrl+B` | `Cmd+B` |
| Toggle bottom panel | `Ctrl+J` | `Cmd+J` |
| New integrated terminal | `Ctrl+Shift+\`` | `Cmd+Shift+\`` |

## Integrated terminal

The terminal stays inside the animated bottom panel. The `+` button creates an
independent shell instead of restarting the current one; use the shell name in
the panel header to switch sessions. The trash button kills only the active
session. Clear, restart, kill, and hide actions are also available from the
adjacent menu.

On Windows, lite-vs prefers Windows PowerShell when the terminal plugin still
uses the default `COMSPEC` (`cmd.exe`), matching the usual modern-editor setup.
To keep Command Prompt instead, add this to your Lite XL `init.lua`:

```lua
config.plugins.lite_vs_terminal = { prefer_powershell = false }
```

Explicit non-default shells remain unchanged on every platform.

## Portability and project boundaries

- No vendor logos, product icons, screenshots, native DLLs, EXEs, user
  sessions, histories, logs, or editor binaries are included.
- The `<>` title-bar mark and all Lua files in this repository are original
  project assets.
- Optional functionality is installed from its upstream source through LPM;
  those packages are not redistributed here and retain their own licenses.
- The installer retrieves Inter from a pinned Google Fonts revision under the
  SIL Open Font License. Code uses JetBrains Mono from Lite XL. No proprietary
  system font or font path is required.
- Window movement uses Lite XL's native hit testing. An optional module named
  `lite_vs_native_drag` may provide more caption regions, but is not required
  or distributed.

This is an independent community project. It is not endorsed by or affiliated
with Lite XL or any other editor vendor.

## Development

Run the local validation script from PowerShell:

```powershell
.\scripts\check.ps1
```

The CI checks Lua and shell syntax, PowerShell parser errors, Lite XL plugin
load order, clean install/uninstall behavior on Windows, Linux, and macOS,
accidental binary assets, private Lite XL state, hard-coded Windows font paths,
and branded icon identifiers.

## License

Project-owned code is available under the [MIT License](LICENSE). See
[THIRD_PARTY.md](THIRD_PARTY.md) for dependency boundaries.

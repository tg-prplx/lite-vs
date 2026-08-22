# Third-party boundary

This repository contains only project-owned Lua, documentation, and installer
code. It does not vendor the projects listed below.

The installer may retrieve these packages through the Lite XL Plugin Manager:

- `font_symbols_nerdfont_mono_regular`
- `navigate`
- `nerdicons`
- `plugin_manager`
- `scm`
- `tab_switcher`
- `terminal`
- `json`

Their source, package metadata, authorship, and license terms remain with their
respective upstream projects and can be reviewed in the official
[Lite XL plugins repository](https://github.com/lite-xl/lite-xl-plugins) and
[Lite XL Plugin Manager](https://github.com/lite-xl/lite-xl-plugin-manager).

Lite XL itself is a separate MIT-licensed project available from the
[official Lite XL repository](https://github.com/lite-xl/lite-xl). The name is
used only to identify compatibility with the host application.

The installer downloads the Inter variable font and its license from a pinned
revision of the [Google Fonts repository](https://github.com/google/fonts).
Inter is copyright The Inter Project Authors and is licensed under the SIL Open
Font License 1.1. The downloaded files are verified by SHA-256 and are not
stored in this repository.

The code font is JetBrains Mono and the fallback UI font is Fira Sans. Both are
provided by the user's Lite XL installation and remain under their respective
upstream licenses; this repository does not redistribute them.

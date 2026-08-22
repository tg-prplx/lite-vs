-- priority:0
-- mod-version:3
-- Project-owned bootstrap. It changes only runtime configuration and never
-- edits Lite XL's installation or the user's init.lua.

local core = require "core"
local config = require "core.config"
local style = require "core.style"

config.borderless = true
config.plugins.toolbarview = false
config.plugins.treeview = { size = 280 * SCALE }

-- Use the same open fonts on every platform. Inter is installed by the
-- lite-vs installers under the SIL Open Font License; Lite XL's bundled
-- Fira Sans remains a safe fallback for manual/incomplete installations.
local font_root = USERDIR .. PATHSEP .. "fonts" .. PATHSEP .. "lite-vs"
local inter_path = font_root .. PATHSEP .. "Inter.ttf"
local ui_path = system.get_file_info(inter_path)
  and inter_path or (DATADIR .. PATHSEP .. "fonts" .. PATHSEP .. "FiraSans-Regular.ttf")
local code_path = DATADIR .. PATHSEP .. "fonts" .. PATHSEP .. "JetBrainsMono-Regular.ttf"
local text_options = {
  antialiasing = PLATFORM == "Windows" and "subpixel" or "grayscale",
  hinting = "slight",
}

style.font = renderer.font.load(ui_path, 15 * SCALE, text_options)
style.big_font = style.font:copy(46 * SCALE)
style.code_font = renderer.font.load(code_path, 16 * SCALE, text_options)
core.lite_vs_ui_font = style.font
core.lite_vs_ui_bold_font = renderer.font.load(ui_path, 15 * SCALE, {
  antialiasing = text_options.antialiasing,
  hinting = text_options.hinting,
  bold = true,
})

-- Apply the bundled palette before the layout plugins are loaded.
core.reload_module("colors.lite-vs-dark")

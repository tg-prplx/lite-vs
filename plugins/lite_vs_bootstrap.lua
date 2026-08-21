-- mod-version:3
-- priority:99
-- Project-owned bootstrap. It changes only runtime configuration and never
-- edits Lite XL's installation or the user's init.lua.

local core = require "core"
local config = require "core.config"

config.borderless = true
config.plugins.toolbarview = false

-- Apply the bundled palette before the layout plugins are loaded.
core.reload_module("colors.lite-vs-dark")

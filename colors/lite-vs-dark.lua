-- Original dark workbench theme for Lite XL 2.1.x.
-- The palette is independently defined for this project and uses only the
-- token classes exposed by Lite XL.

local style = require "core.style"
local common = require "core.common"

local function color(value)
  return { common.color(value) }
end

-- Compact workbench geometry.
style.padding = {
  x = common.round(12 * SCALE),
  y = common.round(6 * SCALE)
}
style.divider_size = common.round(1 * SCALE)
style.scrollbar_size = common.round(5 * SCALE)
style.expanded_scrollbar_size = common.round(12 * SCALE)
style.caret_width = common.round(2 * SCALE)
style.tab_width = common.round(180 * SCALE)

-- Workbench surfaces.
style.background = color "#1F1F1F"       -- editor and active tab
style.background2 = color "#181818"      -- title bar, tabs, explorer, status bar
style.background3 = color "#222222"      -- command palette, menus, popovers
style.text = color "#CCCCCC"
style.caret = color "#FFFFFF"
style.accent = color "#0078D4"
style.dim = color "#9D9D9D"
style.divider = color "#2B2B2B"
style.selection = color "#264F78"
style.line_number = color "#6E7681"
style.line_number2 = color "#CCCCCC"
style.line_highlight = color "#2A2D2E"
style.scrollbar = color "rgba(121, 121, 121, 0.40)"
style.scrollbar2 = color "rgba(121, 121, 121, 0.70)"
style.scrollbar_track = color "#1F1F1F"

style.nagbar = color "#F85149"
style.nagbar_text = color "#FFFFFF"
style.nagbar_dim = color "rgba(0, 0, 0, 0.45)"
style.drag_overlay = color "rgba(255, 255, 255, 0.08)"
style.drag_overlay_tab = color "#0078D4"
style.good = color "#2EA043"
style.warn = color "#D29922"
style.error = color "#F85149"
style.modified = color "#0078D4"

-- Syntax palette.
style.syntax = style.syntax or {}
style.syntax["normal"] = color "#D4D4D4"
style.syntax["symbol"] = color "#9CDCFE"
style.syntax["comment"] = color "#6A9955"
style.syntax["keyword"] = color "#569CD6"
style.syntax["keyword2"] = color "#C586C0"
style.syntax["keyword3"] = color "#4FC1FF"
style.syntax["number"] = color "#B5CEA8"
style.syntax["literal"] = color "#569CD6"
style.syntax["string"] = color "#CE9178"
style.syntax["operator"] = color "#D4D4D4"
style.syntax["function"] = color "#DCDCAA"
style.syntax["type"] = color "#4EC9B0"
style.syntax["whitespace"] = color "#404040"

style.log = style.log or {}
style.log["INFO"] = { icon = "i", color = style.text }
style.log["WARN"] = { icon = "!", color = style.warn }
style.log["ERROR"] = { icon = "!", color = style.error }

-- Common plugin-specific style hooks.
style.linter_warning = color "#D29922"
style.linter_error = color "#F85149"
style.bracketmatch_color = color "#0078D4"
style.guide = color "#404040"
style.guide_width = 1

return style

-- mod-version:3
-- priority:102
-- Interactive workbench layer for the lite_vs_layout runtime patch.

local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local RootView = require "core.rootview"
local TitleView = require "core.titleview"
local CommandView = require "core.commandview"
local DocView = require "core.docview"
local process = require "core.process"
local treeview = require "plugins.treeview"
local nerd = require "libraries.font_symbols_nerdfont_mono_regular"

local map = nerd.utf8
local popup_icon_font = renderer.font.load(
  nerd.path, 18 * SCALE,
  { antialiasing = "grayscale", hinting = "full" }
)

local C = {
  popup = { common.color "#1F1F1F" },
  popup2 = { common.color "#222222" },
  input = { common.color "#313131" },
  hover = { common.color "#2A2D2E" },
  selected = { common.color "#04395E" },
  selected_border = { common.color "#0078D4" },
  border = { common.color "#454545" },
  input_border = { common.color "#3C3C3C" },
  glow_outer = { common.color "rgba(0, 0, 0, 0.08)" },
  glow_middle = { common.color "rgba(0, 0, 0, 0.14)" },
  glow_inner = { common.color "rgba(0, 0, 0, 0.24)" },
  text = { common.color "#CCCCCC" },
  bright = { common.color "#FFFFFF" },
  dim = { common.color "#9D9D9D" },
  placeholder = { common.color "#989898" },
  disabled = { common.color "#656565" },
  accent = { common.color "#0078D4" },
}

local TITLE_H = 54 * SCALE
local QUICK_W = 900 * SCALE
local QUICK_Y = 9 * SCALE
local QUICK_INPUT_H = 60 * SCALE
local QUICK_ROW_H = 33 * SCALE
local QUICK_MAX_ROWS = 13
local MENU_W = 440 * SCALE
local MENU_ROW_H = 34 * SCALE
local MENU_SEP_H = 12 * SCALE
local MOTION_SELECTION_RATE = 0.34

local function inside(px, py, x, y, w, h)
  return px >= x and py >= y and px < x + w and py < y + h
end

local function draw_round_rect(x, y, w, h, radius, color)
  if w <= 0 or h <= 0 then return end
  local u = math.max(1, math.floor(SCALE + 0.5))
  radius = math.floor(math.max(u, math.min(radius, math.floor(math.min(w, h) / 2))) + 0.5)
  if radius < 2 * u or w < 6 * u or h < 6 * u then
    renderer.draw_rect(x + u, y, math.max(0, w - 2 * u), h, color)
    renderer.draw_rect(x, y + u, w, math.max(0, h - 2 * u), color)
    return
  end
  -- Scanline corners approximate a real radius without overlapping pixels.
  -- That is important for translucent glow layers: overlap produced the dark
  -- corner artefacts visible in the old Quick Pick.
  for row = 0, radius - 1 do
    local cy = radius - row - 0.5
    local inset = math.ceil(radius - math.sqrt(math.max(0, radius * radius - cy * cy)))
    local rw = math.max(0, w - inset * 2)
    renderer.draw_rect(x + inset, y + row, rw, 1, color)
    renderer.draw_rect(x + inset, y + h - row - 1, rw, 1, color)
  end
  renderer.draw_rect(x, y + radius, w, math.max(0, h - radius * 2), color)
end

local function draw_black_glow(x, y, w, h, radius)
  -- Lite VS's popup shadow is a zero-offset black halo, not a drop shadow.
  draw_round_rect(x - 9 * SCALE, y - 9 * SCALE, w + 18 * SCALE, h + 18 * SCALE,
    radius + 9 * SCALE, C.glow_outer)
  draw_round_rect(x - 5 * SCALE, y - 5 * SCALE, w + 10 * SCALE, h + 10 * SCALE,
    radius + 5 * SCALE, C.glow_middle)
  draw_round_rect(x - 2 * SCALE, y - 2 * SCALE, w + 4 * SCALE, h + 4 * SCALE,
    radius + 2 * SCALE, C.glow_inner)
end

local function ease_out_cubic(t)
  t = common.clamp(t, 0, 1)
  return 1 - (1 - t) ^ 3
end

local function animated_offset(opened_at, distance, duration)
  if not opened_at then return 0 end
  local progress = (system.get_time() - opened_at) / duration
  if progress < 1 then core.redraw = true end
  return -distance * (1 - ease_out_cubic(progress))
end

local function animated_value(owner, key, destination, rate)
  local value = owner[key]
  if value == nil then
    owner[key] = destination
    return destination
  end
  local difference = math.abs(value - destination)
  if not config.transitions or difference < 0.5 then
    owner[key] = destination
  else
    rate = rate or MOTION_SELECTION_RATE
    if config.fps ~= 60 or config.animation_rate ~= 1 then
      local dt = 60 / config.fps
      rate = 1 - common.clamp(1 - rate, 1e-8, 1 - 1e-8) ^
        (config.animation_rate * dt)
    end
    owner[key] = common.lerp(value, destination, rate)
    core.redraw = true
  end
  return owner[key]
end

local function draw_round_panel(x, y, w, h, radius, fill, border)
  local u = math.max(1, math.floor(SCALE + 0.5))
  if border then draw_round_rect(x, y, w, h, radius, border) end
  draw_round_rect(x + u, y + u, w - 2 * u, h - 2 * u,
    math.max(u, radius - u), fill)
end

local function restore_editor_focus()
  local node = core.root_view and core.root_view:get_primary_node()
  if node and node.active_view then core.set_active_view(node.active_view) end
end

local function perform(name)
  restore_editor_focus()
  return command.perform(name)
end

local function binding(name, fallback)
  return keymap.get_binding(name) or fallback or ""
end

-- -------------------------------------------------------------------------
-- Lite VS style menu model and popup renderer.
-- -------------------------------------------------------------------------

local function item(text, cmd, shortcut, extra)
  local t = extra or {}
  t.text, t.command, t.shortcut = text, cmd, shortcut
  return t
end

local SEP = { separator = true }

local menus = {
  File = {
    item("New Text File", "core:new-doc", "Ctrl+N"),
    item("New File...", "core:new-named-doc", "Ctrl+Alt+N"),
    item("New Window", nil, "Ctrl+Shift+N", {
      action = function() process.start({ EXEFILE }) end,
    }),
    SEP,
    item("Open File...", "core:open-file", "Ctrl+O"),
    item("Open Folder...", "core:open-project-folder", "Ctrl+Shift+O"),
    item("Open Recent", "core:find-file", "Ctrl+P"),
    SEP,
    item("Add Folder to Workspace...", "core:add-directory", ""),
    SEP,
    item("Save", "doc:save", "Ctrl+S"),
    item("Save As...", "doc:save-as", "Ctrl+Shift+S"),
    item("Save All", nil, "Ctrl+K S", {
      action = function()
        for _, doc in ipairs(core.docs) do
          if doc:is_dirty() and doc.abs_filename then doc:save() end
        end
      end,
    }),
    SEP,
    item("Preferences", "ui:settings", ""),
    SEP,
    item("Revert File", "doc:reload", ""),
    item("Close Editor", "root:close", "Ctrl+W"),
    item("Close All Editors", "root:close-all", ""),
    item("Close Window", "core:quit", "Alt+F4"),
    item("Exit", "core:quit", ""),
  },
  Edit = {
    item("Undo", "doc:undo", "Ctrl+Z"),
    item("Redo", "doc:redo", "Ctrl+Y"),
    SEP,
    item("Cut", "doc:cut", "Ctrl+X"),
    item("Copy", "doc:copy", "Ctrl+C"),
    item("Paste", "doc:paste", "Ctrl+V"),
    SEP,
    item("Find", "find-replace:find", "Ctrl+F"),
    item("Replace", "find-replace:replace", "Ctrl+H"),
    item("Find in Files", "project-search:find", "Ctrl+Shift+F"),
    SEP,
    item("Select All", "doc:select-all", "Ctrl+A"),
  },
  Selection = {
    item("Select All", "doc:select-all", "Ctrl+A"),
    item("Select Line", "doc:select-lines", ""),
    item("Select Word", "doc:select-word", ""),
    SEP,
    item("Add Cursor Above", "doc:create-cursor-previous-line", "Ctrl+Alt+Up"),
    item("Add Cursor Below", "doc:create-cursor-next-line", "Ctrl+Alt+Down"),
    item("Add Cursors to Line Ends", "doc:split-cursor", ""),
    SEP,
    item("Duplicate Selection", "doc:duplicate-lines", "Shift+Alt+Down"),
    item("Move Line Up", "doc:move-lines-up", "Alt+Up"),
    item("Move Line Down", "doc:move-lines-down", "Alt+Down"),
  },
  View = {
    item("Command Palette...", "core:find-command", "Ctrl+Shift+P"),
    item("Open Editors...", "lite-vs:open-editors", "Ctrl+Tab"),
    SEP,
    item("Explorer", "lite-vs:show-explorer", "Ctrl+Shift+E"),
    item("Search", "project-search:find", "Ctrl+Shift+F"),
    item("Source Control", "scm:global-diff", "Ctrl+Shift+G"),
    item("Run and Debug", "lite-vs:run-commands", "Ctrl+Shift+D"),
    item("Extensions", "plugin-manager:show", "Ctrl+Shift+X"),
    SEP,
    item("Toggle Primary Side Bar", "treeview:toggle", "Ctrl+B"),
    item("Toggle Panel", "terminal:toggle-drawer", "Ctrl+J"),
    item("Split Editor Right", "root:split-right", "Ctrl+\\"),
    item("Split Editor Down", "root:split-down", ""),
    SEP,
    item("Zoom In", "scale:increase", "Ctrl+="),
    item("Zoom Out", "scale:decrease", "Ctrl+-"),
    item("Full Screen", "core:toggle-fullscreen", "F11"),
  },
  Go = {
    item("Back", "navigate:previous", "Alt+Left"),
    item("Forward", "navigate:next", "Alt+Right"),
    SEP,
    item("Go to File...", "core:find-file", "Ctrl+P"),
    item("Go to Line...", "doc:go-to-line", "Ctrl+G"),
    SEP,
    item("Next Editor", "root:switch-to-next-tab", "Ctrl+PageDown"),
    item("Previous Editor", "root:switch-to-previous-tab", "Ctrl+PageUp"),
    item("Next Change", "scm:goto-next-change", ""),
    item("Previous Change", "scm:goto-previous-change", ""),
  },
  Run = {
    item("Run and Debug Commands...", "lite-vs:run-commands", "Ctrl+Shift+D"),
    item("Open Terminal", "terminal:open-tab", "Ctrl+Shift+`"),
    item("Toggle Terminal Panel", "terminal:toggle-drawer", "Ctrl+J"),
    SEP,
    item("Start/Stop Macro Recording", "macro:toggle-record", ""),
    item("Play Recorded Macro", "macro:play", ""),
  },
  Terminal = {
    item("New Terminal", "terminal:open-tab", "Ctrl+Shift+`"),
    item("Toggle Terminal", "terminal:toggle-drawer", "Ctrl+J"),
    item("Focus Terminal", "terminal:focus", ""),
    SEP,
    item("Clear", "terminal:clear", "Ctrl+L"),
    item("Close Terminal", "terminal:close-tab", ""),
  },
  Help = {
    item("Command Palette...", "core:find-command", "Ctrl+Shift+P"),
    item("Settings", "ui:settings", "Ctrl+Alt+P"),
    item("Extensions", "plugin-manager:show", "Ctrl+Shift+X"),
    SEP,
    item("Open Lite XL Log", "core:open-log", ""),
    item("Open User Configuration", "core:open-user-module", ""),
    item("Restart Lite XL", "core:restart", "Ctrl+Alt+R"),
  },
}

local menu_state = {
  open = false,
  name = nil,
  items = nil,
  x = 0,
  y = 0,
  w = MENU_W,
  h = 0,
  hover = nil,
  hover_y = nil,
}

local function menu_item_enabled(entry)
  if entry.separator then return false end
  if entry.enabled ~= nil then
    if type(entry.enabled) ~= "function" then return entry.enabled end
    local ok, enabled = pcall(entry.enabled)
    return ok and enabled or false
  end
  if entry.action ~= nil then return true end
  if not entry.command then return false end
  local ok, enabled = pcall(command.is_valid, entry.command)
  return ok and enabled or false
end

local function measure_menu(entries)
  local h = 8 * SCALE
  for _, entry in ipairs(entries) do
    h = h + (entry.separator and MENU_SEP_H or MENU_ROW_H)
  end
  return h + 8 * SCALE
end

local function open_menu(name, x, y, entries)
  entries = entries or menus[name]
  if not entries then return end
  menu_state.open = true
  menu_state.name = name
  menu_state.items = entries
  menu_state.x = x
  menu_state.y = y
  menu_state.w = MENU_W
  menu_state.h = measure_menu(entries)
  menu_state.hover = nil
  menu_state.hover_y = nil
  menu_state.opened_at = system.get_time()
  local root = core.root_view
  if menu_state.x + menu_state.w > root.size.x - 6 * SCALE then
    menu_state.x = root.size.x - menu_state.w - 6 * SCALE
  end
  if menu_state.y + menu_state.h > root.size.y - 6 * SCALE then
    menu_state.y = root.size.y - menu_state.h - 6 * SCALE
  end
  core.redraw = true
end

local function close_menu()
  menu_state.open = false
  menu_state.name = nil
  menu_state.items = nil
  menu_state.hover = nil
  core.redraw = true
end

local function menu_rows()
  local offset_y = animated_offset(menu_state.opened_at, 5 * SCALE, 0.11)
  local y = menu_state.y + offset_y + 8 * SCALE
  local rows = {}
  for i, entry in ipairs(menu_state.items or {}) do
    local h = entry.separator and MENU_SEP_H or MENU_ROW_H
    rows[#rows + 1] = { index = i, entry = entry, x = menu_state.x, y = y, w = menu_state.w, h = h }
    y = y + h
  end
  return rows
end

local function draw_menu()
  if not menu_state.open then return end
  local offset_y = animated_offset(menu_state.opened_at, 5 * SCALE, 0.11)
  local x, y, w, h = menu_state.x, menu_state.y + offset_y, menu_state.w, menu_state.h
  draw_black_glow(x, y, w, h, 6 * SCALE)
  draw_round_panel(x, y, w, h, 6 * SCALE, C.popup, C.border)

  local rows = menu_rows()
  local hovered_row
  for _, row in ipairs(rows) do
    if menu_state.hover == row.index and menu_item_enabled(row.entry) then
      hovered_row = row
      break
    end
  end
  if hovered_row then
    local hover_y = animated_value(menu_state, "hover_y", hovered_row.y,
      MOTION_SELECTION_RATE)
    draw_round_rect(x + 4 * SCALE, hover_y, w - 8 * SCALE,
      hovered_row.h, 4 * SCALE, C.hover)
  else
    menu_state.hover_y = nil
  end

  for _, row in ipairs(rows) do
    local entry = row.entry
    if entry.separator then
      renderer.draw_rect(x + 12 * SCALE, row.y + math.floor(row.h / 2),
        w - 24 * SCALE, style.divider_size, C.border)
    else
      local enabled = menu_item_enabled(entry)
      local color = enabled and C.text or C.disabled
      common.draw_text(style.font, color, entry.text, nil,
        x + 18 * SCALE, row.y, 0, row.h)
      if entry.shortcut and entry.shortcut ~= "" then
        common.draw_text(style.font, enabled and C.dim or C.disabled,
          entry.shortcut, "right", x + 18 * SCALE, row.y,
          w - 36 * SCALE, row.h)
      end
      if entry.submenu then
        common.draw_text(popup_icon_font, color, map["cod-chevron_right"] or ">",
          "center", x + w - 34 * SCALE, row.y, 24 * SCALE, row.h)
      end
    end
  end
end

local function activate_menu_entry(index)
  local entry = menu_state.items and menu_state.items[index]
  if not entry or not menu_item_enabled(entry) then return end
  close_menu()
  if entry.action then
    entry.action()
  elseif entry.command then
    perform(entry.command)
  end
end

-- -------------------------------------------------------------------------
-- Lite VS Quick Pick: Command Palette, Quick Open and open-editor list.
-- -------------------------------------------------------------------------

local command_enter = CommandView.enter
function CommandView:enter(label, options, ...)
  if type(options) == "table" then
    local copied = {}
    for k, v in pairs(options) do copied[k] = v end
    copied.typeahead = false
    options = copied
  end
  command_enter(self, label, options, ...)
  self.lite_vs_label = label
  self.lite_vs_placeholder = ({
    ["Do Command"] = "",
    ["Open File From Project"] = "Search files by name (append : to go to line or @ to go to symbol)",
    ["Open Editors"] = "Search open editors",
    ["Run and Debug"] = "Search run and debug commands",
    ["AI and Chat"] = "Search AI and chat extensions",
  })[label] or label
  self.label = label == "Do Command" and "> " or ""
  self.lite_vs_hover = nil
  self.lite_vs_selection_y = nil
  self.lite_vs_opened_at = system.get_time()
  core.redraw = true
end

local command_update = CommandView.update
function CommandView:update()
  command_update(self)
  -- Keep the locked command node at zero height; Quick Pick is a floating overlay.
  self.size.y = 0
end

local function quick_rect(view)
  local root = core.root_view
  local rows = math.min(QUICK_MAX_ROWS, #view.suggestions)
  local width = math.min(QUICK_W, root.size.x - 24 * SCALE)
  local x = math.floor((root.size.x - width) / 2)
  local y = QUICK_Y + animated_offset(view.lite_vs_opened_at, 10 * SCALE, 0.12)
  local h = QUICK_INPUT_H + (rows > 0 and (style.divider_size + rows * QUICK_ROW_H) or 0)
  return x, y, width, h, rows
end

local function fit_text(font, value, max_width, keep_end)
  local text = tostring(value or "")
  if font:get_width(text) <= max_width then return text end
  local ellipsis = "..."
  local available = math.max(0, max_width - font:get_width(ellipsis))
  if available <= 0 then return ellipsis end
  if keep_end then
    local first = #text
    while first > 1 and font:get_width(text:sub(first)) < available do
      first = first - 1
    end
    return ellipsis .. text:sub(math.min(#text, first + 1))
  end
  local last = 1
  while last < #text and font:get_width(text:sub(1, last)) < available do
    last = last + 1
  end
  return text:sub(1, math.max(1, last - 1)) .. ellipsis
end

local function draw_quick_pick(view)
  if core.active_view ~= view then return end
  local x, y, w, h, rows = quick_rect(view)
  draw_black_glow(x, y, w, h, 7 * SCALE)
  draw_round_panel(x, y, w, h, 7 * SCALE, C.popup2, C.input_border)

  local old_x, old_y = view.position.x, view.position.y
  local old_w, old_h = view.size.x, view.size.y
  view.position.x, view.position.y = x + 8 * SCALE, y + 10 * SCALE
  view.size.x, view.size.y = w - 16 * SCALE, QUICK_INPUT_H - 22 * SCALE
  draw_round_panel(view.position.x, view.position.y,
    view.size.x, view.size.y, 2 * SCALE, C.input, C.selected_border)
  CommandView.super.draw(view)
  if view:get_text() == "" and view.label == "" and view.lite_vs_placeholder ~= "" then
    common.draw_text(style.font, C.placeholder, view.lite_vs_placeholder, nil,
      view.position.x + 8 * SCALE, view.position.y, 0, view.size.y)
  end
  view.position.x, view.position.y = old_x, old_y
  view.size.x, view.size.y = old_w, old_h

  if rows > 0 then
    renderer.draw_rect(x, y + QUICK_INPUT_H, w, style.divider_size, C.border)
  end
  local first = math.max(1, view.suggestions_offset)
  local last = math.min(#view.suggestions, first + rows - 1)
  if view.suggestion_idx >= first and view.suggestion_idx <= last then
    local selected_index = view.suggestion_idx - first
    local target_y = y + QUICK_INPUT_H + style.divider_size +
      selected_index * QUICK_ROW_H
    local selection_y = animated_value(view, "lite_vs_selection_y", target_y,
      MOTION_SELECTION_RATE)
    draw_round_rect(x + 5 * SCALE, selection_y, w - 10 * SCALE,
      QUICK_ROW_H, 3 * SCALE, C.selected)
    renderer.draw_rect(x + 5 * SCALE, selection_y + 3 * SCALE,
      2 * SCALE, QUICK_ROW_H - 6 * SCALE, C.selected_border)
  else
    view.lite_vs_selection_y = nil
  end
  for i = first, last do
    local row_index = i - first
    local ry = y + QUICK_INPUT_H + style.divider_size + row_index * QUICK_ROW_H
    local selected = i == view.suggestion_idx
    local hovered = i == view.lite_vs_hover
    if hovered and not selected then
      draw_round_rect(x + 5 * SCALE, ry, w - 10 * SCALE,
        QUICK_ROW_H, 3 * SCALE, C.hover)
    end
    local entry = view.suggestions[i]
    local color = selected and C.bright or C.text
    local left_x = x + 16 * SCALE
    local right_x = x + math.floor(w * 0.43)
    local right_edge = x + w - 16 * SCALE
    local left_w = right_x - left_x - 12 * SCALE
    local title = fit_text(style.font, entry.text or tostring(entry), left_w, false)
    common.draw_text(style.font, color, title, nil, left_x, ry, 0, QUICK_ROW_H)
    if entry.info and entry.info ~= "" then
      local info = fit_text(style.font, entry.info, right_edge - right_x, true)
      common.draw_text(style.font, selected and C.text or C.dim, info, "right",
        right_x, ry, right_edge - right_x, QUICK_ROW_H)
    end
  end
end

function CommandView:draw() end

local function open_command_picker(label, terms)
  local names = command.get_all_valid()
  local filtered = {}
  for _, name in ipairs(names) do
    local low = name:lower()
    local include = not terms
    for _, term in ipairs(terms or {}) do
      if low:find(term, 1, true) then include = true break end
    end
    if include then
      filtered[#filtered + 1] = setmetatable({
        text = command.prettify_name(name),
        info = binding(name),
        command = name,
      }, { __tostring = function(v) return v.text .. " " .. (v.info or "") end })
    end
  end
  table.sort(filtered, function(a, b) return a.text < b.text end)
  core.command_view:enter(label, {
    typeahead = false,
    submit = function(_, selected)
      if selected then command.perform(selected.command) end
    end,
    suggest = function(text)
      return text == "" and filtered or common.fuzzy_match(filtered, text)
    end,
  })
end

command.add(nil, {
  ["lite-vs:open-editors"] = function()
    local entries = {}
    for _, view in ipairs(core.root_view.root_node:get_children()) do
      if view:is(DocView) then
        entries[#entries + 1] = setmetatable({
          text = view:get_name(),
          info = view.doc and common.home_encode(view.doc.abs_filename or view.doc.filename or "") or "",
          view = view,
        }, { __tostring = function(v) return v.text .. " " .. v.info end })
      end
    end
    core.command_view:enter("Open Editors", {
      typeahead = false,
      submit = function(_, selected)
        if selected then
          local node = core.root_view.root_node:get_node_for_view(selected.view)
          if node then node:set_active_view(selected.view) end
        end
      end,
      suggest = function(text)
        return text == "" and entries or common.fuzzy_match(entries, text)
      end,
      validate = function(_, selected) return selected ~= nil end,
    })
  end,
  ["lite-vs:run-commands"] = function()
    open_command_picker("Run and Debug", { "run", "debug", "build", "macro", "terminal" })
  end,
  ["lite-vs:show-explorer"] = function()
    treeview.visible = true
    command.perform "treeview:toggle-focus"
  end,
})

-- Replace command search with non-typeahead Lite VS behavior.
command.add(nil, {
  ["core:find-command"] = function()
    open_command_picker("Do Command")
  end,
  ["core:find-file"] = function()
    local entries = {}
    local seen = {}
    local function add_file(filename)
      if not filename or filename == "" then return end
      local abs = system.absolute_path(common.home_expand(filename)) or filename
      if seen[abs] then return end
      seen[abs] = true
      entries[#entries + 1] = setmetatable({
        text = common.basename(abs),
        info = common.home_encode(common.dirname(abs) or ""),
        filename = abs,
      }, { __tostring = function(v) return v.text .. " " .. v.info end })
    end
    for _, doc in ipairs(core.docs) do add_file(doc.abs_filename or doc.filename) end
    for _, filename in ipairs(core.visited_files) do add_file(filename) end
    if core.project_files_number() then
      for dir, project_item in core.get_project_files() do
        if project_item.type == "file" then
          add_file(dir .. PATHSEP .. project_item.filename)
        end
      end
    end
    core.command_view:enter("Open File From Project", {
      typeahead = false,
      submit = function(text, selected)
        local filename = selected and selected.filename or common.home_expand(text)
        if filename and filename ~= "" then
          core.root_view:open_doc(core.open_doc(filename))
        end
      end,
      suggest = function(text)
        return text == "" and entries or common.fuzzy_match(entries, text)
      end,
    })
  end,
})

-- -------------------------------------------------------------------------
-- Root event routing for floating menus and Quick Pick.
-- -------------------------------------------------------------------------

local root_draw = RootView.draw
function RootView:draw(...)
  root_draw(self, ...)
  if core.active_view == core.command_view then
    draw_quick_pick(core.command_view)
  end
  draw_menu()
end

local root_mouse_moved = RootView.on_mouse_moved
function RootView:on_mouse_moved(x, y, dx, dy)
  if menu_state.open then
    menu_state.hover = nil
    for _, hit in ipairs(core.title_view.lite_vs_hit_items or {}) do
      if hit.id and hit.id:match("^menu:") and inside(x, y, hit.x, hit.y, hit.w, hit.h) then
        local name = hit.id:sub(6)
        if name ~= menu_state.name then open_menu(name, hit.x, TITLE_H - 10 * SCALE) end
        core.request_cursor "arrow"
        return
      end
    end
    for _, row in ipairs(menu_rows()) do
      if not row.entry.separator and inside(x, y, row.x, row.y, row.w, row.h) then
        menu_state.hover = row.index
        break
      end
    end
    core.request_cursor "arrow"
    return
  end
  if core.active_view == core.command_view then
    local qx, qy, qw, _, rows = quick_rect(core.command_view)
    core.command_view.lite_vs_hover = nil
    for row = 1, rows do
      local ry = qy + QUICK_INPUT_H + style.divider_size + (row - 1) * QUICK_ROW_H
      if inside(x, y, qx, ry, qw, QUICK_ROW_H) then
        core.command_view.lite_vs_hover = core.command_view.suggestions_offset + row - 1
        break
      end
    end
    core.request_cursor "arrow"
    return
  end
  return root_mouse_moved(self, x, y, dx, dy)
end

local root_mouse_pressed = RootView.on_mouse_pressed
function RootView:on_mouse_pressed(button, x, y, clicks)
  if menu_state.open then
    for _, hit in ipairs(core.title_view.lite_vs_hit_items or {}) do
      if hit.id and hit.id:match("^menu:") and inside(x, y, hit.x, hit.y, hit.w, hit.h) then
        local name = hit.id:sub(6)
        if name == menu_state.name then close_menu()
        else open_menu(name, hit.x, TITLE_H - 10 * SCALE) end
        return true
      end
    end
    for _, row in ipairs(menu_rows()) do
      if inside(x, y, row.x, row.y, row.w, row.h) then
        if not row.entry.separator then activate_menu_entry(row.index) end
        return true
      end
    end
    close_menu()
    return true
  end
  if core.active_view == core.command_view then
    local qx, qy, qw, qh, rows = quick_rect(core.command_view)
    if inside(x, y, qx, qy, qw, qh) then
      for row = 1, rows do
        local ry = qy + QUICK_INPUT_H + style.divider_size + (row - 1) * QUICK_ROW_H
        if inside(x, y, qx, ry, qw, QUICK_ROW_H) then
          core.command_view.suggestion_idx = core.command_view.suggestions_offset + row - 1
          core.command_view:submit()
          return true
        end
      end
      return true
    end
    core.command_view:exit()
    return true
  end
  return root_mouse_pressed(self, button, x, y, clicks)
end

command.add(function() return menu_state.open end, {
  ["lite-vs:close-menu"] = function() close_menu() end,
  ["lite-vs:menu-next"] = function()
    local n = #menu_state.items
    local i = menu_state.hover or 0
    repeat i = i % n + 1 until not menu_state.items[i].separator
    menu_state.hover = i
  end,
  ["lite-vs:menu-previous"] = function()
    local n = #menu_state.items
    local i = menu_state.hover or 1
    repeat i = (i - 2) % n + 1 until not menu_state.items[i].separator
    menu_state.hover = i
  end,
  ["lite-vs:menu-submit"] = function()
    if menu_state.hover then activate_menu_entry(menu_state.hover) end
  end,
})

keymap.add({
  ["escape"] = { "lite-vs:close-menu" },
  ["down"] = { "lite-vs:menu-next" },
  ["up"] = { "lite-vs:menu-previous" },
  ["return"] = { "lite-vs:menu-submit" },
})

-- -------------------------------------------------------------------------
-- Title actions. Window movement uses Lite XL's native hit testing. An
-- optional platform extension can provide segmented caption regions.
-- -------------------------------------------------------------------------

local title_draw = TitleView.draw
function TitleView:draw(...)
  title_draw(self, ...)
  for _, hit in ipairs(self.lite_vs_hit_items or {}) do
    if hit.id and hit.id:match("^menu:") then
      local name = hit.id:sub(6)
      hit.action = function()
        if menu_state.open and menu_state.name == name then close_menu()
        else open_menu(name, hit.x, TITLE_H - 10 * SCALE) end
      end
    elseif hit.id == "logo" then
      hit.action = function() open_menu("File", 42 * SCALE, TITLE_H - 10 * SCALE) end
    elseif hit.id == "back" then
      hit.action = function() perform "navigate:previous" end
    elseif hit.id == "forward" then
      hit.action = function() perform "navigate:next" end
    elseif hit.id == "search" then
      hit.action = function() perform "core:find-file" end
    elseif hit.id == "layout" then
      hit.action = function() open_menu("View", hit.x - MENU_W + hit.w, TITLE_H - 10 * SCALE) end
    elseif hit.id == "primary-sidebar" then
      hit.action = function() perform "treeview:toggle" end
    elseif hit.id == "panel" then
      hit.action = function() perform "terminal:toggle-drawer" end
    elseif hit.id == "secondary-sidebar" then
      -- Lite XL has no native secondary sidebar; a right editor group is the
      -- closest functional equivalent and preserves the spatial model.
      hit.action = function() perform "root:split-right" end
    end
  end
  if menu_state.open and menu_state.name and menus[menu_state.name] then
    for _, hit in ipairs(self.lite_vs_hit_items or {}) do
      if hit.id == "menu:" .. menu_state.name then
        renderer.draw_rect(hit.x + 4 * SCALE, hit.y + 8 * SCALE,
          hit.w - 8 * SCALE, hit.h - 16 * SCALE, C.hover)
        common.draw_text(style.font, C.bright, menu_state.name, "center",
          hit.x, hit.y, hit.w, hit.h)
      end
    end
  end
end

-- -------------------------------------------------------------------------
-- Activity Bar and Lite VS key bindings.
-- -------------------------------------------------------------------------

local activity = core.lite_vs_activity_view
if activity then
  function activity:on_mouse_pressed(button, x, y)
    if button ~= "left" then return end
    self:build_items()
    for _, activity_item in ipairs(self.items) do
      if inside(x, y, activity_item.x, activity_item.y, activity_item.w, activity_item.h) then
        self.selected_index = activity_item.index <= 5 and activity_item.index or self.selected_index
        if activity_item.id == "files" then
          perform "lite-vs:show-explorer"
        elseif activity_item.id == "search" then
          perform "project-search:find"
        elseif activity_item.id == "source" then
          perform "scm:global-diff"
        elseif activity_item.id == "run" then
          perform "lite-vs:run-commands"
        elseif activity_item.id == "extensions" then
          perform "plugin-manager:show"
        elseif activity_item.id == "account" then
          open_menu("Account", self.position.x + self.size.x,
            self.position.y + self.size.y - 190 * SCALE, {
              item("Extensions and Accounts", "plugin-manager:show", ""),
              item("Settings Sync Alternatives", "ui:settings", ""),
            })
        elseif activity_item.id == "settings" then
          open_menu("Manage", self.position.x + self.size.x,
            self.position.y + self.size.y - 260 * SCALE, {
              item("Settings", "ui:settings", "Ctrl+Alt+P"),
              item("Command Palette...", "core:find-command", "Ctrl+Shift+P"),
              item("Extensions", "plugin-manager:show", "Ctrl+Shift+X"),
              SEP,
              item("Open User Configuration", "core:open-user-module", ""),
              item("Restart Lite XL", "core:restart", "Ctrl+Alt+R"),
            })
        end
        return true
      end
    end
  end
end

keymap.add_direct({
  ["ctrl+alt+l"] = "core:open-log",
  ["ctrl+tab"] = "lite-vs:open-editors",
  ["ctrl+b"] = "treeview:toggle",
  ["ctrl+j"] = "terminal:toggle-drawer",
  ["ctrl+shift+e"] = "lite-vs:show-explorer",
  ["ctrl+shift+f"] = "project-search:find",
  ["ctrl+shift+g"] = "scm:global-diff",
  ["ctrl+shift+d"] = "lite-vs:run-commands",
  ["ctrl+shift+x"] = "plugin-manager:show",
  ["ctrl+\\"] = "root:split-right",
  ["alt+left"] = "navigate:previous",
  ["alt+right"] = "navigate:next",
})

if PLATFORM == "Mac OS X" then
  keymap.add_direct({
    ["cmd+option+l"] = "core:open-log",
    ["cmd+tab"] = "lite-vs:open-editors",
    ["cmd+b"] = "treeview:toggle",
    ["cmd+j"] = "terminal:toggle-drawer",
    ["cmd+shift+e"] = "lite-vs:show-explorer",
    ["cmd+shift+f"] = "project-search:find",
    ["cmd+shift+g"] = "scm:global-diff",
    ["cmd+shift+d"] = "lite-vs:run-commands",
    ["cmd+shift+x"] = "plugin-manager:show",
    ["cmd+\\"] = "root:split-right",
    ["cmd+left"] = "navigate:previous",
    ["cmd+right"] = "navigate:next",
  })
end

core.redraw = true

return {
  menus = menus,
  menu_state = menu_state,
  open_menu = open_menu,
  close_menu = close_menu,
}

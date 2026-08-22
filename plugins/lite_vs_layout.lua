-- priority:101
-- mod-version:3
-- Modern workbench layout patch for Lite XL 2.1.x.
-- All changes are applied at runtime; Lite XL's installation files stay intact.

local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local View = require "core.view"
local Node = require "core.node"
local DocView = require "core.docview"
local TitleView = require "core.titleview"
local treeview = require "plugins.treeview"
local nerd = require "libraries.font_symbols_nerdfont_mono_regular"
local native_drag_ok, native_drag = pcall(require, "lite_vs_native_drag")

local map = nerd.utf8
local icon_font = renderer.font.load(
  nerd.path, 22 * SCALE,
  { antialiasing = "grayscale", hinting = "full" }
)
local activity_font = renderer.font.load(
  nerd.path, 27 * SCALE,
  { antialiasing = "grayscale", hinting = "full" }
)
local explorer_font = core.lite_vs_ui_bold_font or style.font

local C = {
  title = { common.color "#181818" },
  editor = { common.color "#1F1F1F" },
  panel = { common.color "#181818" },
  hover = { common.color "#2A2D2E" },
  active = { common.color "#37373D" },
  search = { common.color "#202020" },
  search_hover = { common.color "#2A2D2E" },
  border = { common.color "#3C3C3C" },
  divider = { common.color "#2B2B2B" },
  text = { common.color "#CCCCCC" },
  bright = { common.color "#FFFFFF" },
  dim = { common.color "#9D9D9D" },
  accent = { common.color "#0078D4" },
  close = { common.color "#C42B1C" },
}

local TITLE_H = 54 * SCALE
local CONTROL_W = 46 * SCALE
local ACTIVITY_W = 72 * SCALE
local EXPLORER_HEADER_H = 48 * SCALE
local TAB_H = 48 * SCALE
local BREADCRUMB_H = 36 * SCALE
local ACTIVITY_SLOT_H = 64 * SCALE
local MOTION_INDICATOR_RATE = 0.30

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
  for row = 0, radius - 1 do
    local cy = radius - row - 0.5
    local inset = math.ceil(radius - math.sqrt(math.max(0, radius * radius - cy * cy)))
    local rw = math.max(0, w - inset * 2)
    renderer.draw_rect(x + inset, y + row, rw, 1, color)
    renderer.draw_rect(x + inset, y + h - row - 1, rw, 1, color)
  end
  renderer.draw_rect(x, y + radius, w, math.max(0, h - radius * 2), color)
end

local function primary_view()
  local node = core.root_view and core.root_view:get_primary_node()
  return node and node.active_view
end

local function restore_editor_focus()
  local view = primary_view()
  if view then core.set_active_view(view) end
end

-- -------------------------------------------------------------------------
-- Integrated workbench title bar.
-- -------------------------------------------------------------------------

local title_controls = {
  {
    id = "minimize", icon = "cod-chrome_minimize",
    action = function() system.set_window_mode "minimized" end
  },
  {
    id = "maximize", icon = "cod-chrome_maximize",
    action = function()
      system.set_window_mode(core.window_mode == "maximized" and "normal" or "maximized")
    end
  },
  {
    id = "close", icon = "cod-chrome_close",
    action = function() core.quit() end
  },
}

local menu_items = {
  "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Help"
}

function TitleView:configure_hit_test(borderless)
  if borderless and native_drag_ok then
    -- The stock Lite XL hit test can only describe one uninterrupted caption
    -- area.  This toolbar has controls on the left, center and right, so the
    -- native extension supplies exact caption rectangles instead.
    system.set_window_hit_test()
    self.lite_vs_native_drag_signature = nil
  elseif borderless then
    -- A narrow native strip is a safe non-jittering fallback if the optional
    -- platform extension cannot be loaded.
    system.set_window_hit_test(7 * SCALE, CONTROL_W * #title_controls, 8 * SCALE)
  else
    system.set_window_hit_test()
    if native_drag_ok then pcall(native_drag.clear) end
    self.lite_vs_native_drag_signature = nil
  end
end

function TitleView:on_scale_change()
  self:configure_hit_test(self.visible)
end

function TitleView:update()
  self.size.y = self.visible and TITLE_H or 0
  TitleView.super.update(self)
end

local function add_hit(self, id, x, y, w, h, action, icon, kind)
  local item = {
    id = id, x = x, y = y, w = w, h = h,
    action = action, icon = icon, kind = kind
  }
  self.lite_vs_hit_items[#self.lite_vs_hit_items + 1] = item
  return item
end

local function sync_native_drag_regions(self)
  if not native_drag_ok or not self.visible then return end

  local left = self.position.x
  local right = left + self.size.x
  local pad = 2 * SCALE
  local intervals = {}
  for _, item in ipairs(self.lite_vs_hit_items or {}) do
    intervals[#intervals + 1] = {
      math.max(left, item.x - pad),
      math.min(right, item.x + item.w + pad),
    }
  end
  table.sort(intervals, function(a, b) return a[1] < b[1] end)

  local merged = {}
  for _, interval in ipairs(intervals) do
    local previous = merged[#merged]
    if previous and interval[1] <= previous[2] then
      previous[2] = math.max(previous[2], interval[2])
    else
      merged[#merged + 1] = { interval[1], interval[2] }
    end
  end

  local regions = {}
  local cursor = left
  local minimum_width = 8 * SCALE
  for _, interval in ipairs(merged) do
    if interval[1] - cursor >= minimum_width then
      regions[#regions + 1] = { cursor, self.position.y,
        interval[1] - cursor, TITLE_H }
    end
    cursor = math.max(cursor, interval[2])
  end
  if right - cursor >= minimum_width then
    regions[#regions + 1] = { cursor, self.position.y, right - cursor, TITLE_H }
  end

  local signature_parts = {
    string.format("%.2f:%.2f", core.root_view.size.x, core.root_view.size.y)
  }
  for _, region in ipairs(regions) do
    signature_parts[#signature_parts + 1] = string.format(
      "%.2f,%.2f,%.2f,%.2f", region[1], region[2], region[3], region[4]
    )
  end
  local signature = table.concat(signature_parts, ";")
  if signature ~= self.lite_vs_native_drag_signature then
    local called, installed = pcall(native_drag.set_regions, regions,
      core.root_view.size.x, core.root_view.size.y, 8 * SCALE)
    if called and installed then
      self.lite_vs_native_drag_signature = signature
    end
  end
end

local function draw_title_icon(self, item, font, color)
  if self.hovered_item == item then
    local bg = item.id == "close" and C.close or C.hover
    if item.kind == "control" then
      renderer.draw_rect(item.x, item.y, item.w, item.h, bg)
    else
      draw_round_rect(item.x + 6 * SCALE, item.y + 7 * SCALE,
        item.w - 12 * SCALE, item.h - 14 * SCALE, 5 * SCALE, bg)
    end
    color = C.bright
  end
  common.draw_text(font, color, map[item.icon] or "", "center",
    item.x, item.y, item.w, item.h)
end

function TitleView:draw()
  self:draw_background(C.title)
  renderer.draw_rect(self.position.x, self.position.y + self.size.y - style.divider_size,
    self.size.x, style.divider_size, C.divider)

  self.lite_vs_hit_items = {}
  local ox, oy = self.position.x, self.position.y
  local controls_x = ox + self.size.x - CONTROL_W * #title_controls

  -- An original text mark keeps the project recognizable without borrowing
  -- an editor or vendor logo.
  local logo = add_hit(self, "logo", ox, oy, 52 * SCALE, TITLE_H,
    function() command.perform "core:find-command" end, nil, "icon")
  common.draw_text(style.font, C.accent, "<>", "center",
    logo.x, logo.y, logo.w, logo.h)

  local mx = ox + 55 * SCALE
  -- Never let the menu run underneath the native window controls. On very
  -- narrow windows the trailing labels collapse into one command entry,
  -- leaving a small caption strip that remains draggable.
  local menu_limit = controls_x - 28 * SCALE
  for _, label in ipairs(menu_items) do
    local mw = style.font:get_width(label) + 20 * SCALE
    if mx + mw > menu_limit then
      local overflow_w = 34 * SCALE
      if mx + overflow_w <= menu_limit then
        local overflow = add_hit(self, "overflow-menu", mx, oy,
          overflow_w, TITLE_H,
          function() command.perform "core:find-command" end, nil, "menu")
        if self.hovered_item == overflow then
          draw_round_rect(mx + 2 * SCALE, oy + 8 * SCALE,
            overflow_w - 4 * SCALE, TITLE_H - 16 * SCALE,
            4 * SCALE, C.hover)
        end
        common.draw_text(style.font, C.text, "…", "center",
          mx, oy, overflow_w, TITLE_H)
        mx = mx + overflow_w
      end
      break
    end
    local item = add_hit(self, "menu:" .. label, mx, oy, mw, TITLE_H,
      function() command.perform "core:find-command" end, nil, "menu")
    if self.hovered_item == item then
      draw_round_rect(mx + 2 * SCALE, oy + 8 * SCALE, mw - 4 * SCALE,
        TITLE_H - 16 * SCALE, 4 * SCALE, C.hover)
    end
    common.draw_text(style.font, C.text, label, "center", mx, oy, mw, TITLE_H)
    mx = mx + mw
  end

  local tools = {
    { "layout", "md-view_dashboard_outline", function() command.perform "core:find-command" end },
    { "primary-sidebar", "md-page_layout_sidebar_left", function() command.perform "treeview:toggle" end },
    { "panel", "md-dock_bottom", function() command.perform "terminal:toggle-drawer" end },
    { "secondary-sidebar", "md-page_layout_sidebar_right", function() command.perform "root:split-right" end },
  }
  local tool_sets = {
    [0] = {},
    [1] = { tools[3] },
    [2] = { tools[2], tools[3] },
    [3] = { tools[2], tools[3], tools[4] },
    [4] = tools,
  }

  -- Prefer all four layout controls, but shed the least important ones when
  -- the command center would otherwise collide with the menu. The system
  -- controls are never hidden.
  local tool_count = 4
  local desired_center_space = 260 * SCALE
  while tool_count > 0 do
    local candidate_x = controls_x - (tool_count * 48 + 22) * SCALE
    if candidate_x - 8 * SCALE - mx >= desired_center_space then break end
    tool_count = tool_count - 1
  end
  local visible_tools = tool_sets[tool_count]
  local tools_x = tool_count > 0
    and controls_x - (tool_count * 48 + 22) * SCALE
    or controls_x
  local center_right = (tool_count > 0 and tools_x or controls_x) - 8 * SCALE

  -- Keep an actual caption gap whenever space permits. Navigation disappears
  -- before Search, and Search switches to an icon-only compact form before it
  -- is finally hidden. Every rectangle is derived from the remaining width,
  -- so hit areas cannot overlap either.
  local raw_center_w = math.max(0, center_right - mx)
  local caption_gap = 16 * SCALE
  if raw_center_w >= 520 * SCALE then
    caption_gap = 76 * SCALE
  elseif raw_center_w >= 340 * SCALE then
    caption_gap = 40 * SCALE
  end
  caption_gap = math.min(caption_gap, raw_center_w)
  local center_left = mx + caption_gap
  local available_center_w = math.max(0, center_right - center_left)

  local nav_count = 0
  if available_center_w >= 240 * SCALE then
    nav_count = 2
  elseif available_center_w >= 180 * SCALE then
    nav_count = 1
  end
  local nav_gap = nav_count > 0 and 6 * SCALE or 0
  local nav_w = nav_count * 36 * SCALE + nav_gap
  local search_x = center_left + nav_w
  local search_w = math.min(820 * SCALE,
    math.max(0, center_right - search_x))
  local search_y = oy + 9 * SCALE
  local search_h = TITLE_H - 18 * SCALE
  local show_search = search_w >= 44 * SCALE

  if nav_count >= 1 then
    local back = add_hit(self, "back", center_left, oy,
      34 * SCALE, TITLE_H,
      function()
        restore_editor_focus()
        command.perform "root:switch-to-previous-tab"
      end, "cod-arrow_left", "icon")
    draw_title_icon(self, back, icon_font, C.dim)
  end
  if nav_count >= 2 then
    local forward = add_hit(self, "forward", center_left + 36 * SCALE, oy,
      34 * SCALE, TITLE_H,
      function()
        restore_editor_focus()
        command.perform "root:switch-to-next-tab"
      end, "cod-arrow_right", "icon")
    draw_title_icon(self, forward, icon_font, C.dim)
  end

  if show_search then
    local search = add_hit(self, "search", search_x, search_y,
      search_w, search_h,
      function() command.perform "core:find-command" end, nil, "search")
    draw_round_rect(search_x, search_y, search_w, search_h, 7 * SCALE,
      self.hovered_item == search and C.search_hover or C.search)
    renderer.draw_rect(search_x + 7 * SCALE, search_y,
      math.max(0, search_w - 14 * SCALE), style.divider_size, C.border)
    renderer.draw_rect(search_x + 7 * SCALE,
      search_y + search_h - style.divider_size,
      math.max(0, search_w - 14 * SCALE), style.divider_size, C.border)
    renderer.draw_rect(search_x, search_y + 7 * SCALE,
      style.divider_size, math.max(0, search_h - 14 * SCALE), C.border)
    renderer.draw_rect(search_x + search_w - style.divider_size,
      search_y + 7 * SCALE, style.divider_size,
      math.max(0, search_h - 14 * SCALE), C.border)

    local search_icon = map["cod-search"] or ""
    local search_icon_w = icon_font:get_width(search_icon)
    if search_w >= 120 * SCALE then
      local search_label_w = style.font:get_width("Search")
      local search_content_w = search_icon_w + 8 * SCALE + search_label_w
      local search_content_x = search_x + (search_w - search_content_w) / 2
      common.draw_text(icon_font, C.dim, search_icon, nil,
        search_content_x, search_y, 0, search_h)
      common.draw_text(style.font, C.dim, "Search", nil,
        search_content_x + search_icon_w + 8 * SCALE,
        search_y, 0, search_h)
    else
      common.draw_text(icon_font, C.dim, search_icon, "center",
        search_x, search_y, search_w, search_h)
    end
  end

  local tx = tools_x
  for _, spec in ipairs(visible_tools) do
    local item = add_hit(self, spec[1], tx, oy, 46 * SCALE, TITLE_H,
      spec[3], spec[2], "icon")
    draw_title_icon(self, item, icon_font, C.text)
    tx = tx + 48 * SCALE
  end

  for i, spec in ipairs(title_controls) do
    local x = controls_x + (i - 1) * CONTROL_W
    local icon = spec.icon
    if spec.id == "maximize" and core.window_mode == "maximized" then
      icon = "cod-chrome_restore"
    end
    local item = add_hit(self, spec.id, x, oy, CONTROL_W, TITLE_H,
      spec.action, icon, "control")
    draw_title_icon(self, item, icon_font, C.text)
  end

  sync_native_drag_regions(self)
end

function TitleView:on_mouse_moved(px, py, ...)
  if self.size.y == 0 then return end
  TitleView.super.on_mouse_moved(self, px, py, ...)
  self.hovered_item = nil
  for _, item in ipairs(self.lite_vs_hit_items or {}) do
    if inside(px, py, item.x, item.y, item.w, item.h) then
      self.hovered_item = item
      core.request_cursor "arrow"
      break
    end
  end
end

function TitleView:on_mouse_pressed(button, x, y, clicks)
  local caught = TitleView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return caught end
  local clicked_item = nil
  for _, item in ipairs(self.lite_vs_hit_items or {}) do
    if inside(x, y, item.x, item.y, item.w, item.h) then
      clicked_item = item
      break
    end
  end
  if button == "left" and clicked_item and clicked_item.action then
    restore_editor_focus()
    clicked_item.action()
    return true
  elseif button == "left" and clicks and clicks >= 2 then
    system.set_window_mode(core.window_mode == "maximized" and "normal" or "maximized")
    return true
  end
end

-- -------------------------------------------------------------------------
-- Lite VS Activity Bar, inserted to the left of Explorer.
-- -------------------------------------------------------------------------

local ActivityBar = View:extend()

function ActivityBar:__tostring() return "LiteVSActivityBar" end

function ActivityBar:new()
  ActivityBar.super.new(self)
  self.hovered_index = nil
  self.selected_index = 1
  self.indicator_y = nil
  self.items = {}
end

function ActivityBar:get_name() return nil end

function ActivityBar:update()
  self.size.x = ACTIVITY_W
  ActivityBar.super.update(self)
  local target_y = self.position.y + (self.selected_index - 1) * ACTIVITY_SLOT_H
  if self.indicator_y == nil then self.indicator_y = target_y end
  self:move_towards(self, "indicator_y", target_y,
    MOTION_INDICATOR_RATE, "lite-vs-activity-indicator")
end

local activity_top = {
  { "files", "cod-files", function() command.perform "treeview:toggle" end },
  { "search", "cod-search", function() command.perform "core:find-file" end },
  { "source", "cod-source_control", function() command.perform "core:find-command" end },
  { "run", "cod-debug_alt", function() command.perform "core:find-command" end },
  { "extensions", "cod-extensions", function() command.perform "ui:settings" end },
}

local activity_bottom = {
  { "account", "cod-account", function() command.perform "core:find-command" end },
  { "settings", "cod-settings_gear", function() command.perform "ui:settings" end },
}

function ActivityBar:build_items()
  self.items = {}
  local x, y = self.position.x, self.position.y
  local slot_h = ACTIVITY_SLOT_H
  for i, spec in ipairs(activity_top) do
    self.items[#self.items + 1] = {
      id = spec[1], icon = spec[2], action = spec[3], index = i,
      x = x, y = y + (i - 1) * slot_h, w = ACTIVITY_W, h = slot_h
    }
  end
  for i, spec in ipairs(activity_bottom) do
    self.items[#self.items + 1] = {
      id = spec[1], icon = spec[2], action = spec[3],
      index = #activity_top + i,
      x = x, y = y + self.size.y - (#activity_bottom - i + 1) * slot_h,
      w = ACTIVITY_W, h = slot_h
    }
  end
end

function ActivityBar:draw()
  self:draw_background(C.panel)
  renderer.draw_rect(self.position.x + self.size.x - style.divider_size,
    self.position.y, style.divider_size, self.size.y, C.divider)
  self:build_items()
  for _, item in ipairs(self.items) do
    local selected = item.index == self.selected_index
    local hovered = item.index == self.hovered_index
    if hovered then
      draw_round_rect(item.x + 8 * SCALE, item.y + 5 * SCALE,
        item.w - 16 * SCALE, item.h - 10 * SCALE, 6 * SCALE, C.hover)
    end
    common.draw_text(activity_font,
      (selected or hovered) and C.bright or C.dim,
      map[item.icon] or "", "center", item.x, item.y, item.w, item.h)
  end
  if self.indicator_y then
    draw_round_rect(self.position.x, self.indicator_y + 7 * SCALE,
      3 * SCALE, ACTIVITY_SLOT_H - 14 * SCALE, 2 * SCALE, C.accent)
  end
end

function ActivityBar:on_mouse_moved(px, py, ...)
  ActivityBar.super.on_mouse_moved(self, px, py, ...)
  self.hovered_index = nil
  self:build_items()
  for _, item in ipairs(self.items) do
    if inside(px, py, item.x, item.y, item.w, item.h) then
      self.hovered_index = item.index
      core.request_cursor "arrow"
      break
    end
  end
end

function ActivityBar:on_mouse_left()
  self.hovered_index = nil
end

function ActivityBar:on_mouse_pressed(button, x, y)
  if button ~= "left" then return end
  for _, item in ipairs(self.items) do
    if inside(x, y, item.x, item.y, item.w, item.h) then
      self.selected_index = item.index <= #activity_top and item.index or self.selected_index
      if item.action then item.action() end
      if item.id == "files" then
        restore_editor_focus()
      end
      return true
    end
  end
end

local activity_view = ActivityBar()
local tree_node = core.root_view.root_node:get_node_for_view(treeview) or treeview.node
assert(tree_node and tree_node.type == "leaf",
  "lite-vs could not locate the Explorer leaf node")
activity_view.node = tree_node:split("left", activity_view, { x = true })
treeview.node = core.root_view.root_node:get_node_for_view(treeview)
core.lite_vs_activity_view = activity_view

-- -------------------------------------------------------------------------
-- Explorer heading.
-- -------------------------------------------------------------------------

local tree_get_content_offset = treeview.get_content_offset
function treeview:get_content_offset()
  local x, y = tree_get_content_offset(self)
  return x, y + EXPLORER_HEADER_H
end

local tree_get_scrollable_size = treeview.get_scrollable_size
function treeview:get_scrollable_size()
  return tree_get_scrollable_size(self) + EXPLORER_HEADER_H
end

local tree_draw = treeview.draw
function treeview:draw()
  tree_draw(self)
  if not self.visible then return end
  local x, y, w = self.position.x, self.position.y, self.size.x
  renderer.draw_rect(x, y, w, EXPLORER_HEADER_H, C.panel)
  renderer.draw_rect(x, y + EXPLORER_HEADER_H - style.divider_size,
    w, style.divider_size, C.divider)
  common.draw_text(explorer_font, C.bright, "Explorer", nil,
    x + 20 * SCALE, y, 0, EXPLORER_HEADER_H)
  common.draw_text(icon_font, C.text, map["cod-ellipsis"] or "...", "center",
    x + w - 52 * SCALE, y, 42 * SCALE, EXPLORER_HEADER_H)
end

-- -------------------------------------------------------------------------
-- Taller editor tabs and a Lite VS-like breadcrumb row.
-- -------------------------------------------------------------------------

function Node:get_scroll_button_rect(index)
  local glyph_w = style.icon_font:get_width(">")
  local w, pad = glyph_w * 3, glyph_w
  local x = self.position.x + (index == 1 and self.size.x - w * 2 or self.size.x - w)
  return x, self.position.y, w, TAB_H, pad
end

function Node:get_tab_rect(idx)
  local maxw = self.size.x
  local x0 = self.position.x
  local x1 = x0 + common.clamp(self.tab_width * (idx - 1) - self.tab_shift, 0, maxw)
  local x2 = x0 + common.clamp(self.tab_width * idx - self.tab_shift, 0, maxw)
  return x1, self.position.y, x2 - x1, TAB_H
end

local node_update_layout = Node.update_layout
function Node:update_layout()
  node_update_layout(self)
  if self.type == "leaf" and not self.locked and self:should_show_tabs() then
    local av = self.active_view
    av.position.y = av.position.y + BREADCRUMB_H
    av.size.y = math.max(0, av.size.y - BREADCRUMB_H)
  end
end

local function breadcrumb_parts(view)
  if not view or not view.doc then return nil end
  local filename = view.doc.abs_filename or view.doc.filename
  if not filename then return nil end
  local parts = {}
  for part in filename:gmatch("[^/\\]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function draw_breadcrumbs(node)
  local parts = breadcrumb_parts(node.active_view)
  if not parts then return end
  local x = node.position.x
  local y = node.position.y + TAB_H
  local w = node.size.x
  renderer.draw_rect(x, y, w, BREADCRUMB_H, C.editor)
  renderer.draw_rect(x, y + BREADCRUMB_H - style.divider_size,
    w, style.divider_size, C.divider)
  local tx = x + 18 * SCALE
  local right_limit = x + w - 128 * SCALE
  local start = math.max(1, #parts - 6)
  for i = start, #parts do
    local label = parts[i]
    local tw = style.font:get_width(label)
    if tx + tw > right_limit then break end
    local color = i == #parts and C.text or C.dim
    common.draw_text(style.font, color, label, nil, tx, y, 0, BREADCRUMB_H)
    tx = tx + tw + 7 * SCALE
    if i < #parts then
      local sep = map["cod-chevron_right"] or ">"
      common.draw_text(icon_font, C.dim, sep, nil, tx, y, 0, BREADCRUMB_H)
      tx = tx + icon_font:get_width(sep) + 7 * SCALE
    end
  end
  common.draw_text(icon_font, C.text, map["cod-split_horizontal"] or "", "center",
    x + w - 92 * SCALE, y, 40 * SCALE, BREADCRUMB_H)
  common.draw_text(icon_font, C.text, map["cod-ellipsis"] or "...", "center",
    x + w - 48 * SCALE, y, 40 * SCALE, BREADCRUMB_H)
end

local node_draw = Node.draw
function Node:draw()
  node_draw(self)
  if self.type == "leaf" and not self.locked and self:should_show_tabs() then
    draw_breadcrumbs(self)
  end
end

-- Lite VS keeps a wider number gutter than Lite XL.  The separate padding
-- adjustment aligns both the line numbers and the first text column.
local doc_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local width, padding = doc_get_gutter_width(self)
  -- Some service views and third-party DocView wrappers intentionally return
  -- only the width.  Keep those views compatible while preserving the wider
  -- Lite VS gutter for normal editors.
  return (width or 0) + 45 * SCALE, (padding or 0) + 15 * SCALE
end

core.title_view:configure_hit_test(config.borderless)
core.redraw = true

return {
  activity_view = activity_view,
  title_height = TITLE_H,
  activity_width = ACTIVITY_W,
}

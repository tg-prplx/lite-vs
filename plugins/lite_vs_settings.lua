-- priority:104
-- mod-version:3
-- Responsive, workbench-native styling for Lite XL's Settings widget.

local core = require "core"
local common = require "core.common"
local style = require "core.style"
local Widget = require "libraries.widget"
local TextBox = require "libraries.widget.textbox"
local SelectBox = require "libraries.widget.selectbox"
local NumberBox = require "libraries.widget.numberbox"
local Toggle = require "libraries.widget.toggle"
local Label = require "libraries.widget.label"
local nerd = require "libraries.font_symbols_nerdfont_mono_regular"

local ok_settings, settings = pcall(require, "plugins.settings")
if not ok_settings or not settings then return end

local function install_settings_patch(ui)
if not ui or ui.lite_vs_settings_patched then return end
ui.lite_vs_settings_patched = true

local map = nerd.utf8
local icon_font = renderer.font.load(nerd.path, 18 * SCALE, {
  antialiasing = "grayscale", hinting = "full"
})
local heading_font = (core.lite_vs_ui_bold_font or style.font):copy(22 * SCALE)
local section_font = core.lite_vs_ui_bold_font or style.font

local C = {
  surface = { common.color "#1F1F1F" },
  navigation = { common.color "#181818" },
  card = { common.color "#252526" },
  card_hover = { common.color "#2A2D2E" },
  input = { common.color "#313131" },
  input_hover = { common.color "#3C3C3C" },
  border = { common.color "#3F3F46" },
  border_focus = { common.color "#007ACC" },
  text = { common.color "#CCCCCC" },
  bright = { common.color "#FFFFFF" },
  muted = { common.color "#9D9D9D" },
  accent = { common.color "#0E639C" },
  accent_hover = { common.color "#1177BB" },
  knob = { common.color "#FFFFFF" },
}

local ROOT_MARGIN = 28 * SCALE
local HEADER_H = 82 * SCALE
local NAV_W = 210 * SCALE
local NAV_GAP = 36 * SCALE
local TAB_H = 42 * SCALE
local TAB_GAP = 6 * SCALE
local CONTENT_HEADING_H = 54 * SCALE
local MAX_CONTENT_W = 820 * SCALE
local SECTION_H = 42 * SCALE
local CONTROL_MAX_W = 500 * SCALE
local LIST_MAX_W = 620 * SCALE
local CONTROL_H = 34 * SCALE

local function navigation_metrics(width)
  if width >= 760 * SCALE then return NAV_W, NAV_GAP end
  if width >= 560 * SCALE then return 164 * SCALE, 24 * SCALE end
  return 52 * SCALE, 14 * SCALE
end

local function draw_round_rect(x, y, w, h, radius, color)
  if w <= 0 or h <= 0 then return end
  local unit = math.max(1, math.floor(SCALE + 0.5))
  radius = math.floor(math.max(unit,
    math.min(radius, math.floor(math.min(w, h) / 2))) + 0.5)
  if radius < 2 * unit or w < 6 * unit or h < 6 * unit then
    renderer.draw_rect(x + unit, y, math.max(0, w - 2 * unit), h, color)
    renderer.draw_rect(x, y + unit, w, math.max(0, h - 2 * unit), color)
    return
  end
  for row = 0, radius - 1 do
    local cy = radius - row - 0.5
    local inset = math.ceil(radius - math.sqrt(math.max(0,
      radius * radius - cy * cy)))
    local rw = math.max(0, w - inset * 2)
    renderer.draw_rect(x + inset, y + row, rw, 1, color)
    renderer.draw_rect(x + inset, y + h - row - 1, rw, 1, color)
  end
  renderer.draw_rect(x, y + radius, w,
    math.max(0, h - radius * 2), color)
end

local function draw_round_outline(x, y, w, h, radius, border, fill)
  draw_round_rect(x, y, w, h, radius, border)
  local inset = math.max(1, math.floor(SCALE + 0.5))
  draw_round_rect(x + inset, y + inset,
    math.max(0, w - inset * 2), math.max(0, h - inset * 2),
    math.max(1, radius - inset), fill)
end

local action_icons = {
  ["User Module"] = map["cod-edit"],
  ["Clear Fonts Cache"] = map["cod-trash"],
  ["Add"] = map["cod-add"],
  ["Remove"] = map["cod-remove"],
  ["Visit Website"] = map["cod-link_external"],
}

local function draw_button_contents(self, color)
  local font = self:get_font()
  local height = self:get_height()
  local offset_x = self.position.x + self.padding.x
  local icon = self.lite_vs_action_icon
  if icon then
    local icon_w = 18 * SCALE
    common.draw_text(icon_font, color, icon, "center", offset_x,
      self.position.y, icon_w, height)
    offset_x = offset_x + icon_w + 6 * SCALE
  end
  if self.label and self.label ~= "" then
    common.draw_text(font, color, self.label, nil, offset_x,
      self.position.y, 0, height)
  end
end

local function draw_navigation_tab(self)
  if not self:is_visible() then return false end
  local pane = self.lite_vs_settings_pane
  local active = self.parent.active_pane == pane
  local hovered = self.hover_text ~= nil
  if active or hovered then
    draw_round_rect(self.position.x, self.position.y,
      self.size.x, self.size.y, 7 * SCALE,
      active and C.card or C.card_hover)
  end
  if active then
    draw_round_rect(self.position.x, self.position.y + 8 * SCALE,
      3 * SCALE, self.size.y - 16 * SCALE, 2 * SCALE, C.accent)
  end
  local icon = self.lite_vs_settings_icon or ""
  local compact = self.size.x < 100 * SCALE
  common.draw_text(icon_font, active and C.bright or C.muted, icon, "center",
    compact and self.position.x or self.position.x + 10 * SCALE,
    self.position.y, compact and self.size.x or 30 * SCALE, self.size.y)
  if not compact then
    common.draw_text(section_font, active and C.bright or C.text,
      self.label or "", nil, self.position.x + 48 * SCALE,
      self.position.y, 0, self.size.y)
  end
  return true
end

local function draw_section_tab(self)
  if not self:is_visible() then return false end
  local pane = self.lite_vs_settings_section
  local hovered = self.hover_text ~= nil
  draw_round_outline(self.position.x, self.position.y,
    self.size.x, self.size.y, 5 * SCALE, C.border,
    hovered and C.card_hover or C.card)
  local chevron = pane.expanded and map["cod-chevron_down"]
    or map["cod-chevron_right"]
  common.draw_text(icon_font, pane.expanded and C.bright or C.muted,
    chevron or "", "center", self.position.x + 8 * SCALE,
    self.position.y, 28 * SCALE, self.size.y)
  common.draw_text(section_font, C.bright, self.label or "", nil,
    self.position.x + 42 * SCALE, self.position.y, 0, self.size.y)
  return true
end

local function draw_control_button(self)
  if not self:is_visible() then return false end
  local hovered = self.hover_text ~= nil
  if self.lite_vs_stepper then
    if hovered then
      renderer.draw_rect(self.position.x + 1 * SCALE,
        self.position.y + 1 * SCALE,
        math.max(0, self.size.x - 2 * SCALE),
        math.max(0, self.size.y - 2 * SCALE), C.input_hover)
    end
    common.draw_text(section_font, hovered and C.bright or C.text,
      self.label or "", "center", self.position.x, self.position.y,
      self.size.x, self.size.y)
    return true
  end
  local primary = self.lite_vs_primary
  draw_round_outline(self.position.x, self.position.y,
    self.size.x, self.size.y, 3 * SCALE,
    primary and (hovered and C.accent_hover or C.accent) or C.border,
    primary and (hovered and C.accent_hover or C.accent)
      or (hovered and C.input_hover or C.input))
  draw_button_contents(self,
    primary and C.bright or (hovered and C.bright or C.text))
  return true
end

local function draw_textbox(self)
  if not self:is_visible() then return false end
  local focused = self.active or core.active_view == self.textview
  if not self.lite_vs_embedded then
    draw_round_outline(self.position.x, self.position.y,
      self.size.x, self.size.y, 3 * SCALE,
      focused and C.border_focus or C.border, C.input)
  end
  local text_padding = 10 * SCALE
  self.textview.position.x = self.position.x + text_padding
  self.textview.position.y = self.position.y - style.padding.y / 2.5
  self.textview.size.x = math.max(0, self.size.x - text_padding * 2)
  self.textview.size.y = self.size.y - style.padding.y * 2
  core.push_clip_rect(self.position.x + 2 * SCALE,
    self.position.y + 1 * SCALE,
    math.max(0, self.size.x - 4 * SCALE),
    math.max(0, self.size.y - 2 * SCALE))
  self.textview:draw()
  core.pop_clip_rect()
  self:draw_scrollbar()
  return true
end

local function draw_selectbox(self)
  if not self:is_visible() then return false end
  local hovered = self.hover_text ~= nil
  draw_round_outline(self.position.x, self.position.y,
    self.size.x, self.size.y, 3 * SCALE,
    hovered and C.border_focus or C.border, C.input)
  local text = self.selected == 0 and self.label
    or self.list:get_row_text(self.selected + 1)
  text = self:text_overflow(text, self.size.x - 54 * SCALE, self:get_font())
  common.draw_text(self:get_font(), hovered and C.bright or C.text,
    text, "left", self.position.x + style.padding.x,
    self.position.y, self.size.x - 48 * SCALE, self.size.y)
  common.draw_text(icon_font, hovered and C.bright or C.muted,
    map["cod-chevron_down"] or "", "center",
    self.position.x + self.size.x - 38 * SCALE,
    self.position.y, 30 * SCALE, self.size.y)
  return true
end

local function draw_numberbox(self)
  if not self:is_visible() then return false end
  local focused = self.textbox.active or core.active_view == self.textbox.textview
  draw_round_outline(self.position.x, self.position.y,
    self.size.x, self.size.y, 3 * SCALE,
    focused and C.border_focus or C.border, C.input)
  Widget.draw(self)
  local first_x = self.decrease_button.position.x
  local second_x = self.increase_button.position.x
  renderer.draw_rect(first_x, self.position.y + 1 * SCALE,
    math.max(1, SCALE), math.max(0, self.size.y - 2 * SCALE), C.border)
  renderer.draw_rect(second_x, self.position.y + 1 * SCALE,
    math.max(1, SCALE), math.max(0, self.size.y - 2 * SCALE), C.border)
  return true
end

local function draw_itemslist(self)
  if not self:is_visible() then return false end
  local list = self.list
  draw_round_outline(list.position.x, list.position.y,
    list.size.x, list.size.y, 3 * SCALE, C.border, C.input)
  return Widget.draw(self)
end

local function draw_toggle(self)
  if not self:is_visible() then return false end
  self.render_background = false
  Widget.draw(self)
  local x = self.position.x + self.toggle_x
  local y = self.position.y + 2 * SCALE
  local w = 40 * SCALE
  local h = math.max(16 * SCALE, self.size.y - 4 * SCALE)
  draw_round_rect(x, y, w, h, h / 2,
    self.enabled and C.accent or C.border)
  local knob = h - 6 * SCALE
  local knob_x = self.enabled and x + w - knob - 3 * SCALE
    or x + 3 * SCALE
  draw_round_rect(knob_x, y + 3 * SCALE, knob, knob,
    knob / 2, C.knob)
  return true
end

local function style_widget(widget)
  if widget.lite_vs_settings_styled then return end
  widget.lite_vs_settings_styled = true

  if widget.type_name == "widget.textbox" then
    widget.border.width = 0
    widget.render_background = false
    widget.textview.draw_background = function() end
    local original_set_size = widget.set_size
    function widget:set_size(width)
      original_set_size(self, width)
      self.size.y = CONTROL_H
    end
    widget:set_size(widget.size.x)
    widget.draw = draw_textbox
  elseif widget.type_name == "widget.selectbox" then
    widget.border.width = 0
    widget.render_background = false
    local original_update = widget.update
    function widget:update()
      local result = original_update(self)
      if result == false then return false end
      self.size.y = CONTROL_H
      return result
    end
    widget.size.y = CONTROL_H
    widget.draw = draw_selectbox
    widget.list_container.background_color = C.card
    widget.list_container.border.color = C.border_focus
  elseif widget.type_name == "widget.numberbox" then
    widget.border.width = 0
    widget.render_background = false
    widget.draw = draw_numberbox
    widget.textbox.lite_vs_embedded = true
    widget.decrease_button.lite_vs_stepper = true
    widget.increase_button.lite_vs_stepper = true
  elseif widget.type_name == "widget.itemslist" then
    widget.border.width = 0
    widget.render_background = false
    widget.draw = draw_itemslist
    widget.list.border.width = 0
    widget.list.render_background = false
  elseif widget.type_name == "widget.toggle" then
    widget.render_background = false
    widget.draw = draw_toggle
    widget.caption_label.foreground_color = C.text
  elseif widget.type_name == "widget.button" then
    widget.border.width = 0
    widget.render_background = false
    widget.lite_vs_action_icon = action_icons[widget.label]
    widget.icon.code = nil
    widget.padding.x = widget.lite_vs_stepper and 0 or 12 * SCALE
    widget.padding.y = 5 * SCALE
    widget.lite_vs_primary = widget.label == "User Module"
      or widget.label == "Add" or widget.label == "Visit Website"
    local original_update = widget.update
    function widget:update()
      local result = original_update(self)
      if result == false then return false end
      if self.lite_vs_stepper then self.size.x = CONTROL_H end
      if self.lite_vs_action_icon then self.size.x = self.size.x + 24 * SCALE end
      self.size.y = CONTROL_H
      return result
    end
    widget:set_label(widget.label)
    if widget.lite_vs_stepper then widget.size.x = CONTROL_H end
    if widget.lite_vs_action_icon then widget.size.x = widget.size.x + 24 * SCALE end
    widget.size.y = CONTROL_H
    widget.draw = draw_control_button
  elseif widget.type_name == "widget.label" then
    widget.foreground_color = widget.desc and C.muted or C.text
  end

  for _, child in ipairs(widget.childs or {}) do
    style_widget(child)
  end
end

local category_icons = {
  core = map["cod-settings_gear"],
  colors = map["cod-symbol_color"],
  plugins = map["cod-extensions"],
  keybindings = map["cod-key"],
  about = map["cod-info"],
}

for _, pane in ipairs(ui.notebook.panes) do
  pane.tab.lite_vs_settings_pane = pane
  pane.tab.lite_vs_settings_icon = category_icons[pane.name] or ""
  pane.tab.border.width = 0
  pane.tab.render_background = false
  pane.tab.draw = draw_navigation_tab
  pane.container.border.width = 0
  pane.container.render_background = false
end

local function patch_foldingbook(book)
  if book.lite_vs_settings_patched then return end
  book.lite_vs_settings_patched = true
  book.border.width = 0
  book.render_background = false
  local original_update = book.update
  function book:update()
    local result = original_update(self)
    if result == false then return false end
    local y = 8 * SCALE
    for _, pane in ipairs(self.panes) do
      pane.tab:set_position(0, y)
      pane.tab:set_size(self.size.x, SECTION_H)
      pane.container.border.width = 0
      pane.container.render_background = false
      if pane.container:is_visible() then
        pane.container:set_position(0, y + SECTION_H + 8 * SCALE)
        pane.container:set_size(self.size.x)
        y = pane.container:get_bottom() + 10 * SCALE
      else
        y = pane.tab:get_bottom() + 10 * SCALE
      end
    end
    return result
  end
  function book:draw()
    if not self:is_visible() then return false end
    self.render_background = false
    return Widget.draw(self)
  end
  for _, pane in ipairs(book.panes) do
    pane.tab.lite_vs_settings_section = pane
    pane.tab.border.width = 0
    pane.tab.render_background = false
    pane.tab.draw = draw_section_tab
    style_widget(pane.container)
  end
end

patch_foldingbook(ui.core_sections)
patch_foldingbook(ui.plugin_sections)
style_widget(ui.colors)
style_widget(ui.keybinds)
style_widget(ui.about)

local notebook = ui.notebook
local original_notebook_update = notebook.update
function notebook:update()
  local result = original_notebook_update(self)
  if result == false then return false end
  local nav_w, nav_gap = navigation_metrics(self.size.x)
  self.lite_vs_settings_nav_w = nav_w
  local content_area_x = nav_w + nav_gap
  local available_w = math.max(0, self.size.x - content_area_x)
  local content_w = math.min(MAX_CONTENT_W, available_w)
  local content_x = content_area_x
  for index, pane in ipairs(self.panes) do
    pane.tab:set_position(0, (index - 1) * (TAB_H + TAB_GAP))
    pane.tab:set_size(nav_w, TAB_H)
    pane.container:set_position(content_x, CONTENT_HEADING_H)
    pane.container:set_size(content_w,
      math.max(0, self.size.y - CONTENT_HEADING_H))
  end
  return result
end

function notebook:draw()
  if not self:is_visible() then return false end
  self.render_background = false
  local nav_w = self.lite_vs_settings_nav_w
    or navigation_metrics(self.size.x)
  draw_round_rect(self.position.x, self.position.y,
    nav_w, math.min(self.size.y, #self.panes * (TAB_H + TAB_GAP)
      + 16 * SCALE), 10 * SCALE, C.navigation)
  Widget.draw(self)
  if self.active_pane then
    local content = self.active_pane.container
    common.draw_text(heading_font, C.bright,
      self.active_pane.tab.label or "Settings", nil,
      content.position.x, self.position.y + 4 * SCALE,
      0, 40 * SCALE)
    renderer.draw_rect(content.position.x,
      self.position.y + CONTENT_HEADING_H - style.divider_size,
      content.size.x, style.divider_size, C.border)
  end
  return true
end

local SettingsClass = getmetatable(ui)
local original_settings_update = SettingsClass.update
function SettingsClass:update()
  local result = original_settings_update(self)
  if not self:is_visible() then return result end

  self.background_color = C.surface
  self.notebook:set_position(ROOT_MARGIN, HEADER_H)
  self.notebook:set_size(math.max(0, self.size.x - ROOT_MARGIN * 2),
    math.max(0, self.size.y - HEADER_H - ROOT_MARGIN))
  self.notebook:update()

  for _, book in ipairs({ self.core_sections, self.plugin_sections }) do
    if book.parent:is_visible() then
      book:set_position(0, 0)
      book:set_size(book.parent.size.x, book:get_real_height())
      book:update()
      for _, pane in ipairs(book.panes) do
        local previous
        for position = #pane.container.childs, 1, -1 do
          local child = pane.container.childs[position]
          local x = 18 * SCALE
          local y = 16 * SCALE
          if previous then
            if (previous:is(Label) and not previous.desc)
              or (child:is(Label) and child.desc) then
              y = previous:get_bottom() + 9 * SCALE
            else
              y = previous:get_bottom() + 24 * SCALE
            end
          end
          if child.type_name == "widget.line" then
            x = 0
          elseif child:is(TextBox) or child:is(SelectBox)
            or child:is(NumberBox) then
            child:set_size(math.min(CONTROL_MAX_W,
              pane.container:get_width() - 36 * SCALE))
          elseif child.type_name == "widget.itemslist"
            or child.type_name == "widget.filepicker" then
            child:set_size(math.min(LIST_MAX_W,
              pane.container:get_width() - 36 * SCALE), child.size.y)
          end
          child:set_position(x, y)
          style_widget(child)
          previous = child
        end
      end
    end
  end

  if self.keybinds:is_visible() then self.keybinds:update_positions() end
  if self.about:is_visible() then self.about:update_positions() end
  return result
end

local original_settings_draw = SettingsClass.draw
function SettingsClass:draw()
  local result = original_settings_draw(self)
  if result == false or not self:is_visible() then return result end
  common.draw_text(heading_font, C.bright, "Settings", nil,
    self.position.x + ROOT_MARGIN,
    self.position.y + 10 * SCALE, 0, 36 * SCALE)
  common.draw_text(style.font, C.muted,
    "Customize the editor, appearance, plugins, and shortcuts.", nil,
    self.position.x + ROOT_MARGIN,
    self.position.y + 44 * SCALE, 0, 28 * SCALE)
  return result
end

ui.border.width = 0
ui.render_background = true
ui.background_color = C.surface
ui.notebook.border.width = 0
ui.notebook.render_background = false

end

if settings.ui then
  install_settings_patch(settings.ui)
else
  core.add_thread(function()
    while not settings.ui do coroutine.yield(0.05) end
    install_settings_patch(settings.ui)
    core.redraw = true
  end)
end

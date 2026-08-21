-- mod-version:3
-- priority:103
-- Functional workbench views for the custom Lite XL layout.

local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local DocView = require "core.docview"
local RootView = require "core.rootview"
local Node = require "core.node"
local TitleView = require "core.titleview"
local process = require "core.process"
local treeview = require "plugins.treeview"
local workbench = require "plugins.lite_vs_workbench"
local nerd = require "libraries.font_symbols_nerdfont_mono_regular"

local ok_scm, scm = pcall(require, "plugins.scm")
local ok_terminal, terminal_plugin = pcall(require, "plugins.terminal")
local ok_manager, plugin_manager = pcall(require, "plugins.plugin_manager")
local ok_projectsearch, projectsearch = pcall(require, "plugins.projectsearch")

local map = nerd.utf8
local icon_font = renderer.font.load(nerd.path, 18 * SCALE,
  { antialiasing = "grayscale", hinting = "full" })
local title_font = style.font

local C = {
  side = { common.color "#181818" },
  editor = { common.color "#1F1F1F" },
  input = { common.color "#313131" },
  hover = { common.color "#2A2D2E" },
  selected = { common.color "#37373D" },
  border = { common.color "#3C3C3C" },
  divider = { common.color "#2B2B2B" },
  focus = { common.color "#0078D4" },
  selection = { common.color "#264F78" },
  button = { common.color "#0078D4" },
  button_hover = { common.color "#026EC1" },
  text = { common.color "#CCCCCC" },
  bright = { common.color "#FFFFFF" },
  dim = { common.color "#9D9D9D" },
  placeholder = { common.color "#989898" },
  green = { common.color "#2EA043" },
  yellow = { common.color "#D29922" },
  red = { common.color "#F85149" },
  blue = { common.color "#4DAAFC" },
}

local HEADER_H = 48 * SCALE
local INPUT_H = 34 * SCALE
local ROW_H = 30 * SCALE
local PAD = 12 * SCALE
local PANEL_HEADER_H = 42 * SCALE
local MOTION_SIDEBAR_RATE = 0.22
local MOTION_PANEL_RATE = 0.20
local MOTION_INDICATOR_RATE = 0.32

local function inside(px, py, x, y, w, h)
  return px >= x and py >= y and px < x + w and py < y + h
end

local function draw_round_rect(x, y, w, h, color)
  if w <= 0 or h <= 0 then return end
  local radius = math.max(2, math.floor(4 * SCALE + 0.5))
  radius = math.min(radius, math.floor(math.min(w, h) / 2))
  if radius < 2 or w < 6 or h < 6 then
    renderer.draw_rect(x, y, w, h, color)
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

local function fit_text(font, text, width)
  text = tostring(text or "")
  if font:get_width(text) <= width then return text end
  local ellipsis = "..."
  while #text > 1 and font:get_width(text .. ellipsis) > width do
    text = text:sub(1, -2)
  end
  return text .. ellipsis
end

local function editor_view()
  local node = core.root_view and core.root_view:get_primary_node()
  return node and node.active_view
end

local function restore_editor_focus()
  local view = editor_view()
  if view then core.set_active_view(view) end
  return view
end

local function open_file_at(filename, line, col, length)
  if not filename then return end
  local view = core.root_view:open_doc(core.open_doc(filename))
  if view and view.doc then
    line, col = line or 1, col or 1
    view.doc:set_selection(line, col, line, col + math.max(0, (length or 1) - 1))
    view:scroll_to_line(line, false, true)
    core.set_active_view(view)
  end
end

-- -------------------------------------------------------------------------
-- Primary sidebar views
-- -------------------------------------------------------------------------

local apply_sidebar_size
local SidebarView = View:extend()

function SidebarView:new(id, title)
  SidebarView.super.new(self)
  self.lite_vs_sidebar = true
  self.id = id
  self.title = title
  self.visible = true
  self.target_size = (config.plugins.treeview and config.plugins.treeview.size) or 373 * SCALE
  self.size.x = self.target_size
  self.hits = {}
  self.hovered = nil
  self.focused_field = nil
  self.fields = {}
  self.field_edits = {}
  self.dragging_field = nil
  self.content_height = self.size.y
  self.scrollable = true
end

function SidebarView:__tostring() return "LiteVSSidebar:" .. self.id end
function SidebarView:get_name() return nil end
function SidebarView:supports_text_input() return self.focused_field ~= nil end

local function text_length(value)
  value = tostring(value or "")
  return value:ulen() or #value
end

local function text_slice(value, first, last)
  value = tostring(value or "")
  if first and last and first > last then return "" end
  return value:usub(first, last) or ""
end

local function field_char(value, index)
  if index < 1 or index > text_length(value) then return "" end
  return text_slice(value, index, index)
end

local function word_char(char)
  return char ~= "" and (char:match("[%w_]") ~= nil or #char > 1)
end

function SidebarView:get_field_state(name)
  local value = tostring(self.fields[name] or "")
  local length = text_length(value)
  local state = self.field_edits[name]
  if not state then
    state = { caret = length, anchor = length, scroll_x = 0, undo = {}, redo = {} }
    self.field_edits[name] = state
  end
  state.caret = common.clamp(state.caret or length, 0, length)
  state.anchor = common.clamp(state.anchor or state.caret, 0, length)
  state.scroll_x = math.max(0, state.scroll_x or 0)
  return state
end

function SidebarView:get_field_selection(name)
  local state = self:get_field_state(name)
  return math.min(state.anchor, state.caret), math.max(state.anchor, state.caret), state
end

function SidebarView:remember_field(name)
  local state = self:get_field_state(name)
  state.undo[#state.undo + 1] = {
    value = self.fields[name] or "", caret = state.caret, anchor = state.anchor
  }
  if #state.undo > 100 then table.remove(state.undo, 1) end
  state.redo = {}
end

function SidebarView:field_changed(name)
  self.next_refresh = system.get_time() + (name == "query" and 0.16 or 0.12)
  if name == "query" then self.scroll.to.y = 0 end
  core.redraw = true
end

function SidebarView:replace_field_selection(text)
  local name = self.focused_field
  if not name then return end
  text = tostring(text or "")
  local value = tostring(self.fields[name] or "")
  local first, last, state = self:get_field_selection(name)
  self:remember_field(name)
  local before = first > 0 and text_slice(value, 1, first) or ""
  local after = last < text_length(value) and text_slice(value, last + 1) or ""
  self.fields[name] = before .. text .. after
  state.caret = first + text_length(text)
  state.anchor = state.caret
  self:field_changed(name)
end

function SidebarView:field_caret_from_x(hit, x)
  local name = hit.value
  local value = tostring(self.fields[name] or "")
  local state = self:get_field_state(name)
  local target = x - hit.text_x + state.scroll_x
  if target <= 0 then return 0 end
  local length = text_length(value)
  local previous = 0
  for index = 1, length do
    local current = style.font:get_width(text_slice(value, 1, index))
    if target < (previous + current) / 2 then return index - 1 end
    previous = current
  end
  return length
end

function SidebarView:set_field_caret(target, selecting)
  local name = self.focused_field
  if not name then return end
  local state = self:get_field_state(name)
  state.caret = common.clamp(target, 0, text_length(self.fields[name] or ""))
  if not selecting then state.anchor = state.caret end
  core.redraw = true
end

function SidebarView:move_field_caret(direction, selecting, by_word)
  local name = self.focused_field
  if not name then return end
  local value = tostring(self.fields[name] or "")
  local first, last, state = self:get_field_selection(name)
  if not selecting and first ~= last then
    return self:set_field_caret(direction < 0 and first or last, false)
  end
  local target = state.caret
  if by_word then
    if direction < 0 then
      while target > 0 and not word_char(field_char(value, target)) do target = target - 1 end
      while target > 0 and word_char(field_char(value, target)) do target = target - 1 end
    else
      local length = text_length(value)
      while target < length and not word_char(field_char(value, target + 1)) do target = target + 1 end
      while target < length and word_char(field_char(value, target + 1)) do target = target + 1 end
    end
  else
    target = target + direction
  end
  self:set_field_caret(target, selecting)
end

function SidebarView:select_field_word(name, caret)
  local value = tostring(self.fields[name] or "")
  local length = text_length(value)
  local state = self:get_field_state(name)
  if length == 0 then state.anchor, state.caret = 0, 0; return end
  local index = common.clamp(caret + 1, 1, length)
  if not word_char(field_char(value, index)) and index > 1 then index = index - 1 end
  local first, last = index, index
  local is_word = word_char(field_char(value, index))
  while first > 1 and word_char(field_char(value, first - 1)) == is_word do first = first - 1 end
  while last < length and word_char(field_char(value, last + 1)) == is_word do last = last + 1 end
  state.anchor, state.caret = first - 1, last
end

function SidebarView:delete_field(backward, by_word)
  local name = self.focused_field
  if not name then return end
  local first, last, state = self:get_field_selection(name)
  if first == last then
    if backward and first > 0 then
      if by_word then
        self:move_field_caret(-1, true, true)
      else
        state.anchor = state.caret - 1
      end
    elseif not backward and last < text_length(self.fields[name] or "") then
      if by_word then
        self:move_field_caret(1, true, true)
      else
        state.caret = state.caret + 1
      end
    else
      return
    end
  end
  self:replace_field_selection("")
end

function SidebarView:copy_field(cut)
  local name = self.focused_field
  if not name then return end
  local first, last = self:get_field_selection(name)
  if first == last then return end
  local value = tostring(self.fields[name] or "")
  system.set_clipboard(text_slice(value, first + 1, last))
  if cut then self:replace_field_selection("") end
end

function SidebarView:paste_field()
  self:replace_field_selection(system.get_clipboard() or "")
end

function SidebarView:select_all_field()
  local name = self.focused_field
  if not name then return end
  local state = self:get_field_state(name)
  state.anchor, state.caret = 0, text_length(self.fields[name] or "")
  core.redraw = true
end

function SidebarView:undo_field(redo)
  local name = self.focused_field
  if not name then return end
  local state = self:get_field_state(name)
  local source, target = redo and state.redo or state.undo, redo and state.undo or state.redo
  local snapshot = table.remove(source)
  if not snapshot then return end
  target[#target + 1] = {
    value = self.fields[name] or "", caret = state.caret, anchor = state.anchor
  }
  self.fields[name] = snapshot.value
  state.caret, state.anchor = snapshot.caret, snapshot.anchor
  self:field_changed(name)
end

function SidebarView:get_scrollable_size()
  return math.max(self.size.y, self.content_height or self.size.y)
end

function SidebarView:on_mouse_wheel(y)
  self.scroll.to.y = self.scroll.to.y + y * -config.mouse_wheel_scroll
  return true
end

function SidebarView:begin_scrolled_content(top, height)
  self.content_height = math.max(self.size.y, top - self.position.y + math.max(0, height))
  core.push_clip_rect(self.position.x, top, self.size.x,
    math.max(0, self.position.y + self.size.y - top))
  return top - self.scroll.y
end

function SidebarView:end_scrolled_content()
  core.pop_clip_rect()
  self:draw_scrollbar()
end

function SidebarView:set_target_size(axis, value)
  if axis == "x" then
    if apply_sidebar_size then return apply_sidebar_size(value, self) end
    self.target_size = math.max(220 * SCALE, value)
    self.size.x = self.target_size
    return true
  end
end

function SidebarView:update()
  local dest = self.visible and self.target_size or 0
  self:move_towards(self.size, "x", dest, MOTION_SIDEBAR_RATE,
    "lite-vs-primary-sidebar")
  SidebarView.super.update(self)
  if self.next_refresh and system.get_time() >= self.next_refresh then
    self.next_refresh = nil
    self:refresh()
  end
end

function SidebarView:add_hit(kind, x, y, w, h, value, action)
  local hit = { kind = kind, x = x, y = y, w = w, h = h, value = value, action = action }
  self.hits[#self.hits + 1] = hit
  return hit
end

function SidebarView:draw_header(actions)
  local x, y, w = self.position.x, self.position.y, self.size.x
  renderer.draw_rect(x, y, w, HEADER_H, C.side)
  common.draw_text(title_font, C.bright, self.title, nil, x + 18 * SCALE, y, 0, HEADER_H)
  local ax = x + w - 12 * SCALE
  for i = #(actions or {}), 1, -1 do
    local action = actions[i]
    ax = ax - 30 * SCALE
    local hit = self:add_hit("action", ax, y + 7 * SCALE, 28 * SCALE, 34 * SCALE, action.id, action.action)
    if self.hovered == hit then
      draw_round_rect(hit.x + 3 * SCALE, hit.y + 3 * SCALE,
        hit.w - 6 * SCALE, hit.h - 6 * SCALE, C.hover)
    end
    common.draw_text(icon_font, C.text, map[action.icon] or "", "center",
      hit.x, hit.y, hit.w, hit.h)
  end
end

function SidebarView:draw_input(name, value, placeholder, x, y, w, icon)
  value = tostring(value or "")
  local focused = self.focused_field == name
  local border = focused and C.focus or C.border
  draw_round_rect(x, y, w, INPUT_H, border)
  draw_round_rect(x + SCALE, y + SCALE, w - 2 * SCALE, INPUT_H - 2 * SCALE, C.input)
  local tx = x + 9 * SCALE
  if icon then
    common.draw_text(icon_font, C.dim, map[icon] or "", nil, tx, y, 0, INPUT_H)
    tx = tx + 24 * SCALE
  end
  local text_w = math.max(0, x + w - tx - 8 * SCALE)
  local state = self:get_field_state(name)
  local caret_w = style.font:get_width(text_slice(value, 1, state.caret))
  if focused then
    if caret_w - state.scroll_x > text_w - 2 * SCALE then
      state.scroll_x = caret_w - text_w + 2 * SCALE
    elseif caret_w - state.scroll_x < 0 then
      state.scroll_x = caret_w
    end
  else
    state.scroll_x = 0
  end
  state.scroll_x = common.clamp(state.scroll_x, 0,
    math.max(0, style.font:get_width(value) - text_w + 2 * SCALE))
  core.push_clip_rect(tx, y + 2 * SCALE, text_w, INPUT_H - 4 * SCALE)
  if value == "" then
    common.draw_text(style.font, C.placeholder, placeholder, nil, tx, y, 0, INPUT_H)
  else
    local draw_x = tx - state.scroll_x
    local first, last = self:get_field_selection(name)
    if focused and first ~= last then
      local selection_x = draw_x + style.font:get_width(text_slice(value, 1, first))
      local selection_w = style.font:get_width(text_slice(value, first + 1, last))
      renderer.draw_rect(selection_x, y + 5 * SCALE,
        selection_w, INPUT_H - 10 * SCALE, C.selection)
    end
    common.draw_text(style.font, C.text, value, nil, draw_x, y, 0, INPUT_H)
  end
  if focused and (system.get_time() % 1) < 0.55 then
    renderer.draw_rect(tx + caret_w - state.scroll_x, y + 6 * SCALE,
      math.max(1, SCALE), INPUT_H - 12 * SCALE, C.bright)
  end
  core.pop_clip_rect()
  local hit = self:add_hit("field", x, y, w, INPUT_H, name)
  hit.text_x, hit.text_w = tx, text_w
  return hit
end

function SidebarView:draw_button(label, x, y, w, action, icon)
  local hit = self:add_hit("button", x, y, w, INPUT_H, label, action)
  local inset = self.hovered == hit and 2 * SCALE or 0
  draw_round_rect(x + inset, y + inset, w - inset * 2, INPUT_H - inset * 2,
    self.hovered == hit and C.button_hover or C.button)
  local tx = x + 10 * SCALE
  if icon then
    common.draw_text(icon_font, C.bright, map[icon] or "", nil, tx, y, 0, INPUT_H)
    tx = tx + 23 * SCALE
  end
  common.draw_text(style.font, C.bright, label, nil, tx, y, 0, INPUT_H)
  return hit
end

function SidebarView:on_mouse_moved(x, y, ...)
  if self.dragging_field and self.dragging_field_hit then
    local state = self:get_field_state(self.dragging_field)
    state.caret = self:field_caret_from_x(self.dragging_field_hit, x)
    self.hovered = self.dragging_field_hit
    core.request_cursor "ibeam"
    core.redraw = true
    return true
  end
  self.hovered = nil
  for index = #self.hits, 1, -1 do
    local hit = self.hits[index]
    if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
      self.hovered = hit
      core.request_cursor(hit.kind == "field" and "ibeam" or "hand")
      break
    end
  end
  return SidebarView.super.on_mouse_moved(self, x, y, ...)
end

function SidebarView:on_mouse_left()
  self.hovered = nil
  if not self.dragging_field then return SidebarView.super.on_mouse_left(self) end
end

function SidebarView:on_mouse_pressed(button, x, y, clicks)
  if button ~= "left" then return SidebarView.super.on_mouse_pressed(self, button, x, y, clicks) end
  for index = #self.hits, 1, -1 do
    local hit = self.hits[index]
    if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
      if hit.kind == "field" then
        self.focused_field = hit.value
        core.set_active_view(self)
        local state = self:get_field_state(hit.value)
        local caret = self:field_caret_from_x(hit, x)
        if clicks and clicks >= 3 then
          state.anchor, state.caret = 0, text_length(self.fields[hit.value] or "")
        elseif clicks and clicks >= 2 then
          self:select_field_word(hit.value, caret)
        else
          state.caret, state.anchor = caret, caret
        end
        self.dragging_field = hit.value
        self.dragging_field_hit = hit
      elseif hit.action then
        hit.action(hit)
      elseif hit.kind == "result" and self.activate_result then
        self:activate_result(hit.value)
      end
      core.redraw = true
      return true
    end
  end
  self.focused_field = nil
  self.dragging_field, self.dragging_field_hit = nil, nil
  return SidebarView.super.on_mouse_pressed(self, button, x, y, clicks)
end

function SidebarView:on_mouse_released(button, x, y)
  if button == "left" and self.dragging_field then
    self.dragging_field, self.dragging_field_hit = nil, nil
    return true
  end
  return SidebarView.super.on_mouse_released(self, button, x, y)
end

function SidebarView:on_text_input(text)
  if not self.focused_field then return end
  self:replace_field_selection(text)
  return true
end

function SidebarView:backspace()
  self:delete_field(true, false)
end

function SidebarView:submit()
  self:refresh()
end

local SearchView = SidebarView:extend()

function SearchView:new()
  SearchView.super.new(self, "search", "Search")
  self.fields.query = ""
  self.fields.replace = ""
  self.options = { case = false, word = false, regex = false }
  self.results = {}
  self.generation = 0
end

local function find_match(line, needle, options)
  if needle == "" then return nil end
  local source, query = line, needle
  if not options.case then source, query = source:lower(), query:lower() end
  local ok, first, last
  if options.regex then
    ok, first, last = pcall(string.find, source, query)
    if not ok then return nil end
  else
    first, last = source:find(query, 1, true)
  end
  if not first then return nil end
  if options.word then
    local before = first > 1 and source:sub(first - 1, first - 1) or ""
    local after = last < #source and source:sub(last + 1, last + 1) or ""
    if before:match("[%w_]") or after:match("[%w_]") then return nil end
  end
  return first, last
end

function SearchView:refresh()
  self.generation = self.generation + 1
  local generation = self.generation
  local needle = self.fields.query or ""
  self.results = {}
  if needle == "" then
    self.searching = false
    return
  end
  self.searching = true
  if ok_projectsearch and projectsearch.ResultsView then
    -- Reuse Lite XL's proven project iterator/search worker, but keep its
    -- results inside the Lite VS sidebar instead of opening a separate tab.
    local job = projectsearch.ResultsView(nil, needle, function(line)
      return find_match(line, needle, self.options)
    end)
    self.search_job = job
    core.add_thread(function()
      while job.searching do
        if generation ~= self.generation then return end
        coroutine.yield(0.05)
      end
      if generation ~= self.generation then return end
      self.results = {}
      for index, result in ipairs(job.results or {}) do
        if index > 500 then break end
        local filename = core.project_absolute_path(result.file)
        self.results[#self.results + 1] = {
          filename = filename,
          relative = common.relative_path(core.project_dir or filename, filename),
          line = result.line, col = result.col,
          length = math.max(1, text_length(needle)), text = result.text,
        }
      end
      self.searching = false
      self.content_height = self.size.y
      core.redraw = true
    end)
    return
  end
  core.add_thread(function()
    local count = 0
    for dir, item in core.get_project_files() do
      if generation ~= self.generation then return end
      if item.type == "file" then
        local filename = dir .. PATHSEP .. item.filename
        local info = system.get_file_info(filename)
        if not info or not info.size or info.size < 2 * 1024 * 1024 then
          local handle = io.open(filename, "rb")
          if handle then
            local line_no = 0
            for line in handle:lines() do
              line_no = line_no + 1
              if not line:find("\0", 1, true) then
                local first, last = find_match(line, needle, self.options)
                if first then
                  self.results[#self.results + 1] = {
                    filename = filename,
                    relative = common.relative_path(core.project_dir or dir, filename),
                    line = line_no, col = first, length = last - first + 1,
                    text = line:gsub("^%s+", "")
                  }
                  if #self.results >= 500 then break end
                end
              end
            end
            handle:close()
          end
        end
        count = count + 1
        if count % 20 == 0 then coroutine.yield() end
        if #self.results >= 500 then break end
      end
    end
    if generation == self.generation then self.searching = false end
    core.redraw = true
  end)
end

function SearchView:activate_result(result)
  open_file_at(result.filename, result.line, result.col, result.length)
end

function SearchView:draw()
  self:draw_background(C.side)
  self.hits = {}
  self:draw_header({
    { id = "refresh", icon = "cod-refresh", action = function() self:refresh() end },
    { id = "collapse", icon = "cod-collapse_all", action = function() self.results = {} end },
  })
  local x, y, w = self.position.x + PAD, self.position.y + HEADER_H + 8 * SCALE,
    self.size.x - PAD * 2
  self:draw_input("query", self.fields.query, "Search", x, y, w, "cod-search")
  y = y + INPUT_H + 6 * SCALE
  self:draw_input("replace", self.fields.replace, "Replace", x + 24 * SCALE, y,
    w - 24 * SCALE, "cod-replace")
  y = y + INPUT_H + 7 * SCALE
  local options = {
    { "case", "Aa" }, { "word", "ab" }, { "regex", ".*" }
  }
  local ox = x + w - #options * 38 * SCALE
  for _, spec in ipairs(options) do
    local id, label = spec[1], spec[2]
    local hit = self:add_hit("option", ox, y, 34 * SCALE, 26 * SCALE, id,
      function() self.options[id] = not self.options[id]; self:refresh() end)
    if self.options[id] or self.hovered == hit then
      draw_round_rect(hit.x, hit.y, hit.w, hit.h, self.options[id] and C.selected or C.hover)
    end
    common.draw_text(style.font, self.options[id] and C.bright or C.dim,
      label, "center", hit.x, hit.y, hit.w, hit.h)
    ox = ox + 38 * SCALE
  end
  y = y + 34 * SCALE
  renderer.draw_rect(self.position.x, y, self.size.x, style.divider_size, C.divider)
  local summary = self.searching and "Searching..." or
    (#self.results == 0 and ((self.fields.query == "") and "Type a query to search files" or "No results")
      or (#self.results .. " results"))
  common.draw_text(style.font, C.dim, summary, nil, x, y + 4 * SCALE, 0, ROW_H)
  y = y + ROW_H + 4 * SCALE
  local bottom = self.position.y + self.size.y
  local list_top = y
  y = self:begin_scrolled_content(list_top, #self.results * ROW_H * 2)
  for _, result in ipairs(self.results) do
    if y + ROW_H * 2 >= list_top and y < bottom then
      local hit = self:add_hit("result", self.position.x + 4 * SCALE, y,
        self.size.x - 8 * SCALE, ROW_H * 2, result)
      if self.hovered == hit then
        draw_round_rect(hit.x + 2 * SCALE, hit.y + 1 * SCALE,
          hit.w - 4 * SCALE, hit.h - 2 * SCALE, C.hover)
      end
      common.draw_text(style.font, C.text,
        fit_text(style.font, result.relative .. ":" .. result.line, hit.w - 20 * SCALE),
        nil, x, y, 0, ROW_H)
      common.draw_text(style.font, C.dim,
        fit_text(style.font, result.text, hit.w - 20 * SCALE),
        nil, x + 12 * SCALE, y + ROW_H, 0, ROW_H)
    end
    y = y + ROW_H * 2
  end
  self:end_scrolled_content()
end

local SCMView = SidebarView:extend()

function SCMView:new()
  SCMView.super.new(self, "source", "Source Control")
  self.fields.message = ""
  self.changes = {}
  self.branch = ""
  self.last_refresh = 0
end

function SCMView:refresh()
  self.changes = {}
  if not ok_scm or not core.project_dir then return end
  scm.update()
  self.branch = scm.get_branch(core.project_dir) or ""
  core.add_thread(function()
    coroutine.yield(0.15)
    local seen = {}
    for dir, item in core.get_project_files() do
      if item.type == "file" then
        local filename = dir .. PATHSEP .. item.filename
        local change = scm.get_path_changes(filename)
        if change and change.status and not seen[filename] then
          seen[filename] = true
          self.changes[#self.changes + 1] = {
            filename = filename,
            relative = common.relative_path(core.project_dir, filename),
            status = change.status,
            staged = change.staged,
          }
        end
      end
    end
    table.sort(self.changes, function(a, b) return a.relative < b.relative end)
    self.branch = scm.get_branch(core.project_dir) or self.branch
    core.redraw = true
  end)
end

function SCMView:commit()
  local message = self.fields.message or ""
  if message == "" or not core.project_dir then return end
  local proc, errmsg = process.start({ "git", "commit", "-m", message },
    { cwd = core.project_dir })
  if not proc then
    core.error("Unable to start git commit: %s", errmsg or "unknown error")
    return
  end
  self.fields.message = ""
  core.add_thread(function()
    while proc:running() do coroutine.yield(0.05) end
    if proc:returncode() == 0 then
      core.log("Source control commit completed.")
      self:refresh()
    else
      local stderr = proc:read_stderr(64 * 1024) or ""
      core.error("Source control commit failed: %s", stderr ~= "" and stderr or proc:returncode())
    end
  end)
end

function SCMView:activate_result(result)
  open_file_at(result.filename, 1, 1, 1)
  command.perform "scm:file-diff"
end

function SCMView:submit() self:commit() end

function SCMView:draw()
  self:draw_background(C.side)
  self.hits = {}
  self:draw_header({
    { id = "diff", icon = "cod-diff", action = function() restore_editor_focus(); command.perform "scm:global-diff" end },
    { id = "refresh", icon = "cod-refresh", action = function() self:refresh() end },
    { id = "more", icon = "cod-ellipsis", action = function() restore_editor_focus(); command.perform "scm:project-status" end },
  })
  local x, y, w = self.position.x + PAD, self.position.y + HEADER_H + 8 * SCALE,
    self.size.x - PAD * 2
  self:draw_input("message", self.fields.message, "Message (Ctrl+Enter to commit)", x, y, w, "cod-git_commit")
  y = y + INPUT_H + 8 * SCALE
  self:draw_button("Commit", x, y, w, function() self:commit() end, "cod-check")
  y = y + INPUT_H + 14 * SCALE
  common.draw_text(title_font, C.bright,
    "CHANGES" .. (#self.changes > 0 and ("  " .. #self.changes) or ""), nil,
    self.position.x + 18 * SCALE, y, 0, ROW_H)
  common.draw_text(style.font, C.dim, self.branch, "right", x, y, w, ROW_H)
  y = y + ROW_H
  local list_top = y
  if not ok_scm then
    common.draw_text(style.font, C.dim, "SCM plugin is unavailable", nil, x, y, 0, ROW_H)
    self.content_height = self.size.y
    self:draw_scrollbar()
  elseif not core.project_dir then
    common.draw_text(style.font, C.dim, "Open a folder to use source control", nil, x, y, 0, ROW_H)
    self.content_height = self.size.y
    self:draw_scrollbar()
  elseif #self.changes == 0 then
    common.draw_text(style.font, C.dim, "No pending changes", nil, x, y, 0, ROW_H)
    self.content_height = self.size.y
    self:draw_scrollbar()
  else
    local bottom = self.position.y + self.size.y
    y = self:begin_scrolled_content(list_top, #self.changes * ROW_H)
    for _, change in ipairs(self.changes) do
      if y + ROW_H >= list_top and y < bottom then
        local hit = self:add_hit("result", self.position.x + 4 * SCALE, y,
          self.size.x - 8 * SCALE, ROW_H, change)
        if self.hovered == hit then
          draw_round_rect(hit.x + 2 * SCALE, hit.y + 1 * SCALE,
            hit.w - 4 * SCALE, hit.h - 2 * SCALE, C.hover)
        end
        local status_color = change.status == "added" and C.green or
          (change.status == "deleted" and C.red or C.yellow)
        common.draw_text(icon_font, status_color, map["cod-git_commit"] or "", nil,
          x, y, 0, ROW_H)
        common.draw_text(style.font, C.text,
          fit_text(style.font, change.relative, w - 58 * SCALE), nil,
          x + 26 * SCALE, y, 0, ROW_H)
        common.draw_text(style.font, status_color, change.status:sub(1, 1):upper(), "right",
          x, y, w, ROW_H)
      end
      y = y + ROW_H
    end
    self:end_scrolled_content()
  end
end

local RunView = SidebarView:extend()

function RunView:new()
  RunView.super.new(self, "run", "Run and Debug")
end

function RunView:draw()
  self:draw_background(C.side)
  self.hits = {}
  self:draw_header({
    { id = "config", icon = "cod-gear", action = function() command.perform "lite-vs:run-commands" end },
    { id = "more", icon = "cod-ellipsis", action = function() command.perform "lite-vs:run-commands" end },
  })
  local x = self.position.x + 26 * SCALE
  local w = self.size.x - 52 * SCALE
  local y = self.position.y + HEADER_H + 44 * SCALE
  common.draw_text(style.font, C.text, "Run and Debug", nil, x, y, 0, ROW_H)
  y = y + ROW_H + 10 * SCALE
  common.draw_text(style.font, C.dim,
    "Open a file and run a configured build, debug, macro, or terminal command.",
    nil, x, y, w, ROW_H * 3)
  y = y + ROW_H * 3 + 12 * SCALE
  self:draw_button("Run and Debug", x, y, w,
    function() command.perform "lite-vs:run-commands" end, "cod-debug_start")
  y = y + INPUT_H + 12 * SCALE
  self:draw_button("Open Terminal", x, y, w,
    function() command.perform "lite-vs:terminal-panel" end, "cod-terminal")
end

local ExtensionsView = SidebarView:extend()

function ExtensionsView:new()
  ExtensionsView.super.new(self, "extensions", "Extensions")
  self.fields.query = ""
  self.extensions = {}
  self.manager_loading = false
  self.manager_error = nil
  self.manager_progress = nil
  self:refresh()
end

local extension_status_names = {
  installed = "Installed", bundled = "Built-in", builtin = "Built-in",
  special = "Built-in", core = "Core", orphan = "Installed (local)",
  available = "Available", incompatible = "Incompatible",
}

function ExtensionsView:refresh()
  local rows, seen = {}, {}
  local query = (self.fields.query or ""):lower()
  local function add(name, status, description, addon)
    name = tostring(name or ""):gsub("%.lua$", "")
    if name == "" then return end
    local key = name:lower()
    local existing = seen[key]
    if existing then
      existing.addon = addon or existing.addon
      existing.raw_status = addon and addon.status or existing.raw_status
      existing.status = extension_status_names[existing.raw_status] or existing.status
      if description and description ~= "" then existing.description = description end
      return
    end
    local raw_status = addon and addon.status or status or "installed"
    local row = {
      name = name,
      raw_status = raw_status,
      status = extension_status_names[raw_status] or tostring(raw_status),
      description = description or "Lite XL extension",
      addon = addon,
    }
    seen[key] = row
    rows[#rows + 1] = row
  end
  for _, base in ipairs({ USERDIR .. PATHSEP .. "plugins", DATADIR .. PATHSEP .. "plugins" }) do
    local list = system.list_dir(base) or {}
    for _, name in ipairs(list) do
      add(name, base:find(USERDIR, 1, true) and "installed" or "builtin")
    end
  end
  if ok_manager and plugin_manager.addons then
    for _, addon in ipairs(plugin_manager.addons) do
      if query ~= "" or addon.status ~= "available" then
        add(addon.id, addon.status, addon.description, addon)
      end
    end
  end
  self.extensions = {}
  for _, row in ipairs(rows) do
    if query == "" or row.name:lower():find(query, 1, true) or row.description:lower():find(query, 1, true) then
      self.extensions[#self.extensions + 1] = row
    end
  end
  table.sort(self.extensions, function(a, b) return a.name < b.name end)

  -- The sidebar behaves like Lite VS's Extensions search: the local installed
  -- list is immediate, while repository results arrive asynchronously.
  if query ~= "" and ok_manager and not plugin_manager.addons and not self.manager_loading then
    self:refresh_manager()
  end
end

function ExtensionsView:submit() self:refresh() end

function ExtensionsView:refresh_manager()
  if not ok_manager or self.manager_loading then return end
  self.manager_loading, self.manager_error = true, nil
  local options = {
    progress = function(progress)
      self.manager_progress = progress
      core.redraw = true
    end
  }
  plugin_manager:refresh(options):done(function()
    self.manager_loading, self.manager_progress = false, nil
    self:refresh()
    core.redraw = true
  end):fail(function(message)
    self.manager_loading, self.manager_progress = false, nil
    self.manager_error = tostring(message or "Unable to refresh extension catalog")
    core.redraw = true
  end)
end

function ExtensionsView:activate_result(extension)
  if not ok_manager then return end
  restore_editor_focus()
  local view = plugin_manager.view(plugin_manager)
  core.root_view:get_active_node_default():add_view(view)
  if not extension then return end
  core.add_thread(function()
    local attempts = 0
    while not view.initialized and attempts < 200 do
      attempts = attempts + 1
      coroutine.yield(0.05)
    end
    if not view.initialized then return end
    local plugins = view:get_sorted_plugins()
    for index, addon in ipairs(plugins) do
      if addon.id == extension.name or addon.id == (extension.addon and extension.addon.id) then
        view.selected_plugin, view.selected_plugin_idx = addon, index
        local line_height = style.font:get_height() + style.padding.y
        view.scroll.to.y = math.max(0, (index - 1) * line_height)
        break
      end
    end
    core.redraw = true
  end)
end

function ExtensionsView:extension_action(extension)
  if not extension or extension.raw_status ~= "available" or not extension.addon then
    return self:activate_result(extension)
  end
  if self.manager_loading then return end
  self.manager_loading, self.manager_error = true, nil
  plugin_manager:install(extension.addon, {
    progress = function(progress)
      self.manager_progress = progress
      core.redraw = true
    end,
    restart = false,
  }):done(function()
    self.manager_loading, self.manager_progress = false, nil
    self:refresh_manager()
  end):fail(function(message)
    self.manager_loading, self.manager_progress = false, nil
    self.manager_error = tostring(message or "Extension installation failed")
    core.redraw = true
  end)
end

function ExtensionsView:draw()
  self:draw_background(C.side)
  self.hits = {}
  self:draw_header({
    { id = "refresh", icon = "cod-refresh", action = function() self:refresh_manager() end },
    { id = "more", icon = "cod-ellipsis", action = function() restore_editor_focus(); command.perform "plugin-manager:show" end },
  })
  local x, y, w = self.position.x + PAD, self.position.y + HEADER_H + 8 * SCALE,
    self.size.x - PAD * 2
  self:draw_input("query", self.fields.query, "Search Extensions", x, y, w, "cod-search")
  y = y + INPUT_H + 12 * SCALE
  local heading = self.fields.query == "" and "INSTALLED" or
    (self.manager_loading and "SEARCHING EXTENSIONS" or ("EXTENSIONS  " .. #self.extensions))
  common.draw_text(title_font, C.bright, heading, nil, x, y, 0, ROW_H)
  if self.manager_progress then
    common.draw_text(style.font, C.dim, tostring(self.manager_progress), "right", x, y, w, ROW_H)
  end
  y = y + ROW_H
  if self.manager_error then
    common.draw_text(style.font, C.red, fit_text(style.font, self.manager_error, w), nil,
      x, y, 0, ROW_H)
    y = y + ROW_H
  end
  local list_top = y
  local bottom = self.position.y + self.size.y
  y = self:begin_scrolled_content(list_top, #self.extensions * ROW_H * 2)
  for _, ext in ipairs(self.extensions) do
    if y + ROW_H * 2 >= list_top and y < bottom then
      local hit = self:add_hit("result", self.position.x + 4 * SCALE, y,
        self.size.x - 8 * SCALE, ROW_H * 2, ext)
      if self.hovered == hit then
        draw_round_rect(hit.x + 2 * SCALE, hit.y + 1 * SCALE,
          hit.w - 4 * SCALE, hit.h - 2 * SCALE, C.hover)
      end
      local action_label = ext.raw_status == "available" and "Install" or "Manage"
      local action_w = 66 * SCALE
      local action_hit = self:add_hit("extension-action",
        self.position.x + self.size.x - PAD - action_w, y + 7 * SCALE,
        action_w, 26 * SCALE, ext,
        function() self:extension_action(ext) end)
      draw_round_rect(action_hit.x, action_hit.y, action_hit.w, action_hit.h,
        self.hovered == action_hit and C.button_hover or
          (ext.raw_status == "available" and C.button or C.selected))
      common.draw_text(style.font, C.bright, action_label, "center",
        action_hit.x, action_hit.y, action_hit.w, action_hit.h)
      common.draw_text(icon_font, C.blue, map["cod-extensions"] or "", nil,
        x, y, 0, ROW_H * 2)
      common.draw_text(style.font, C.text,
        fit_text(style.font, ext.name, w - 44 * SCALE - action_w), nil,
        x + 34 * SCALE, y, 0, ROW_H)
      common.draw_text(style.font, C.dim,
        fit_text(style.font, ext.status .. " - " .. ext.description,
          w - 44 * SCALE - action_w), nil,
        x + 34 * SCALE, y + ROW_H, 0, ROW_H)
    end
    y = y + ROW_H * 2
  end
  self:end_scrolled_content()
end

local sidebar_node = core.root_view.root_node:get_node_for_view(treeview)
local sidebar_views = {
  search = SearchView(), source = SCMView(), run = RunView(), extensions = ExtensionsView()
}
for _, view in pairs(sidebar_views) do table.insert(sidebar_node.views, view) end

-- The Activity Bar is a fixed child nested inside the original TreeView split.
-- Lite XL normally treats that whole subtree as non-resizable because one of
-- its children is fixed.  Mark only the outer group as a resize proxy; its own
-- Activity Bar divider remains fixed while the Workbench/sidebar divider gets
-- the native horizontal resize cursor and drag behavior.
local sidebar_target_size = math.max(373 * SCALE,
  (config.plugins.treeview and config.plugins.treeview.size) or treeview.target_size or 373 * SCALE)

apply_sidebar_size = function(value)
  local root_width = core.root_view and core.root_view.size.x or value
  local maximum = math.max(220 * SCALE, root_width - 320 * SCALE)
  sidebar_target_size = common.clamp(value, 220 * SCALE, maximum)
  treeview.target_size = sidebar_target_size
  for _, sidebar in pairs(sidebar_views) do
    sidebar.target_size = sidebar_target_size
    sidebar.size.x = sidebar_target_size
  end
  if sidebar_node.active_view == treeview then treeview.size.x = sidebar_target_size end
  if config.plugins.treeview then config.plugins.treeview.size = sidebar_target_size end
  core.redraw = true
  return true
end

local tree_set_target_size = treeview.set_target_size
function treeview:set_target_size(axis, value)
  if axis == "x" then return apply_sidebar_size(value, self) end
  return tree_set_target_size(self, axis, value)
end

apply_sidebar_size(sidebar_target_size)
core.add_thread(function()
  -- user_settings.lua is merged after plugin construction.  Re-read the final
  -- configured width once startup has settled so Explorer opens at the same
  -- width as Lite VS instead of the treeview plugin's narrow default.
  coroutine.yield(0.75)
  if config.plugins.treeview and config.plugins.treeview.size then
    apply_sidebar_size(math.max(373 * SCALE, config.plugins.treeview.size))
  end
end)
sidebar_node.resizable = true

local sidebar_group = sidebar_node:get_parent_node(core.root_view.root_node)
if sidebar_group then
  sidebar_group.lite_vs_sidebar_resize_proxy = {
    sidebar = sidebar_node,
    activity = core.lite_vs_activity_view,
  }
end

local node_is_resizable = Node.is_resizable
function Node:is_resizable(axis)
  if axis == "x" and self.lite_vs_sidebar_resize_proxy then return true end
  return node_is_resizable(self, axis)
end

local node_resize = Node.resize
function Node:resize(axis, value)
  local proxy = self.lite_vs_sidebar_resize_proxy
  if axis == "x" and proxy then
    local activity_width = proxy.activity and proxy.activity.size.x or 56 * SCALE
    return proxy.sidebar:resize("x", value - activity_width - style.divider_size)
  end
  return node_resize(self, axis, value)
end

local sidebar_indexes = { explorer = 1, search = 2, source = 3, run = 4, extensions = 5 }

local function sidebar_visible(view)
  if view == treeview then return treeview.visible end
  return view.visible
end

local function set_sidebar_visible(view, visible)
  if view == treeview then treeview.visible = visible else view.visible = visible end
end

local function show_sidebar(id, toggle)
  local view = id == "explorer" and treeview or sidebar_views[id]
  if not view then return end
  local current = sidebar_node.active_view
  local current_was_open = current and sidebar_visible(current)
  if toggle and current == view and current_was_open then
    set_sidebar_visible(view, false)
  else
    local start_width = current_was_open and current.size.x or 0
    set_sidebar_visible(view, true)
    view.size.x = math.max(0, start_width)
    sidebar_node:set_active_view(view)
    if view.refresh then view:refresh() end
  end
  local activity = core.lite_vs_activity_view
  if activity then activity.selected_index = sidebar_indexes[id] or activity.selected_index end
  core.root_view.root_node:update_layout()
  core.redraw = true
end

local function toggle_primary_sidebar()
  local view = sidebar_node.active_view
  set_sidebar_visible(view, not sidebar_visible(view))
  core.root_view.root_node:update_layout()
  core.redraw = true
end

-- Explorer's Open Editors section is part of the sidebar rather than another
-- floating picker.  It remains backed by the real editor nodes, including the
-- per-row close buttons.
local function open_editor_entries()
  local entries = {}
  for _, view in ipairs(core.root_view.root_node:get_children()) do
    if view:is(DocView) then
      entries[#entries + 1] = {
        view = view,
        name = view:get_name(),
        modified = view.doc and view.doc:is_dirty(),
      }
    end
  end
  return entries
end

local function open_editors_height()
  return 28 * SCALE + math.min(5, #open_editor_entries()) * ROW_H
end

local tree_content_offset = treeview.get_content_offset
function treeview:get_content_offset()
  local x, y = tree_content_offset(self)
  return x, y + open_editors_height()
end

local tree_scrollable_size = treeview.get_scrollable_size
function treeview:get_scrollable_size()
  return tree_scrollable_size(self) + open_editors_height()
end

local tree_draw = treeview.draw
function treeview:draw()
  local logical_visible = self.visible
  local animating_out = not logical_visible and self.size.x > 0.5
  if animating_out then self.visible = true end
  tree_draw(self)
  if animating_out then self.visible = logical_visible end
  if not logical_visible and not animating_out then return end
  local header_x, header_y, w = self.position.x, self.position.y, self.size.x
  self.lite_vs_explorer_header_hit = {
    x = header_x + w - 48 * SCALE, y = header_y + 7 * SCALE,
    w = 40 * SCALE, h = 34 * SCALE
  }
  if self.lite_vs_explorer_header_hover then
    draw_round_rect(self.lite_vs_explorer_header_hit.x + 4 * SCALE,
      self.lite_vs_explorer_header_hit.y + 3 * SCALE,
      self.lite_vs_explorer_header_hit.w - 8 * SCALE,
      self.lite_vs_explorer_header_hit.h - 6 * SCALE, C.hover)
    common.draw_text(icon_font, C.bright, map["cod-ellipsis"] or "", "center",
      self.lite_vs_explorer_header_hit.x, self.lite_vs_explorer_header_hit.y,
      self.lite_vs_explorer_header_hit.w, self.lite_vs_explorer_header_hit.h)
  end
  local x, y = self.position.x, self.position.y + HEADER_H
  local entries = open_editor_entries()
  self.lite_vs_open_editor_hits = {}
  renderer.draw_rect(x, y, w, 28 * SCALE, C.side)
  common.draw_text(icon_font, C.text, map["cod-chevron_down"] or "", nil,
    x + 8 * SCALE, y, 0, 28 * SCALE)
  common.draw_text(title_font, C.bright, "OPEN EDITORS", nil,
    x + 30 * SCALE, y, 0, 28 * SCALE)
  common.draw_text(style.font, C.dim, tostring(#entries), "right",
    x + 8 * SCALE, y, w - 20 * SCALE, 28 * SCALE)
  y = y + 28 * SCALE
  local active = editor_view()
  for i, entry in ipairs(entries) do
    if i > 5 then break end
    local hit = { view = entry.view, x = x + 3 * SCALE, y = y,
      w = w - 6 * SCALE, h = ROW_H }
    hit.close_x = x + w - 32 * SCALE
    self.lite_vs_open_editor_hits[#self.lite_vs_open_editor_hits + 1] = hit
    if self.lite_vs_open_editor_hover == hit or active == entry.view then
      renderer.draw_rect(hit.x, hit.y, hit.w, hit.h,
        active == entry.view and C.selected or C.hover)
    end
    local filename = entry.view.doc and (entry.view.doc.abs_filename or entry.view.doc.filename) or ""
    local icon = filename:match("%.py$") and "seti-python" or "cod-file"
    common.draw_text(icon_font, filename:match("%.py$") and C.blue or C.text,
      map[icon] or map["cod-file"] or "", nil, x + 15 * SCALE, y, 0, ROW_H)
    common.draw_text(style.font, entry.modified and C.bright or C.text,
      fit_text(style.font, entry.name, w - 82 * SCALE), nil,
      x + 43 * SCALE, y, 0, ROW_H)
    if self.lite_vs_open_editor_hover == hit or active == entry.view then
      common.draw_text(icon_font, C.text, map[entry.modified and "cod-circle_filled" or "cod-close"] or "",
        "center", hit.close_x, y, 28 * SCALE, ROW_H)
    end
    y = y + ROW_H
  end
  renderer.draw_rect(x, y, w, style.divider_size, C.divider)
end

local tree_mouse_moved = treeview.on_mouse_moved
function treeview:on_mouse_moved(x, y, ...)
  self.lite_vs_open_editor_hover = nil
  self.lite_vs_explorer_header_hover = self.lite_vs_explorer_header_hit and
    inside(x, y, self.lite_vs_explorer_header_hit.x, self.lite_vs_explorer_header_hit.y,
      self.lite_vs_explorer_header_hit.w, self.lite_vs_explorer_header_hit.h)
  if self.lite_vs_explorer_header_hover then core.request_cursor "hand" end
  for _, hit in ipairs(self.lite_vs_open_editor_hits or {}) do
    if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
      self.lite_vs_open_editor_hover = hit
      core.request_cursor "arrow"
      break
    end
  end
  return tree_mouse_moved(self, x, y, ...)
end

local tree_mouse_pressed = treeview.on_mouse_pressed
function treeview:on_mouse_pressed(button, x, y, clicks)
  if button == "left" then
    local header = self.lite_vs_explorer_header_hit
    if header and inside(x, y, header.x, header.y, header.w, header.h) then
      workbench.open_menu("Explorer Actions", header.x - 250 * SCALE, header.y + header.h, {
        { text = "New Text File", command = "core:new-doc", shortcut = "Ctrl+N" },
        { text = "Open File...", command = "core:open-file", shortcut = "Ctrl+O" },
        { text = "Open Folder...", command = "core:open-project-folder", shortcut = "Ctrl+Shift+O" },
        { separator = true },
        { text = "Refresh Explorer", action = function()
          treeview.cache = {}; core.rescan_project_directories()
        end, shortcut = "" },
        { text = "Collapse Folders", action = function()
          for _, dir_cache in pairs(treeview.cache or {}) do
            for _, cached in pairs(dir_cache) do
              if cached.depth and cached.depth > 0 then cached.expanded = false end
            end
          end
          core.redraw = true
        end, shortcut = "" },
      })
      return true
    end
    for _, hit in ipairs(self.lite_vs_open_editor_hits or {}) do
      if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
        local node = core.root_view.root_node:get_node_for_view(hit.view)
        if node then
          if x >= hit.close_x then node:close_view(core.root_view.root_node, hit.view)
          else node:set_active_view(hit.view) end
        end
        return true
      end
    end
  end
  return tree_mouse_pressed(self, button, x, y, clicks)
end

-- -------------------------------------------------------------------------
-- True secondary sidebar with a live outline.
-- -------------------------------------------------------------------------

local SecondaryView = View:extend()

function SecondaryView:new()
  SecondaryView.super.new(self)
  self.size.x = 0
  self.target_size = 330 * SCALE
  self.target_width = 0
  self.visible = false
  self.hits = {}
  self.hovered = nil
end

function SecondaryView:get_name() return nil end
function SecondaryView:__tostring() return "LiteVSSecondarySidebar" end

function SecondaryView:set_target_size(axis, value)
  if axis == "x" then
    value = math.max(0, value)
    self.size.x = value
    self.target_width = value
    if value > 1 then
      self.target_size = math.max(220 * SCALE, value)
      self.visible = true
    else
      self.visible = false
    end
    return true
  end
end

function SecondaryView:update()
  self.target_width = self.visible and self.target_size or 0
  self:move_towards(self.size, "x", self.target_width,
    MOTION_SIDEBAR_RATE, "lite-vs-secondary-sidebar")
  return SecondaryView.super.update(self)
end

function SecondaryView:get_outline()
  local view = editor_view()
  local rows = {}
  if not view or not view.doc then return rows end
  for line_no, line in ipairs(view.doc.lines or {}) do
    local label = line:match("^%s*class%s+([%w_]+)")
      or line:match("^%s*def%s+([%w_]+)")
      or line:match("^%s*local%s+function%s+([%w_%.:]+)")
      or line:match("^%s*function%s+([%w_%.:]+)")
      or line:match("^%s*#+%s*(.-)%s*$")
    if label and label ~= "" then rows[#rows + 1] = { text = label, line = line_no } end
  end
  return rows
end

function SecondaryView:draw()
  self:draw_background(C.side)
  self.hits = {}
  renderer.draw_rect(self.position.x, self.position.y, style.divider_size, self.size.y, C.divider)
  common.draw_text(title_font, C.bright, "Outline", nil,
    self.position.x + 18 * SCALE, self.position.y, 0, HEADER_H)
  local y = self.position.y + HEADER_H
  renderer.draw_rect(self.position.x, y, self.size.x, style.divider_size, C.divider)
  y = y + 5 * SCALE
  local outline = self:get_outline()
  if #outline == 0 then
    common.draw_text(style.font, C.dim, "The active editor has no symbols.", nil,
      self.position.x + PAD, y, self.size.x - PAD * 2, ROW_H * 2)
  end
  for _, row in ipairs(outline) do
    if y + ROW_H > self.position.y + self.size.y - HEADER_H then break end
    local hit = { x = self.position.x + 4 * SCALE, y = y,
      w = self.size.x - 8 * SCALE, h = ROW_H, value = row }
    self.hits[#self.hits + 1] = hit
    if self.hovered == hit then
      draw_round_rect(hit.x + 2 * SCALE, hit.y + 1 * SCALE,
        hit.w - 4 * SCALE, hit.h - 2 * SCALE, C.hover)
    end
    common.draw_text(icon_font, C.dim, map["cod-symbol_method"] or "", nil,
      self.position.x + PAD, y, 0, ROW_H)
    common.draw_text(style.font, C.text, row.text, nil,
      self.position.x + PAD + 26 * SCALE, y, 0, ROW_H)
    y = y + ROW_H
  end
  local bottom_y = self.position.y + self.size.y - HEADER_H
  renderer.draw_rect(self.position.x, bottom_y, self.size.x, style.divider_size, C.divider)
  common.draw_text(title_font, C.bright, "Timeline", nil,
    self.position.x + 18 * SCALE, bottom_y, 0, HEADER_H)
end

function SecondaryView:on_mouse_moved(x, y, ...)
  self.hovered = nil
  for _, hit in ipairs(self.hits) do
    if inside(x, y, hit.x, hit.y, hit.w, hit.h) then self.hovered = hit; break end
  end
  return SecondaryView.super.on_mouse_moved(self, x, y, ...)
end

function SecondaryView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" then
    for _, hit in ipairs(self.hits) do
      if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
        local view = editor_view()
        if view and view.doc then
          view.doc:set_selection(hit.value.line, 1)
          view:scroll_to_line(hit.value.line, false, true)
          core.set_active_view(view)
        end
        return true
      end
    end
  end
  return SecondaryView.super.on_mouse_pressed(self, button, x, y, clicks)
end

local secondary_view = SecondaryView()
local primary_node = core.root_view:get_primary_node()
local secondary_node = primary_node:split("right", secondary_view, { x = true }, true)

local function toggle_secondary_sidebar()
  secondary_view.visible = not secondary_view.visible
  secondary_view.target_width = secondary_view.visible and secondary_view.target_size or 0
  core.redraw = true
end

-- -------------------------------------------------------------------------
-- Integrated Lite VS terminal panel.
-- -------------------------------------------------------------------------

local terminal_panel, terminal_node

local function panel_menu(x, y)
  workbench.open_menu("Terminal Actions", x, y, {
    { text = "New Terminal", action = function() command.perform "lite-vs:terminal-new" end, shortcut = "Ctrl+Shift+`" },
    { text = "Clear Terminal", action = function()
      if terminal_panel then core.set_active_view(terminal_panel); command.perform "terminal:clear" end
    end, shortcut = "Ctrl+L" },
    { separator = true },
    { text = "Kill Terminal", action = function() command.perform "lite-vs:terminal-kill" end, shortcut = "" },
    { text = "Hide Panel", action = function() command.perform "lite-vs:toggle-panel" end, shortcut = "Ctrl+J" },
  })
end

if ok_terminal and terminal_plugin.class then
  local TerminalPanel = terminal_plugin.class:extend()

  function TerminalPanel:new(options)
    TerminalPanel.super.new(self, options)
    self.open_height = ((options and options.drawer_height) or config.plugins.terminal.drawer_height or 300) * SCALE
    self.size.y = 0
    self.target_height = 0
    self.panel_visible = false
    self.panel_hits = {}
    self.panel_hover = nil
    self.panel_mode = "terminal"
    self.mode_indicator_x = nil
    self.mode_indicator_w = nil
    self.mode_indicator_target_x = nil
    self.mode_indicator_target_w = nil
  end

  function TerminalPanel:set_target_size(axis, value)
    if axis == "y" then
      local maximum = math.max(PANEL_HEADER_H, core.root_view.size.y * 0.82)
      value = common.clamp(value, 0, maximum)
      self.size.y = value
      self.target_height = value
      self.panel_visible = value > 1
      if value > PANEL_HEADER_H then self.open_height = value end
      core.redraw = true
      return true
    end
  end

  function TerminalPanel:with_content(fn, ...)
    local oy, oh = self.position.y, self.size.y
    self.position.y = oy + PANEL_HEADER_H
    self.size.y = math.max(0, oh - PANEL_HEADER_H)
    local result = { fn(self, ...) }
    self.position.y, self.size.y = oy, oh
    return table.unpack(result)
  end

  function TerminalPanel:update()
    local destination = self.panel_visible and self.open_height or 0
    self.target_height = destination
    self:move_towards(self.size, "y", destination,
      MOTION_PANEL_RATE, "lite-vs-panel")
    if self.mode_indicator_target_x then
      self:move_towards(self, "mode_indicator_x",
        self.mode_indicator_target_x, MOTION_INDICATOR_RATE,
        "lite-vs-panel-indicator")
      self:move_towards(self, "mode_indicator_w",
        self.mode_indicator_target_w, MOTION_INDICATOR_RATE,
        "lite-vs-panel-indicator")
    end
    if self.size.y <= PANEL_HEADER_H then return end
    return self:with_content(TerminalPanel.super.update)
  end

  function TerminalPanel:draw()
    if self.size.y <= 0 then return end
    renderer.draw_rect(self.position.x, self.position.y, self.size.x, self.size.y, C.editor)
    renderer.draw_rect(self.position.x, self.position.y, self.size.x, style.divider_size, C.divider)
    self.panel_hits = {}
    local labels = {
      { "problems", "PROBLEMS" }, { "output", "OUTPUT" },
      { "debug", "DEBUG CONSOLE" }, { "terminal", "TERMINAL" }
    }
    local tx = self.position.x + 18 * SCALE
    local selected_x, selected_w
    for _, spec in ipairs(labels) do
      local mode, label = spec[1], spec[2]
      local tw = style.font:get_width(label) + 24 * SCALE
      local hit = { id = mode, x = tx - 5 * SCALE, y = self.position.y,
        w = tw, h = PANEL_HEADER_H,
        action = function()
          if self.panel_mode ~= mode then self.panel_mode = mode end
          core.redraw = true
        end }
      self.panel_hits[#self.panel_hits + 1] = hit
      if self.panel_hover == hit then
        draw_round_rect(hit.x + 2 * SCALE, hit.y + 1 * SCALE,
          hit.w - 4 * SCALE, hit.h - 2 * SCALE, C.hover)
      end
      common.draw_text(style.font, self.panel_mode == mode and C.bright or C.dim,
        label, nil, tx, self.position.y, 0, PANEL_HEADER_H)
      if self.panel_mode == mode then selected_x, selected_w = tx, tw - 24 * SCALE end
      tx = tx + tw
    end
    if selected_x then
      if self.mode_indicator_x == nil then
        self.mode_indicator_x, self.mode_indicator_w = selected_x, selected_w
      end
      self.mode_indicator_target_x = selected_x
      self.mode_indicator_target_w = selected_w
      renderer.draw_rect(self.mode_indicator_x,
        self.position.y + PANEL_HEADER_H - 2 * SCALE,
        self.mode_indicator_w, 2 * SCALE, C.focus)
    end
    local specs = {
      { "new", "cod-add", function() command.perform "lite-vs:terminal-new" end },
      { "kill", "cod-trash", function() command.perform "lite-vs:terminal-kill" end },
      { "more", "cod-ellipsis", function(hit) panel_menu(hit.x - 300 * SCALE, hit.y + hit.h) end },
      { "close", "cod-close", function() command.perform "lite-vs:toggle-panel" end },
    }
    local ax = self.position.x + self.size.x - #specs * 36 * SCALE - 8 * SCALE
    for _, spec in ipairs(specs) do
      local hit = { id = spec[1], icon = spec[2], action = spec[3],
        x = ax, y = self.position.y + 5 * SCALE, w = 34 * SCALE, h = 32 * SCALE }
      self.panel_hits[#self.panel_hits + 1] = hit
      if self.panel_hover == hit then
        draw_round_rect(hit.x + 3 * SCALE, hit.y + 3 * SCALE,
          hit.w - 6 * SCALE, hit.h - 6 * SCALE, C.hover)
      end
      common.draw_text(icon_font, C.text, map[hit.icon] or "", "center", hit.x, hit.y, hit.w, hit.h)
      ax = ax + 36 * SCALE
    end
    if self.panel_mode == "terminal" then
      self:with_content(TerminalPanel.super.draw)
    else
      local x = self.position.x + 18 * SCALE
      local y = self.position.y + PANEL_HEADER_H + 8 * SCALE
      local available = self.size.x - 36 * SCALE
      local shown = 0
      for i = #core.log_items, 1, -1 do
        local item = core.log_items[i]
        local include = self.panel_mode ~= "problems" or item.level == "ERROR" or item.level == "WARN"
        if include then
          local color = item.level == "ERROR" and C.red or (item.level == "WARN" and C.yellow or C.text)
          common.draw_text(style.font, color,
            fit_text(style.font, "[" .. item.level .. "] " .. item.text, available),
            nil, x, y, 0, ROW_H)
          y, shown = y + ROW_H, shown + 1
          if y + ROW_H > self.position.y + self.size.y or shown >= 18 then break end
        end
      end
      if shown == 0 then
        local empty = self.panel_mode == "problems" and "No problems have been detected."
          or (self.panel_mode == "debug" and "No active debug session." or "No output yet.")
        common.draw_text(style.font, C.dim, empty, nil, x, y, 0, ROW_H)
      end
    end
  end

  function TerminalPanel:convert_coordinates(x, y)
    return self:with_content(TerminalPanel.super.convert_coordinates, x, y)
  end

  function TerminalPanel:on_mouse_moved(x, y, dx, dy)
    self.panel_hover = nil
    if y < self.position.y + PANEL_HEADER_H then
      for _, hit in ipairs(self.panel_hits or {}) do
        if inside(x, y, hit.x, hit.y, hit.w, hit.h) then self.panel_hover = hit; break end
      end
      core.request_cursor "arrow"
      return true
    end
    return TerminalPanel.super.on_mouse_moved(self, x, y, dx, dy)
  end

  function TerminalPanel:on_mouse_pressed(button, x, y, clicks)
    if y < self.position.y + PANEL_HEADER_H then
      if button == "left" then
        for _, hit in ipairs(self.panel_hits or {}) do
          if inside(x, y, hit.x, hit.y, hit.w, hit.h) then hit.action(hit); return true end
        end
      end
      return true
    end
    return TerminalPanel.super.on_mouse_pressed(self, button, x, y, clicks)
  end

  function TerminalPanel:on_mouse_released(button, x, y, ...)
    -- RootView broadcasts releases to every leaf.  A hidden integrated panel
    -- has no native terminal yet, while the upstream view assumes it does.
    if not self.terminal or self.size.y <= PANEL_HEADER_H then return end
    return TerminalPanel.super.on_mouse_released(self, button, x, y, ...)
  end

  function TerminalPanel:restart()
    if self.terminal then self.terminal:close() end
    self.terminal = nil
    self.routine = nil
    self.deferred_input = nil
    self.modified_since_last_focus = false
    self.last_size = { x = -1, y = -1 }
    core.redraw = true
  end

  function TerminalPanel:close()
    self:restart()
    self.panel_visible = false
    self.target_height = 0
    core.terminal_view_closed = self.open_height
    restore_editor_focus()
  end

  terminal_panel = TerminalPanel(config.plugins.terminal)
  primary_node = core.root_view:get_primary_node()
  terminal_node = primary_node:split("down", terminal_panel, { y = true }, true)
  core.terminal_view = terminal_panel
  core.terminal_view_node = terminal_node
  core.terminal_view_closed = terminal_panel.open_height
end

local function panel_open()
  return terminal_panel and terminal_panel.panel_visible
end

local function toggle_panel(force_open)
  if not terminal_panel or not terminal_node then return end
  local open = force_open == nil and not panel_open() or force_open
  terminal_panel.panel_visible = open
  terminal_panel.target_height = open and terminal_panel.open_height or 0
  core.terminal_view_closed = open and nil or terminal_panel.open_height
  core.redraw = true
  if open then core.set_active_view(terminal_panel) else restore_editor_focus() end
end

-- -------------------------------------------------------------------------
-- Editor toolbar actions and command routing.
-- -------------------------------------------------------------------------

local node_draw = Node.draw
function Node:draw(...)
  node_draw(self, ...)
  self.lite_vs_editor_hits = nil
  if self.type == "leaf" and not self.locked and self:should_show_tabs()
    and self.active_view and self.active_view:is(DocView) then
    local y = self.position.y + 48 * SCALE
    local hits = {
      { id = "split", x = self.position.x + self.size.x - 92 * SCALE, y = y,
        w = 40 * SCALE, h = 36 * SCALE },
      { id = "more", x = self.position.x + self.size.x - 48 * SCALE, y = y,
        w = 40 * SCALE, h = 36 * SCALE },
    }
    self.lite_vs_editor_hits = hits
    for _, hit in ipairs(hits) do
      if self.hovered and inside(self.hovered.x, self.hovered.y, hit.x, hit.y, hit.w, hit.h) then
        draw_round_rect(hit.x + 3 * SCALE, hit.y + 3 * SCALE,
          hit.w - 6 * SCALE, hit.h - 6 * SCALE, C.hover)
        local icon = hit.id == "split" and "cod-split_horizontal" or "cod-ellipsis"
        common.draw_text(icon_font, C.bright, map[icon] or "", "center",
          hit.x, hit.y, hit.w, hit.h)
      end
    end
  end
end

local root_mouse_pressed = RootView.on_mouse_pressed
function RootView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" then
    local active_sidebar = sidebar_node.active_view
    if sidebar_visible(active_sidebar) then
      local divider_x = active_sidebar.position.x + active_sidebar.size.x
      if math.abs(x - divider_x) <= 8 * SCALE then
        self.lite_vs_sidebar_drag = { kind = "primary", view = active_sidebar }
        core.request_cursor "sizeh"
        return true
      end
    end
    if secondary_view.visible and math.abs(x - secondary_view.position.x) <= 8 * SCALE then
      self.lite_vs_sidebar_drag = { kind = "secondary", view = secondary_view }
      core.request_cursor "sizeh"
      return true
    end
  end
  if not workbench.menu_state.open and core.active_view ~= core.command_view then
    local node = self.root_node:get_child_overlapping_point(x, y)
    for _, hit in ipairs((node and node.lite_vs_editor_hits) or {}) do
      if inside(x, y, hit.x, hit.y, hit.w, hit.h) then
        if button == "left" then
          node:set_active_view(node.active_view)
          if hit.id == "split" then
            command.perform "root:split-right"
          else
            workbench.open_menu("Editor", hit.x - 330 * SCALE, hit.y + hit.h, {
              { text = "Save", command = "doc:save", shortcut = "Ctrl+S" },
              { separator = true },
              { text = "Split Editor Right", command = "root:split-right", shortcut = "Ctrl+\\" },
              { text = "Split Editor Down", command = "root:split-down", shortcut = "" },
              { separator = true },
              { text = "Close Editor", command = "root:close", shortcut = "Ctrl+W" },
              { text = "Close Other Editors", command = "root:close-all-others", shortcut = "" },
              { text = "Close All Editors", command = "root:close-all", shortcut = "" },
            })
          end
        end
        return true
      end
    end
  end
  return root_mouse_pressed(self, button, x, y, clicks)
end

local root_mouse_moved = RootView.on_mouse_moved
function RootView:on_mouse_moved(x, y, dx, dy)
  local drag = self.lite_vs_sidebar_drag
  if drag then
    if drag.kind == "primary" then
      apply_sidebar_size(x - drag.view.position.x)
    else
      drag.view:set_target_size("x", self.size.x - x)
    end
    core.request_cursor "sizeh"
    return true
  end
  local active_sidebar = sidebar_node.active_view
  local on_primary = sidebar_visible(active_sidebar)
    and math.abs(x - (active_sidebar.position.x + active_sidebar.size.x)) <= 8 * SCALE
  local on_secondary = secondary_view.visible
    and math.abs(x - secondary_view.position.x) <= 8 * SCALE
  if on_primary or on_secondary then
    core.request_cursor "sizeh"
    return true
  end
  return root_mouse_moved(self, x, y, dx, dy)
end

local root_mouse_released = RootView.on_mouse_released
function RootView:on_mouse_released(button, x, y, ...)
  if self.lite_vs_sidebar_drag then
    self.lite_vs_sidebar_drag = nil
    core.request_cursor "arrow"
    return true
  end
  return root_mouse_released(self, button, x, y, ...)
end

command.add(nil, {
  ["lite-vs:show-explorer"] = function() show_sidebar("explorer") end,
  ["lite-vs:show-search"] = function() show_sidebar("search") end,
  ["lite-vs:show-source-control"] = function() show_sidebar("source") end,
  ["lite-vs:show-run"] = function() show_sidebar("run") end,
  ["lite-vs:show-extensions"] = function() show_sidebar("extensions") end,
  ["lite-vs:toggle-primary-sidebar"] = toggle_primary_sidebar,
  ["lite-vs:toggle-secondary-sidebar"] = toggle_secondary_sidebar,
  ["lite-vs:toggle-panel"] = function() toggle_panel() end,
  ["lite-vs:terminal-panel"] = function()
    if terminal_panel then terminal_panel.panel_mode = "terminal" end
    toggle_panel(true)
  end,
  ["lite-vs:terminal-new"] = function()
    if terminal_panel then terminal_panel.panel_mode = "terminal"; terminal_panel:restart(); toggle_panel(true) end
  end,
  ["lite-vs:terminal-kill"] = function()
    if terminal_panel then terminal_panel:close() end
  end,
  ["lite-vs:toggle-window-maximized"] = function()
    system.set_window_mode(core.window_mode == "maximized" and "normal" or "maximized")
  end,
})

if terminal_panel then
  command.add(nil, {
    ["terminal:toggle-drawer"] = function() toggle_panel() end,
    ["terminal:swap-drawer"] = function()
      if panel_open() and core.active_view == terminal_panel then restore_editor_focus()
      else toggle_panel(true) end
    end,
    ["terminal:open-tab"] = function()
      terminal_panel.panel_mode = "terminal"; terminal_panel:restart(); toggle_panel(true)
    end,
    ["terminal:focus"] = function() terminal_panel.panel_mode = "terminal"; toggle_panel(true) end,
    ["terminal:execute"] = function(text)
      local submit = function(value)
        terminal_panel.panel_mode = "terminal"
        toggle_panel(true)
        terminal_panel:input(value .. terminal_panel.options.newline)
      end
      if text then submit(text) else core.command_view:enter("Execute Command", { submit = submit }) end
    end,
  })
end

command.add(function()
  local view = core.active_view
  return view and view.lite_vs_sidebar and view.focused_field, view
end, {
  ["lite-vs-sidebar:backspace"] = function(view) view:backspace() end,
  ["lite-vs-sidebar:delete"] = function(view) view:delete_field(false, false) end,
  ["lite-vs-sidebar:delete-word-left"] = function(view) view:delete_field(true, true) end,
  ["lite-vs-sidebar:delete-word-right"] = function(view) view:delete_field(false, true) end,
  ["lite-vs-sidebar:left"] = function(view) view:move_field_caret(-1, false, false) end,
  ["lite-vs-sidebar:right"] = function(view) view:move_field_caret(1, false, false) end,
  ["lite-vs-sidebar:select-left"] = function(view) view:move_field_caret(-1, true, false) end,
  ["lite-vs-sidebar:select-right"] = function(view) view:move_field_caret(1, true, false) end,
  ["lite-vs-sidebar:word-left"] = function(view) view:move_field_caret(-1, false, true) end,
  ["lite-vs-sidebar:word-right"] = function(view) view:move_field_caret(1, false, true) end,
  ["lite-vs-sidebar:select-word-left"] = function(view) view:move_field_caret(-1, true, true) end,
  ["lite-vs-sidebar:select-word-right"] = function(view) view:move_field_caret(1, true, true) end,
  ["lite-vs-sidebar:home"] = function(view) view:set_field_caret(0, false) end,
  ["lite-vs-sidebar:end"] = function(view)
    view:set_field_caret(text_length(view.fields[view.focused_field] or ""), false)
  end,
  ["lite-vs-sidebar:select-home"] = function(view) view:set_field_caret(0, true) end,
  ["lite-vs-sidebar:select-end"] = function(view)
    view:set_field_caret(text_length(view.fields[view.focused_field] or ""), true)
  end,
  ["lite-vs-sidebar:copy"] = function(view) view:copy_field(false) end,
  ["lite-vs-sidebar:cut"] = function(view) view:copy_field(true) end,
  ["lite-vs-sidebar:paste"] = function(view) view:paste_field() end,
  ["lite-vs-sidebar:select-all"] = function(view) view:select_all_field() end,
  ["lite-vs-sidebar:undo"] = function(view) view:undo_field(false) end,
  ["lite-vs-sidebar:redo"] = function(view) view:undo_field(true) end,
  ["lite-vs-sidebar:submit"] = function(view) view:submit() end,
  ["lite-vs-sidebar:escape"] = function(view)
    view.focused_field, view.dragging_field, view.dragging_field_hit = nil, nil, nil
    restore_editor_focus()
  end,
})

local activity = core.lite_vs_activity_view
if activity then
  function activity:on_mouse_pressed(button, x, y)
    if button ~= "left" then return end
    self:build_items()
    for _, item in ipairs(self.items) do
      if inside(x, y, item.x, item.y, item.w, item.h) then
        if item.id == "files" then show_sidebar("explorer", true)
        elseif item.id == "search" then show_sidebar("search", true)
        elseif item.id == "source" then show_sidebar("source", true)
        elseif item.id == "run" then show_sidebar("run", true)
        elseif item.id == "extensions" then show_sidebar("extensions", true)
        elseif item.id == "account" then
          workbench.open_menu("Account", self.position.x + self.size.x,
            self.position.y + self.size.y - 190 * SCALE, {
              { text = "Extensions and Accounts", command = "lite-vs:show-extensions", shortcut = "" },
              { text = "Settings", command = "ui:settings", shortcut = "" },
            })
        elseif item.id == "settings" then
          workbench.open_menu("Manage", self.position.x + self.size.x,
            self.position.y + self.size.y - 260 * SCALE, {
              { text = "Settings", command = "ui:settings", shortcut = "Ctrl+Alt+P" },
              { text = "Command Palette...", command = "core:find-command", shortcut = "Ctrl+Shift+P" },
              { text = "Extensions", command = "lite-vs:show-extensions", shortcut = "Ctrl+Shift+X" },
              { separator = true },
              { text = "Open User Configuration", command = "core:open-user-module", shortcut = "" },
              { text = "Restart Lite XL", command = "core:restart", shortcut = "Ctrl+Alt+R" },
            })
        end
        return true
      end
    end
  end
end

local title_draw = TitleView.draw
function TitleView:draw(...)
  title_draw(self, ...)
  for _, hit in ipairs(self.lite_vs_hit_items or {}) do
    if hit.id == "primary-sidebar" then hit.action = toggle_primary_sidebar
    elseif hit.id == "panel" then hit.action = function() toggle_panel() end
    elseif hit.id == "secondary-sidebar" then hit.action = toggle_secondary_sidebar end
  end
end

local function remap_menu(menu_name, text, target)
  for _, entry in ipairs(workbench.menus[menu_name] or {}) do
    if entry.text == text then entry.command = target end
  end
end

remap_menu("Edit", "Find in Files", "lite-vs:show-search")
remap_menu("View", "Search", "lite-vs:show-search")
remap_menu("View", "Source Control", "lite-vs:show-source-control")
remap_menu("View", "Run and Debug", "lite-vs:show-run")
remap_menu("View", "Extensions", "lite-vs:show-extensions")
remap_menu("View", "Toggle Primary Side Bar", "lite-vs:toggle-primary-sidebar")
remap_menu("View", "Toggle Panel", "lite-vs:toggle-panel")
remap_menu("Run", "Open Terminal", "lite-vs:terminal-new")
remap_menu("Run", "Toggle Terminal Panel", "lite-vs:toggle-panel")
remap_menu("Terminal", "New Terminal", "lite-vs:terminal-new")
remap_menu("Terminal", "Toggle Terminal", "lite-vs:toggle-panel")

keymap.add({
  ["backspace"] = "lite-vs-sidebar:backspace",
  ["delete"] = "lite-vs-sidebar:delete",
  ["ctrl+backspace"] = "lite-vs-sidebar:delete-word-left",
  ["ctrl+delete"] = "lite-vs-sidebar:delete-word-right",
  ["left"] = "lite-vs-sidebar:left",
  ["right"] = "lite-vs-sidebar:right",
  ["shift+left"] = "lite-vs-sidebar:select-left",
  ["shift+right"] = "lite-vs-sidebar:select-right",
  ["ctrl+left"] = "lite-vs-sidebar:word-left",
  ["ctrl+right"] = "lite-vs-sidebar:word-right",
  ["ctrl+shift+left"] = "lite-vs-sidebar:select-word-left",
  ["ctrl+shift+right"] = "lite-vs-sidebar:select-word-right",
  ["home"] = "lite-vs-sidebar:home",
  ["end"] = "lite-vs-sidebar:end",
  ["shift+home"] = "lite-vs-sidebar:select-home",
  ["shift+end"] = "lite-vs-sidebar:select-end",
  ["ctrl+c"] = "lite-vs-sidebar:copy",
  ["ctrl+x"] = "lite-vs-sidebar:cut",
  ["ctrl+v"] = "lite-vs-sidebar:paste",
  ["ctrl+a"] = "lite-vs-sidebar:select-all",
  ["ctrl+z"] = "lite-vs-sidebar:undo",
  ["ctrl+y"] = "lite-vs-sidebar:redo",
  ["ctrl+shift+z"] = "lite-vs-sidebar:redo",
  ["return"] = "lite-vs-sidebar:submit",
  ["ctrl+return"] = "lite-vs-sidebar:submit",
  ["escape"] = "lite-vs-sidebar:escape",
})

keymap.add_direct({
  ["ctrl+b"] = "lite-vs:toggle-primary-sidebar",
  ["ctrl+j"] = "lite-vs:toggle-panel",
  ["ctrl+shift+e"] = "lite-vs:show-explorer",
  ["ctrl+shift+f"] = "lite-vs:show-search",
  ["ctrl+shift+g"] = "lite-vs:show-source-control",
  ["ctrl+shift+d"] = "lite-vs:show-run",
  ["ctrl+shift+x"] = "lite-vs:show-extensions",
  ["ctrl+shift+`"] = "lite-vs:terminal-new",
  ["ctrl+alt+b"] = "lite-vs:toggle-secondary-sidebar",
  ["ctrl+alt+m"] = "lite-vs:toggle-window-maximized",
})

if PLATFORM == "Mac OS X" then
  keymap.add({
    ["cmd+backspace"] = "lite-vs-sidebar:delete-word-left",
    ["cmd+delete"] = "lite-vs-sidebar:delete-word-right",
    ["option+left"] = "lite-vs-sidebar:word-left",
    ["option+right"] = "lite-vs-sidebar:word-right",
    ["option+shift+left"] = "lite-vs-sidebar:select-word-left",
    ["option+shift+right"] = "lite-vs-sidebar:select-word-right",
    ["cmd+c"] = "lite-vs-sidebar:copy",
    ["cmd+x"] = "lite-vs-sidebar:cut",
    ["cmd+v"] = "lite-vs-sidebar:paste",
    ["cmd+a"] = "lite-vs-sidebar:select-all",
    ["cmd+z"] = "lite-vs-sidebar:undo",
    ["cmd+shift+z"] = "lite-vs-sidebar:redo",
    ["cmd+return"] = "lite-vs-sidebar:submit",
  })
  keymap.add_direct({
    ["cmd+b"] = "lite-vs:toggle-primary-sidebar",
    ["cmd+j"] = "lite-vs:toggle-panel",
    ["cmd+shift+e"] = "lite-vs:show-explorer",
    ["cmd+shift+f"] = "lite-vs:show-search",
    ["cmd+shift+g"] = "lite-vs:show-source-control",
    ["cmd+shift+d"] = "lite-vs:show-run",
    ["cmd+shift+x"] = "lite-vs:show-extensions",
    ["cmd+shift+`"] = "lite-vs:terminal-new",
    ["cmd+option+b"] = "lite-vs:toggle-secondary-sidebar",
    ["cmd+option+m"] = "lite-vs:toggle-window-maximized",
  })
end

core.redraw = true

return {
  sidebars = sidebar_views,
  secondary = secondary_view,
  terminal = terminal_panel,
}

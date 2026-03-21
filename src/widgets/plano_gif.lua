local awful = require("awful")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local gears = require("gears")
local gfs = require("gears.filesystem")
local wibox = require("wibox")

local M = {}

local gif_path = gfs.get_configuration_dir() .. "src/assets/logo.gif"
local frames_dir = "/tmp/awesome_plano_gif_frames/"

local gif_surfaces = {}
local loading = false
local loaded = false
local waiting_widgets = {}
local load_timer = nil

local DEFAULT_RADIUS = dpi(14)
local DEFAULT_FALLBACK_BG = "#111111"

local function notify_waiters()
  for _, widget in ipairs(waiting_widgets) do
    widget:emit_signal("widget::redraw_needed")
  end
  waiting_widgets = {}
end

local function load_surfaces_async(paths)
  local index = 1

  if load_timer then
    load_timer:stop()
    load_timer = nil
  end

  load_timer = gears.timer {
    timeout = 0.001,
    autostart = true,
    call_now = false,
    callback = function()
      if index <= #paths then
        local surf = gears.surface.load_uncached(paths[index])
        if surf then
          gif_surfaces[#gif_surfaces + 1] = surf
        end
        index = index + 1
      else
        load_timer:stop()
        load_timer = nil
        loading = false
        loaded = #gif_surfaces > 0
        notify_waiters()
      end
    end
  }
end

local function load_gif_frames(target_size)
  if loading or loaded then
    return
  end

  loading = true

  local check_cmd = string.format("ls %s*.png 2>/dev/null | wc -l", frames_dir)

  awful.spawn.easy_async_with_shell(check_cmd, function(stdout)
    local cached = tonumber(stdout:match("%d+")) or 0

    if cached > 0 then
      local paths = {}
      for i = 0, cached - 1 do
        paths[i + 1] = string.format("%sframe_%04d.png", frames_dir, i)
      end
      load_surfaces_async(paths)
    else
      local size = tonumber(target_size) or dpi(400)

      local extract_cmd = string.format(
        "mkdir -p %s && convert -coalesce -resize %dx%d^ %q %sframe_%%04d.png 2>/dev/null; ls %s*.png 2>/dev/null | wc -l",
        frames_dir, size, size, gif_path, frames_dir, frames_dir
      )

      awful.spawn.easy_async_with_shell(extract_cmd, function(out)
        local count = tonumber(out:match("%d+")) or 0

        if count > 0 then
          local paths = {}
          for i = 0, count - 1 do
            paths[i + 1] = string.format("%sframe_%04d.png", frames_dir, i)
          end
          load_surfaces_async(paths)
        else
          local surf = gears.surface.load_uncached(gif_path)
          if surf then
            gif_surfaces = { surf }
            loaded = true
          end
          loading = false
          notify_waiters()
        end
      end)
    end
  end)
end

function M.preload(target_size)
  load_gif_frames(target_size)
end

function M.new(args)
  args = args or {}

  local radius = args.radius or DEFAULT_RADIUS
  local fallback_bg = args.fallback_bg or DEFAULT_FALLBACK_BG
  local anim_interval = args.anim_interval or 0.06

  local current_surface = nil
  local current_frame = 1
  local frame_timer = nil

  local widget = wibox.widget.base.make_widget()

  local function start_animation()
    if frame_timer or #gif_surfaces == 0 then
      return
    end

    frame_timer = gears.timer {
      timeout = anim_interval,
      autostart = true,
      call_now = true,
      callback = function()
        if #gif_surfaces == 0 then
          return
        end

        current_surface = gif_surfaces[current_frame]
        current_frame = (current_frame % #gif_surfaces) + 1
        widget:emit_signal("widget::redraw_needed")
      end
    }

    widget._gif_timer = frame_timer
  end

  function widget:fit(_, width, height)
    return width, height
  end

  function widget:draw(_, cr, width, height)
    gears.shape.rounded_rect(cr, width, height, radius)
    cr:clip()

    if current_surface then
      local iw = current_surface:get_width()
      local ih = current_surface:get_height()

      local scale = math.max(width / iw, height / ih)
      local ox = (width - iw * scale) / 2
      local oy = (height - ih * scale) / 2

      cr:save()
      cr:translate(ox, oy)
      cr:scale(scale, scale)
      cr:set_source_surface(current_surface, 0, 0)
      cr:paint()
      cr:restore()
    else
      local r, g, b, a = gears.color.parse_color(fallback_bg)
      cr:set_source_rgba(r, g, b, a)
      cr:paint()
    end
  end

  if loaded and #gif_surfaces > 0 then
    current_surface = gif_surfaces[1]
    start_animation()
  else
    table.insert(waiting_widgets, widget)
    load_gif_frames(args.preload_size or dpi(400))

    local wait_timer
    wait_timer = gears.timer {
      timeout = 0.05,
      autostart = true,
      call_now = false,
      callback = function()
        if loaded and #gif_surfaces > 0 then
          current_surface = gif_surfaces[1]
          start_animation()
          widget:emit_signal("widget::redraw_needed")
          wait_timer:stop()
        elseif not loading then
          wait_timer:stop()
        end
      end
    }

    widget._wait_timer = wait_timer
  end

  return widget
end

return M

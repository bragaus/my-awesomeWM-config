local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local gears = require("gears")
local wibox = require("wibox")

local function hex_to_rgba(hex, alpha_override)
  hex = hex:gsub("#", "")
  if #hex == 6 then
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b, alpha_override or 1
  elseif #hex == 8 then
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    local a = tonumber(hex:sub(7, 8), 16) / 255
    return r, g, b, alpha_override or a
  end
  return 1, 1, 1, alpha_override or 1
end

local function clamp(v, minv, maxv)
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  return line
end

local function read_all(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function detect_default_iface()
  local p = io.popen([[sh -c "ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'"]])
  if not p then return nil end
  local iface = p:read("*l")
  p:close()

  if iface and iface ~= "" then
    return iface
  end

  local p2 = io.popen([[sh -c "ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1"]])
  if not p2 then return nil end
  local fallback = p2:read("*l")
  p2:close()
  return fallback
end

return function(args)
  args = args or {}

  local width = args.width or dpi(320)
  local height = args.height or dpi(96)
  local interval = args.interval or 1
  local samples = args.samples or 42
  local radius = args.radius or dpi(10)

  local palette = args.palette or {
    cpu = "#00F6FF", -- cyan neon
    mem = "#FF00F5", -- magenta neon
    gpu = "#8BFF00", -- acid green
    net = "#FF9F1C", -- orange neon
    grid = "#5A2A82",
    text = "#E8D9FF",
    overlay = "#0B0714"
  }

  local widget = wibox.widget.base.make_widget()

  widget._preserve_colors = true
  widget._preferred_segment_width = width
  widget._preferred_segment_height = height

  local history = {
    cpu = {},
    mem = {},
    gpu = {},
    net = {}
  }

  for i = 1, samples do
    history.cpu[i] = 0
    history.mem[i] = 0
    history.gpu[i] = 0
    history.net[i] = 0
  end

  local last = {
    cpu = 0,
    mem = 0,
    gpu = 0,
    net = 0
  }

  local prev_total = nil
  local prev_idle = nil

  local iface = detect_default_iface()
  local prev_rx = nil
  local prev_tx = nil
  local dynamic_net_peak = 128 * 1024 -- 128 KB/s base
  local gpu_mode = nil

  local function push(tbl, value)
    table.remove(tbl, 1)
    table.insert(tbl, clamp(value, 0, 100))
  end

  local function sample_cpu()
    local line = read_first_line("/proc/stat")
    if not line then return 0 end

    local user, nice, system, idle, iowait, irq, softirq, steal =
      line:match("^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%d*)%s*(%d*)%s*(%d*)%s*(%d*)")

    user = tonumber(user) or 0
    nice = tonumber(nice) or 0
    system = tonumber(system) or 0
    idle = tonumber(idle) or 0
    iowait = tonumber(iowait) or 0
    irq = tonumber(irq) or 0
    softirq = tonumber(softirq) or 0
    steal = tonumber(steal) or 0

    local idle_all = idle + iowait
    local non_idle = user + nice + system + irq + softirq + steal
    local total = idle_all + non_idle

    if not prev_total then
      prev_total = total
      prev_idle = idle_all
      return 0
    end

    local totald = total - prev_total
    local idled = idle_all - prev_idle

    prev_total = total
    prev_idle = idle_all

    if totald <= 0 then
      return 0
    end

    return ((totald - idled) / totald) * 100
  end

  local function sample_mem()
    local content = read_all("/proc/meminfo")
    if not content then return 0 end

    local total = tonumber(content:match("MemTotal:%s+(%d+)"))
    local available = tonumber(content:match("MemAvailable:%s+(%d+)"))

    if not total or not available or total == 0 then
      return 0
    end

    local used = total - available
    return (used / total) * 100
  end

  local function detect_gpu_mode_once()
    if gpu_mode ~= nil then
      return gpu_mode
    end

    local amd_busy = read_first_line("/sys/class/drm/card0/device/gpu_busy_percent")
    if amd_busy then
      gpu_mode = "sysfs"
      return gpu_mode
    end

    local p = io.popen([[sh -c "command -v nvidia-smi >/dev/null 2>&1 && echo yes || echo no"]])
    if p then
      local result = p:read("*l")
      p:close()
      if result == "yes" then
        gpu_mode = "nvidia"
        return gpu_mode
      end
    end

    gpu_mode = "none"
    return gpu_mode
  end

  local function sample_gpu()
    local mode = detect_gpu_mode_once()

    if mode == "sysfs" then
      local v = tonumber(read_first_line("/sys/class/drm/card0/device/gpu_busy_percent")) or 0
      return v
    elseif mode == "nvidia" then
      local p = io.popen([[sh -c "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1"]])
      if not p then return 0 end
      local out = p:read("*l")
      p:close()
      return tonumber(out) or 0
    end

    return 0
  end

  local function sample_net()
    if not iface or iface == "" then
      iface = detect_default_iface()
      if not iface or iface == "" then
        return 0
      end
    end

    local rx = tonumber(read_first_line("/sys/class/net/" .. iface .. "/statistics/rx_bytes")) or 0
    local tx = tonumber(read_first_line("/sys/class/net/" .. iface .. "/statistics/tx_bytes")) or 0

    if not prev_rx or not prev_tx then
      prev_rx = rx
      prev_tx = tx
      return 0
    end

    local drx = math.max(0, rx - prev_rx)
    local dtx = math.max(0, tx - prev_tx)
    prev_rx = rx
    prev_tx = tx

    local rate = (drx + dtx) / interval
    dynamic_net_peak = math.max(rate, dynamic_net_peak * 0.92, 128 * 1024)

    return (rate / dynamic_net_peak) * 100
  end

  local function draw_series(cr, values, x, y, w, h, color_hex)
    local r, g, b = hex_to_rgba(color_hex)

    local n = #values
    if n < 2 then return end

    local step = w / math.max(n - 1, 1)

    -- glow
    cr:set_source_rgba(r, g, b, 0.14)
    cr:set_line_width(dpi(6))
    for i, value in ipairs(values) do
      local px = x + (i - 1) * step
      local py = y + h * (1 - (value / 100))
      if i == 1 then
        cr:move_to(px, py)
      else
        cr:line_to(px, py)
      end
    end
    cr:stroke()

    -- main line
    cr:set_source_rgba(r, g, b, 0.95)
    cr:set_line_width(dpi(2))
    for i, value in ipairs(values) do
      local px = x + (i - 1) * step
      local py = y + h * (1 - (value / 100))
      if i == 1 then
        cr:move_to(px, py)
      else
        cr:line_to(px, py)
      end
    end
    cr:stroke()

    -- last point
    local last_value = values[n]
    local lx = x + (n - 1) * step
    local ly = y + h * (1 - (last_value / 100))

    cr:arc(lx, ly, dpi(2.3), 0, 2 * math.pi)
    cr:set_source_rgba(r, g, b, 1)
    cr:fill()
  end

  local function draw_label(cr, x, y, name, value, color_hex)
    local r, g, b = hex_to_rgba(color_hex)

    cr:set_source_rgba(r, g, b, 1)
    cr:set_line_width(dpi(3))
    cr:move_to(x, y)
    cr:line_to(x + dpi(10), y)
    cr:stroke()

    cr:set_source_rgba(hex_to_rgba(palette.text))
    cr:select_font_face("JetBrainsMono Nerd Font", 0, 0)
    cr:set_font_size(dpi(10))
    cr:move_to(x + dpi(14), y + dpi(3))
    cr:show_text(string.format("%s %02d%%", name, math.floor(value + 0.5)))
  end

  function widget:fit(_, _, _)
    return width, height
  end

  function widget:draw(_, cr, w, h)
    local pad_left = dpi(10)
    local pad_right = dpi(10)
    local pad_top = dpi(22)
    local pad_bottom = dpi(10)

    local plot_x = pad_left
    local plot_y = pad_top
    local plot_w = w - pad_left - pad_right
    local plot_h = h - pad_top - pad_bottom

    -- subtle inner overlay
    gears.shape.rounded_rect(cr, w, h, radius)
    cr:set_source_rgba(0.02, 0.02, 0.06, 0.18)
    cr:fill()

    -- grid
    local gr, gg, gb = hex_to_rgba(palette.grid)
    cr:set_source_rgba(gr, gg, gb, 0.45)
    cr:set_line_width(1)

    for i = 0, 4 do
      local gy = plot_y + (plot_h / 4) * i
      cr:move_to(plot_x, gy)
      cr:line_to(plot_x + plot_w, gy)
      cr:stroke()
    end

    -- labels
    draw_label(cr, dpi(8), dpi(12), "CPU", last.cpu, palette.cpu)
    draw_label(cr, dpi(82), dpi(12), "MEM", last.mem, palette.mem)
    draw_label(cr, dpi(156), dpi(12), "GPU", last.gpu, palette.gpu)
    draw_label(cr, dpi(230), dpi(12), "NET", last.net, palette.net)

    -- series
    draw_series(cr, history.cpu, plot_x, plot_y, plot_w, plot_h, palette.cpu)
    draw_series(cr, history.mem, plot_x, plot_y, plot_w, plot_h, palette.mem)
    draw_series(cr, history.gpu, plot_x, plot_y, plot_w, plot_h, palette.gpu)
    draw_series(cr, history.net, plot_x, plot_y, plot_w, plot_h, palette.net)
  end

  widget._timer = gears.timer {
    timeout = interval,
    autostart = true,
    call_now = true,
    callback = function()
      last.cpu = clamp(sample_cpu(), 0, 100)
      last.mem = clamp(sample_mem(), 0, 100)
      last.gpu = clamp(sample_gpu(), 0, 100)
      last.net = clamp(sample_net(), 0, 100)

      push(history.cpu, last.cpu)
      push(history.mem, last.mem)
      push(history.gpu, last.gpu)
      push(history.net, last.net)

      widget:emit_signal("widget::redraw_needed")
    end
  }

  return widget
end

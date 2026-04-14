
-- tema/cores default
local beautiful = require("beautiful")

-- converte valores para pixels com suporte a DPI
local dpi = beautiful.xresources.apply_dpi

-- funcoes utilitarias (arquivos, superficie, timers)
local gears = require("gears")

-- acesso ao sistema de arquivos.
local gfs = require("gears.filesystem")

-- construcao de widget
local wibox = require("wibox")

-- converte cor hexadecimal (6 ou 8 digitos) para componentes RGBA (0.1)
local function hex_to_rgba(hex, alpha_override)
  hex = (hex or "#ffffff"):gsub("#", "")

  if #hex == 6 then
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b, alpha_override or 1
  end

  if #hex == 8 then
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    local a = tonumber(hex:sub(7, 8), 16) / 255
    return r, g, b, alpha_override or a
  end

  return 1, 1, 1, alpha_override or 1
end

-- clamp restringe o valor minimo ou maximo
local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end

  if value > maximum then
    return maximum
  end

  return value
end

-- remove espaços extras e normaliza.
local function trim(value)
  local normalized = tostring(value or "")
  normalized = normalized:gsub("%s+", " ")
  normalized = normalized:gsub("^%s+", "")
  normalized = normalized:gsub("%s+$", "")
  return normalized
end

-- encurta string com "..."
local function shorten(value, max_len)
  value = trim(value)
  if #value <= max_len then
    return value
  end

  return value:sub(1, max_len - 3) .. "..."
end

-- Leitura de arquivos
local function read_first_line(path)

  -- abrir o arquivo em modo de leitura
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  -- leitura de uma linha inteira, sem incluir o \n
  local line = file:read("*l")
  file:close()
  return line
end

-- igual a funcao de cima so que agora ele vai ler o arquivo inteiro
local function read_all(path)

  -- abre o arquivo em modo leitura 
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  -- vai ler o arquivo inteiro de um vez, incluindo quebras de linhas espacos e etc
  local content = file:read("*a")
  file:close()
  return content
end

-- rodar comandos do terminal
local function run_command(command)
  local process = io.popen(command) -- abre um processo que executa comandos no shell
  if not process then -- verifica se a variavel esta vazia
    return nil
  end

  local output = process:read("*a") -- lê toda (*a) a saída do processo como string
  process:close()
  return output
end

local function detect_default_iface()
  local iface = "wlo1" --trim(run_command([[sh -c "ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'"]]))
  --if iface ~= "" then
    return iface
  --end

  --return trim(run_command([[sh -c "ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1"]]))
end

local function detect_battery_path()
  local path = "/sys/class/power_supply/BAT0" --trim(run_command([[sh -c "ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1"]]))
  --if path == "" then
   -- return nil
  --end

  return path
end

-- adiciona transparencia a cor
local function with_alpha(hex, alpha)
  return gears.color(string.format("%s%02x", hex, math.floor(alpha * 255 + 0.5)))
end

-- mesma logica do with_alpha mas retorna uma strign hex em vez de gears
local function hex_with_alpha_string(hex, alpha)
  return string.format("%s%02x", hex, math.floor(alpha * 255 + 0.5))
end

-- verifica se um arquivo existe no caminho informado
local function file_exists(path)
  local file = io.open(path, "rb") -- abre o arquivo em modo binario de leitura
  if not file then
    return false
  end

  file:close()
  return true
end

-- itera sobre cada path na lista paths
local function first_existing_path(paths)
  for _, path in ipairs(paths or {}) do
    if file_exists(path) then
      return path
    end
  end

  return nil
end

-- coleta todos os caminhos existentes em uma lista 
local function collect_existing_paths(paths)
  local collected = {}

  for _, path in ipairs(paths or {}) do
    if file_exists(path) then
      table.insert(collected, path)
    end
  end

  return collected
end

-- carrega uma imagem de forma segura
local function load_surface_safe(path)
  if not path then
    return nil
  end

  local ok, surface = pcall(gears.surface.load_uncached, path)
  if ok then
    return surface
  end

  return nil
end

-- desenhar o plano de fundo
local function draw_surface_cover(cr, surface, width, height, alpha)
  if not surface then
    return
  end

  local image_width = surface:get_width()
  local image_height = surface:get_height()

  -- se n tiver imagem carregada
  if image_width <= 0 or image_height <= 0 then
    return
  end

  local scale = math.max(width / image_width, height / image_height)
  local offset_x = (width - image_width * scale) / 2
  local offset_y = (height - image_height * scale) / 2

  cr:save()
  cr:translate(offset_x, offset_y)
  cr:scale(scale, scale)
  cr:set_source_surface(surface, 0, 0)

  if alpha and alpha < 1 then
    cr:paint_with_alpha(alpha)
  else
    cr:paint()
  end

  cr:restore()
end

local function format_bytes_per_sec(value)
  local units = { "B/S", "KIB/S", "MIB/S", "GIB/S" }
  local scaled = tonumber(value) or 0
  local unit_index = 1

  while scaled >= 1024 and unit_index < #units do
    scaled = scaled / 1024
    unit_index = unit_index + 1
  end

  if unit_index == 1 then
    return string.format("%d %s", math.floor(scaled + 0.5), units[unit_index])
  end

  return string.format("%.1f %s", scaled, units[unit_index])
end

local function slanted_rect(cr, width, height, slant)
  slant = math.min(slant or dpi(14), width * 0.22)
  cr:move_to(slant, 0)
  cr:line_to(width, 0)
  cr:line_to(width - slant, height)
  cr:line_to(0, height)
  cr:close_path()
end

return function(args)
  args = args or {}

  local width = args.width or dpi(980)
  local height = args.height or dpi(278)
  local interval = args.interval or 1
  local samples = args.samples or 42
  local radius = args.radius or dpi(18)

  local palette = args.palette or {
    accent = "#ff7a00",
    cpu = "#ff9a1f",
    mem = "#9c63ff",
    gpu = "#62b9ff",
    net = "#55ffd7",
    grid = "#ff7a00",
    text = "#fff4e8",
    overlay = "#120d22",
    glow = "#8d72ff",
  }

  palette.accent = palette.accent or "#ff7a00"
  palette.cpu = palette.cpu or palette.accent
  palette.mem = palette.mem or "#9c63ff"
  palette.gpu = palette.gpu or "#62b9ff"
  palette.net = palette.net or "#55ffd7"
  palette.grid = palette.grid or palette.accent
  palette.text = palette.text or "#fff4e8"
  palette.overlay = palette.overlay or "#120d22"
  palette.glow = palette.glow or "#8d72ff"

  local script_dir = gfs.get_configuration_dir() .. "src/scripts/"
  local config_dir = gfs.get_configuration_dir()
  local bt_script = script_dir .. "bt.sh"
  local vol_script = script_dir .. "vol.sh"
  local glow_path = first_existing_path({ config_dir .. "brilho.jpg" })
  local main_image_path = first_existing_path({ config_dir .. "lain.jpg" })
  local archive_images = collect_existing_paths({
    config_dir .. "1.jpg",
    config_dir .. "2.jpg",
    config_dir .. "3.jpg",
    config_dir .. "4.jpg",
  })
  local glow_surface = load_surface_safe(glow_path)

  local history = {
    cpu = {},
    mem = {},
    gpu = {},
    net = {},
  }

  for i = 1, samples do
    history.cpu[i] = 0
    history.mem[i] = 0
    history.gpu[i] = 0
    history.net[i] = 0
  end

  local state = {
    cpu = 0,
    mem = 0,
    gpu = 0,
    net = 0,
    net_rate = 0,
    wifi = nil,
    battery = nil,
    audio = 0,
    muted = false,
    bt_name = "OFFLINE",
    keyboard = "US",
  }

  local prev_total = nil
  local prev_idle = nil
  local iface = detect_default_iface()
  local prev_rx = nil
  local prev_tx = nil
  local dynamic_net_peak = 128 * 1024
  local gpu_mode = nil
  local battery_path = detect_battery_path()
  local tick = 0

  local function push(target, value)
    table.remove(target, 1)
    table.insert(target, clamp(value, 0, 100))
  end

  local function sample_cpu()
    local line = read_first_line("/proc/stat")
    if not line then
      return 0
    end

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

    local total_delta = total - prev_total
    local idle_delta = idle_all - prev_idle
    prev_total = total
    prev_idle = idle_all

    if total_delta <= 0 then
      return 0
    end

    return ((total_delta - idle_delta) / total_delta) * 100
  end

  local function sample_mem()
    local meminfo = read_all("/proc/meminfo")
    if not meminfo then
      return 0
    end

    local total = tonumber(meminfo:match("MemTotal:%s+(%d+)"))
    local available = tonumber(meminfo:match("MemAvailable:%s+(%d+)"))

    if not total or not available or total == 0 then
      return 0
    end

    return ((total - available) / total) * 100
  end

  local function detect_gpu_mode_once()
    if gpu_mode ~= nil then
      return gpu_mode
    end

    if read_first_line("/sys/class/drm/card0/device/gpu_busy_percent") then
      gpu_mode = "sysfs"
      return gpu_mode
    end

    local has_nvidia = trim(run_command([[sh -c "command -v nvidia-smi >/dev/null 2>&1 && echo yes || echo no"]]))
    gpu_mode = has_nvidia == "yes" and "nvidia" or "none"
    return gpu_mode
  end

  local function sample_gpu()
    local mode = detect_gpu_mode_once()

    if mode == "sysfs" then
      return tonumber(read_first_line("/sys/class/drm/card0/device/gpu_busy_percent")) or 0
    end

    if mode == "nvidia" then
      local raw_value = trim(run_command([[sh -c "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1"]]))
      return tonumber(raw_value) or 0
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
      return 0, 0
    end

    local rate = (math.max(0, rx - prev_rx) + math.max(0, tx - prev_tx)) / interval
    prev_rx = rx
    prev_tx = tx

    dynamic_net_peak = math.max(rate, dynamic_net_peak * 0.92, 128 * 1024)
    return (rate / dynamic_net_peak) * 100, rate
  end

  local function sample_wifi()
    local raw_value = trim(run_command([[sh -c "awk 'NR==3 {printf \"%3.0f\", ($3/70)*100}' /proc/net/wireless 2>/dev/null"]]))
    local value = tonumber(raw_value)
    if not value then
      return nil
    end

    return clamp(value, 0, 100)
  end

  local function sample_battery()
    if not battery_path then
      battery_path = detect_battery_path()
      if not battery_path then
        return nil
      end
    end

    return tonumber(read_first_line(battery_path .. "/capacity"))
  end

  local function sample_audio()
    local volume = trim(run_command(vol_script .. " volume 2>/dev/null"))
    local mute = trim(run_command(vol_script .. " mute 2>/dev/null"))
    local volume_number = tonumber((volume:gsub("%%", ""))) or 0
    return volume_number, mute:match("yes") ~= nil
  end

  local function sample_bt_name()
    local output = (run_command(bt_script .. " 2>/dev/null") or ""):gsub("\n", " ")
    output = trim(output)
    if output == "" then
      return "OFFLINE"
    end

    return shorten(output, 20):upper()
  end

  local function sample_keyboard()
    local layout = trim(run_command([[sh -c "setxkbmap -query 2>/dev/null | awk '/layout/ {print $2}'"]]))
    layout = layout:match("([^,]+)") or layout
    if layout == "" then
      return "US"
    end

    return layout:upper()
  end

  local function constrain(widget, forced_width, forced_height)
    if not forced_width and not forced_height then
      return widget
    end

    return wibox.widget {
      widget,
      forced_width = forced_width,
      forced_height = forced_height,
      strategy = "exact",
      widget = wibox.container.constraint,
    }
  end

  local function create_info_row(label_text, initial_value, accent)
    local label = wibox.widget {
      text = label_text,
      font = "JetBrainsMono Nerd Font, bold 11",
      widget = wibox.widget.textbox,
    }

    local value = wibox.widget {
      text = initial_value or "--",
      font = "JetBrainsMono Nerd Font, ExtraBold 12",
      align = "right",
      widget = wibox.widget.textbox,
    }

    local row = wibox.widget {
      {
        {
          {
            label,
            fg = accent,
            widget = wibox.container.background,
          },
          nil,
          value,
          expand = "inside",
          layout = wibox.layout.align.horizontal,
        },
        left = dpi(8),
        right = dpi(8),
        top = dpi(5),
        bottom = dpi(5),
        widget = wibox.container.margin,
      },
      bg = with_alpha(accent, 0.09),
      border_width = dpi(1),
      border_color = with_alpha(accent, 0.32),
      shape = function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, dpi(6))
      end,
      widget = wibox.container.background,
    }

    return row, value
  end

  local function create_section_frame(title_text, body, accent, options)
    options = options or {}

    local section_title = wibox.widget {
      text = title_text,
      font = "JetBrainsMono Nerd Font, ExtraBold 11",
      widget = wibox.widget.textbox,
    }

    local section_line = wibox.widget {
      forced_height = dpi(2),
      bg = gears.color {
        type = "linear",
        from = { 0, 0 },
        to = { width, 0 },
        stops = {
          { 0, accent },
          { 0.55, hex_with_alpha_string(accent, 0.22) },
          { 1, "#00000000" },
        },
      },
      shape = gears.shape.rounded_bar,
      widget = wibox.container.background,
    }

    return wibox.widget {
      {
        {
          {
            section_title,
            fg = accent,
            widget = wibox.container.background,
          },
          section_line,
          body,
          spacing = dpi(8),
          layout = wibox.layout.fixed.vertical,
        },
        margins = options.margins or dpi(10),
        widget = wibox.container.margin,
      },
      bg = with_alpha(options.bg or palette.overlay, options.bg_alpha or 0.76),
      border_width = dpi(1),
      border_color = with_alpha(accent, 0.82),
      shape = function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, options.radius or dpi(10))
      end,
      widget = wibox.container.background,
    }
  end

  local function create_monitor_canvas(image_path, options)
    options = options or {}

    local image_surface = load_surface_safe(image_path)
    local accent = options.accent or palette.accent
    local tint = options.tint or palette.glow
    local glow_alpha = options.glow_alpha or 0.14
    local tint_alpha = options.tint_alpha or 0.12
    local corner = options.radius or dpi(8)
    local widget = wibox.widget.base.make_widget()

    function widget:fit(_, available_width, available_height)
      return available_width, available_height
    end

    function widget:draw(_, cr, w, h)
      local accent_r, accent_g, accent_b = hex_to_rgba(accent)
      local tint_r, tint_g, tint_b = hex_to_rgba(tint)
      local corner_len = dpi(16)

      cr:save()
      gears.shape.rounded_rect(cr, w, h, corner)
      cr:clip()

      cr:set_source_rgba(0.02, 0.02, 0.05, 0.98)
      cr:paint()

      if image_surface then
        draw_surface_cover(cr, image_surface, w, h, 0.95)
      end

      cr:rectangle(0, 0, w, h)
      cr:set_source_rgba(tint_r, tint_g, tint_b, tint_alpha)
      cr:fill()

      cr:rectangle(0, h * 0.7, w, h * 0.3)
      cr:set_source_rgba(accent_r, accent_g, accent_b, 0.10)
      cr:fill()

      if glow_surface then
        draw_surface_cover(cr, glow_surface, w, h, glow_alpha)
      end

      for line = 2, h, 4 do
        cr:set_source_rgba(1, 1, 1, 0.025)
        cr:rectangle(0, line, w, 1)
        cr:fill()
      end

      cr:restore()

      gears.shape.rounded_rect(cr, w, h, corner)
      cr:set_source_rgba(accent_r, accent_g, accent_b, 0.88)
      cr:set_line_width(dpi(1.2))
      cr:stroke()

      cr:set_source_rgba(accent_r, accent_g, accent_b, 0.92)
      cr:set_line_width(dpi(1.4))
      cr:move_to(0, corner_len)
      cr:line_to(0, 0)
      cr:line_to(corner_len, 0)
      cr:move_to(w - corner_len, 0)
      cr:line_to(w, 0)
      cr:line_to(w, corner_len)
      cr:move_to(0, h - corner_len)
      cr:line_to(0, h)
      cr:line_to(corner_len, h)
      cr:move_to(w - corner_len, h)
      cr:line_to(w, h)
      cr:line_to(w, h - corner_len)
      cr:stroke()
    end

    return widget
  end

  local function create_monitor_section(title_text, image_path, options)
    options = options or {}

    local footer = nil
    if options.footer then
      footer = wibox.widget {
        text = options.footer,
        font = "JetBrainsMono Nerd Font, bold 10",
        widget = wibox.widget.textbox,
      }
    end

    local content = {
      constrain(
        create_monitor_canvas(image_path, {
          accent = options.accent,
          tint = options.tint,
          glow_alpha = options.glow_alpha,
          tint_alpha = options.tint_alpha,
          radius = dpi(8),
        }),
        nil,
        options.image_height or dpi(180)
      ),
      spacing = dpi(6),
      layout = wibox.layout.fixed.vertical,
    }

    if footer then
      table.insert(content, footer)
    end

    return create_section_frame(title_text, content, options.accent or palette.accent, {
      bg_alpha = options.bg_alpha or 0.72,
      margins = options.margins or dpi(10),
    })
  end

  local function archive_image(index)
    return archive_images[index] or main_image_path
  end

  local subject_row, _ = create_info_row("SUBJECT", "RADICAL-LAIN", palette.accent)
  local signal_row, signal_value = create_info_row("STATE", "WIRED SYNC", palette.mem)
  local cpu_row, cpu_value = create_info_row("CPU LOAD", "00%", palette.cpu)
  local mem_row, mem_value = create_info_row("MEM BANK", "00%", palette.mem)
  local gpu_row, gpu_value = create_info_row("GPU CORE", "00%", palette.gpu)
  local net_row, net_value = create_info_row("NET FLOW", "0 B/S", palette.net)
  local wifi_row, wifi_value = create_info_row("WIFI NOISE", "OFFLINE", palette.net)
  local battery_row, battery_value = create_info_row("BATTERY", "N/D", palette.cpu)
  local audio_row, audio_value = create_info_row("AUDIO BUS", "00%", palette.mem)
  local kb_row, kb_value = create_info_row("KEYMAP", "US", palette.gpu)
  local bt_row, bt_value = create_info_row("BT NODE", "OFFLINE", palette.gpu)
  local bus_row, bus_value = create_info_row("WIRED BUS", "LINK OPEN", palette.accent)

  local dossier_note = wibox.widget {
    markup = "<span foreground='" .. palette.accent .. "'><b>NOTES</b></span>  <span foreground='#ffffffbb'>sleeping protocol // static halo // wired resonance stable</span>",
    font = "JetBrainsMono Nerd Font, bold 10",
    widget = wibox.widget.textbox,
  }

  local left_rows = wibox.widget {
    subject_row,
    signal_row,
    cpu_row,
    mem_row,
    gpu_row,
    spacing = dpi(8),
    layout = wibox.layout.fixed.vertical,
  }

  local right_rows = wibox.widget {
    net_row,
    wifi_row,
    battery_row,
    audio_row,
    kb_row,
    spacing = dpi(8),
    layout = wibox.layout.fixed.vertical,
  }

  local data_panel = create_section_frame(
    "SUBJECT DX-LN // WIRED MONITOR",
    {
      {
        left_rows,
        right_rows,
        spacing = dpi(10),
        layout = wibox.layout.flex.horizontal,
      },
      bt_row,
      bus_row,
      dossier_note,
      spacing = dpi(8),
      layout = wibox.layout.fixed.vertical,
    },
    palette.accent,
    {
      bg_alpha = 0.70,
      margins = dpi(10),
    }
  )

  local threat_segments = {}
  local threat_strip = wibox.layout.fixed.horizontal()
  threat_strip.spacing = dpi(4)

  for index = 1, 12 do
    local segment = wibox.widget {
      forced_width = dpi(18),
      forced_height = dpi(8),
      shape = gears.shape.rounded_bar,
      bg = with_alpha(palette.accent, 0.14),
      widget = wibox.container.background,
    }

    threat_segments[index] = segment
    threat_strip:add(segment)
  end

  local threat_value = wibox.widget {
    text = "IDLE HUM",
    font = "JetBrainsMono Nerd Font, ExtraBold 12",
    align = "right",
    widget = wibox.widget.textbox,
  }

  local graph_widget = wibox.widget.base.make_widget()

  local function points_for(values, x, y, w, h)
    local points = {}
    local count = #values
    local step = w / math.max(count - 1, 1)

    for i, value in ipairs(values) do
      points[i] = {
        x = x + (i - 1) * step,
        y = y + h - (h * (clamp(value, 0, 100) / 100)),
      }
    end

    return points
  end

  local function trace_smooth_line(cr, points)
    if #points == 0 then
      return
    end

    cr:move_to(points[1].x, points[1].y)

    for i = 2, #points do
      local previous = points[i - 1]
      local current = points[i]
      local mid_x = (previous.x + current.x) / 2

      cr:curve_to(mid_x, previous.y, mid_x, current.y, current.x, current.y)
    end
  end

  local function draw_area(cr, values, x, y, w, h, color_hex, alpha)
    local count = #values
    if count < 2 then
      return
    end

    local r, g, b = hex_to_rgba(color_hex)
    local points = points_for(values, x, y, w, h)
    local first = points[1]
    local last = points[#points]

    cr:new_path()
    cr:move_to(x, y + h)
    cr:line_to(first.x, first.y)
    trace_smooth_line(cr, points)
    cr:line_to(last.x, y + h)
    cr:close_path()
    cr:set_source_rgba(r, g, b, alpha)
    cr:fill_preserve()

    cr:set_source_rgba(r, g, b, 0.22)
    cr:set_line_width(dpi(6))
    cr:stroke_preserve()

    cr:new_path()
    trace_smooth_line(cr, points)
    cr:set_source_rgba(r, g, b, 0.95)
    cr:set_line_width(dpi(2))
    cr:stroke()
  end

  function graph_widget:fit(_, available_width, _)
    return available_width, dpi(170)
  end

  function graph_widget:draw(_, cr, w, h)
    local x = dpi(8)
    local y = dpi(8)
    local plot_w = w - dpi(16)
    local plot_h = h - dpi(16)
    local grid_r, grid_g, grid_b = hex_to_rgba(palette.grid)

    local accent_r, accent_g, accent_b = hex_to_rgba(palette.accent)

    gears.shape.rounded_rect(cr, w, h, dpi(12))
    cr:set_source_rgba(0.03, 0.03, 0.08, 0.94)
    cr:fill()

    gears.shape.rounded_rect(cr, w, h, dpi(12))
    cr:set_source_rgba(accent_r, accent_g, accent_b, 0.10)
    cr:set_line_width(dpi(8))
    cr:stroke()

    cr:rectangle(x, y + plot_h * 0.55, plot_w, plot_h * 0.45)
    cr:set_source_rgba(accent_r, accent_g, accent_b, 0.05)
    cr:fill()

    for i = 0, 4 do
      local gy = y + (plot_h / 4) * i
      cr:set_source_rgba(grid_r, grid_g, grid_b, i % 2 == 0 and 0.22 or 0.12)
      cr:set_line_width(1)
      cr:move_to(x, gy)
      cr:line_to(x + plot_w, gy)
      cr:stroke()
    end

    for i = 0, 10 do
      local gx = x + (plot_w / 10) * i
      cr:set_source_rgba(accent_r, accent_g, accent_b, i % 2 == 0 and 0.09 or 0.04)
      cr:set_line_width(1)
      cr:move_to(gx, y)
      cr:line_to(gx, y + plot_h)
      cr:stroke()
    end

    draw_area(cr, history.mem, x, y, plot_w, plot_h, palette.mem, 0.34)
    draw_area(cr, history.gpu, x, y, plot_w, plot_h, palette.gpu, 0.26)
    draw_area(cr, history.net, x, y, plot_w, plot_h, palette.net, 0.24)
    draw_area(cr, history.cpu, x, y, plot_w, plot_h, palette.cpu, 0.20)

    cr:set_source_rgba(accent_r, accent_g, accent_b, 0.22)
    cr:set_line_width(dpi(1.5))
    cr:move_to(x + dpi(6), y + dpi(6))
    cr:line_to(x + dpi(54), y + dpi(6))
    cr:line_to(x + dpi(54), y + dpi(22))
    cr:stroke()

    cr:move_to(x + plot_w - dpi(54), y + plot_h - dpi(6))
    cr:line_to(x + plot_w - dpi(6), y + plot_h - dpi(6))
    cr:line_to(x + plot_w - dpi(6), y + plot_h - dpi(22))
    cr:stroke()
  end

  local title = wibox.widget {
    text = "[「RadicalWM ⩜ のモニタ、ヤベェ。これ以上ない。🏴」] ☚⍢⃝☚ | ┌∩┐(◣_◢)┌∩┐ ▄︻╦芫≡══--𖦏 🅱",
    font = "JetBrainsMono Nerd Font, ExtraBold 14",
    align = "center",
    widget = wibox.widget.textbox,
  }

  local header_line = wibox.widget {
    forced_height = dpi(3),
    bg = gears.color {
      type = "linear",
      from = { 0, 0 },
      to = { width, 0 },
      stops = {
        { 0, "#AA5A9C" },
        { 0.33, palette.accent },
        { 0.66, palette.gpu },
        { 1, palette.mem },
      }
    },
    shape = gears.shape.rounded_bar,
    widget = wibox.container.background,
  }

  local title_wrap = wibox.widget {
    {
      title,
      margins = dpi(10),
      widget = wibox.container.margin,
    },
    fg = palette.accent,
    bg = with_alpha(palette.accent, 0.08),
    border_width = dpi(1),
    border_color = with_alpha(palette.accent, 0.32),
    shape = function(cr, w, h)
      gears.shape.rounded_rect(cr, w, h, dpi(8))
    end,
    widget = wibox.container.background,
  }

  local top_main_width = math.floor(width * 0.34)
  local top_aux_width = math.floor(width * 0.21)
  local top_data_width = math.max(dpi(350), width - top_main_width - top_aux_width - dpi(86))
  local bottom_side_width = math.floor(width * 0.16)
  local telemetry_width = math.max(dpi(360), width - bottom_side_width * 2 - dpi(86))

  local top_row = wibox.widget {
    constrain(
      create_monitor_section("PRIMARY FEED // LAIN", main_image_path, {
        accent = palette.accent,
        tint = palette.gpu,
        glow_alpha = 0.18,
        tint_alpha = 0.10,
        image_height = dpi(332),
        footer = "observer locked // eyes up to the wired",
      }),
      top_main_width,
      nil
    ),
    constrain(
      {
        create_monitor_section("ARCHIVE 01", archive_image(1), {
          accent = palette.mem,
          tint = palette.mem,
          glow_alpha = 0.14,
          image_height = dpi(154),
          footer = "ghost cache // residual silhouette",
        }),
        create_monitor_section("ARCHIVE 02", archive_image(2), {
          accent = palette.gpu,
          tint = palette.gpu,
          glow_alpha = 0.16,
          image_height = dpi(154),
          footer = "signal echo // passive scan",
        }),
        spacing = dpi(14),
        layout = wibox.layout.fixed.vertical,
      },
      top_aux_width,
      nil
    ),
    constrain(data_panel, top_data_width, nil),
    spacing = dpi(14),
    layout = wibox.layout.fixed.horizontal,
  }

  local bottom_row = wibox.widget {
    constrain(
      create_monitor_section("FIELD 03", archive_image(3), {
        accent = palette.net,
        tint = palette.net,
        glow_alpha = 0.16,
        image_height = dpi(144),
        footer = "ambient packet rain",
      }),
      bottom_side_width,
      nil
    ),
    constrain(
      create_section_frame(
        "THREAT LEVEL // WIRED TRACE",
        {
          constrain(graph_widget, nil, dpi(186)),
          {
            threat_strip,
            nil,
            threat_value,
            expand = "inside",
            layout = wibox.layout.align.horizontal,
          },
          spacing = dpi(10),
          layout = wibox.layout.fixed.vertical,
        },
        palette.accent,
        {
          bg_alpha = 0.66,
          margins = dpi(10),
        }
      ),
      telemetry_width,
      nil
    ),
    constrain(
      create_monitor_section("FIELD 04", archive_image(4), {
        accent = palette.cpu,
        tint = palette.cpu,
        glow_alpha = 0.17,
        image_height = dpi(144),
        footer = "thermal phantom bloom",
      }),
      bottom_side_width,
      nil
    ),
    spacing = dpi(14),
    layout = wibox.layout.fixed.horizontal,
  }

  local panel = wibox.widget {
    {
      {
        header_line,
        title_wrap,
        top_row,
        bottom_row,
        spacing = dpi(12),
        layout = wibox.layout.fixed.vertical,
      },
      margins = dpi(18),
      widget = wibox.container.margin,
    },
    bg = gears.color {
      type = "linear",
      from = { 0, 0 },
      to = { 0, height },
      stops = {
        { 0, "#0b0817f0" },
        { 0.55, "#090611ef" },
        { 1, "#05040af2" },
      }
    },
    fg = palette.text,
    shape = function(cr, w, h)
      gears.shape.rounded_rect(cr, w, h, radius)
    end,
    border_width = dpi(1),
    border_color = with_alpha(palette.accent, 0.36),
    widget = wibox.container.background,
  }

  local function update_texts()
    local threat_load = (state.cpu * 0.34) + (state.mem * 0.22) + (state.gpu * 0.24) + (state.net * 0.20)
    local threat_label = "IDLE HUM"

    if threat_load >= 82 then
      threat_label = "MAX OVERDRIVE"
    elseif threat_load >= 62 then
      threat_label = "STATIC SURGE"
    elseif threat_load >= 38 then
      threat_label = "WIRED SYNC"
    end

    cpu_value.text = string.format("%02d%%", math.floor(state.cpu + 0.5))
    mem_value.text = string.format("%02d%%", math.floor(state.mem + 0.5))
    gpu_value.text = string.format("%02d%%", math.floor(state.gpu + 0.5))
    net_value.text = string.format("%02d%% :: %s", math.floor(state.net + 0.5), format_bytes_per_sec(state.net_rate))
    signal_value.text = threat_label
    threat_value.text = threat_label

    if state.wifi then
      wifi_value.text = string.format("%02d%%", math.floor(state.wifi + 0.5))
    else
      wifi_value.text = "OFFLINE"
    end

    if state.battery then
      battery_value.text = string.format("%02d%%", math.floor(state.battery + 0.5))
    else
      battery_value.text = "N/D"
    end

    if state.muted then
      audio_value.text = "MUTED"
    else
      audio_value.text = string.format("%02d%%", math.floor(state.audio + 0.5))
    end

    kb_value.text = state.keyboard
    bt_value.text = shorten(state.bt_name, 22)
    bus_value.text = string.format(
      "BT %s // WIFI %s // AUDIO %s",
      shorten(state.bt_name, 10),
      state.wifi and string.format("%02d%%", math.floor(state.wifi + 0.5)) or "OFF",
      state.muted and "MUTED" or string.format("%02d%%", math.floor(state.audio + 0.5))
    )

    local active_segments = math.max(1, math.floor((threat_load / 100) * #threat_segments + 0.5))
    for index, segment in ipairs(threat_segments) do
      if index <= active_segments then
        local color = palette.accent
        if index >= 10 then
          color = palette.mem
        elseif index >= 7 then
          color = palette.cpu
        end

        segment.bg = color
      else
        segment.bg = with_alpha(palette.accent, 0.14)
      end
    end
  end

  panel._preserve_colors = true
  panel._preferred_segment_width = width
  panel._preferred_segment_height = height
  panel._always_visible = true
  panel._popup_ontop = false
  panel._popup_type = "desktop"
  panel._popup_opacity = 0.8
  panel._reserve_space = false
  panel._input_passthrough = true

  panel._timer = gears.timer {
    timeout = interval,
    autostart = true,
    call_now = true,
    callback = function()
      tick = tick + 1

      state.cpu = clamp(sample_cpu(), 0, 100)
      state.mem = clamp(sample_mem(), 0, 100)
      state.gpu = clamp(sample_gpu(), 0, 100)
      local net_percent, net_rate = sample_net()
      state.net = clamp(net_percent, 0, 100)
      state.net_rate = net_rate or 0

      push(history.cpu, state.cpu)
      push(history.mem, state.mem)
      push(history.gpu, state.gpu)
      push(history.net, state.net)

      if tick == 1 or tick % 3 == 0 then
        state.wifi = sample_wifi()
        state.battery = sample_battery()
        state.audio, state.muted = sample_audio()
        state.keyboard = sample_keyboard()
      end

      if tick == 1 or tick % 5 == 0 then
        state.bt_name = sample_bt_name()
      end

      update_texts()
      graph_widget:emit_signal("widget::redraw_needed")
    end,
  }

  update_texts()
  return panel
end

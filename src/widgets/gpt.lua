--[[ DEEPSEAK ]]--

local awful = require("awful")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local gears = require("gears")
local wibox = require("wibox")
local lgi = require("lgi")
local cairo = lgi.cairo

-- Variáveis locais para otimização
local shape_rounded_rect = gears.shape.rounded_rect
local pattern_linear = cairo.Pattern.create_linear
local math_max = math.max
local string_format = string.format
local io_open = io.open
local io_popen = io.popen

-- Cache de comandos para evitar repetição
local command_cache = {}
local function command_exists_cached(cmd)
    local cached = command_cache[cmd]
    if cached ~= nil then
        return cached
    end
    local p = io_popen("sh -c 'command -v " .. cmd .. " >/dev/null 2>&1 && echo yes || echo no'")
    if not p then
        command_cache[cmd] = false
        return false
    end
    local out = p:read("*l")
    p:close()
    local exists = out == "yes"
    command_cache[cmd] = exists
    return exists
end

local function hex_to_rgba(hex, alpha_override)
    hex = (hex or "#ffffff"):gsub("#", "")
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
    local f = io_open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

local function read_all(path)
    local f = io_open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function path_exists(path)
    local f = io_open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Detecta interface padrão apenas uma vez, com cache
local default_iface_cache = nil
local function detect_default_iface()
    if default_iface_cache then
        return default_iface_cache
    end
    local p = io_popen([[sh -c "ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'"]])
    if p then
        local iface = p:read("*l")
        p:close()
        if iface and iface ~= "" then
            default_iface_cache = iface
            return iface
        end
    end
    local p2 = io_popen([[sh -c "ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1"]])
    if p2 then
        local fallback = p2:read("*l")
        p2:close()
        default_iface_cache = fallback
        return fallback
    end
    default_iface_cache = "wlo1" -- fallback genérico
    return default_iface_cache
end

local amd_gpu_busy_path_cache = nil
local function detect_amd_gpu_busy_path()
    if amd_gpu_busy_path_cache then
        return amd_gpu_busy_path_cache
    end
    local p = io_popen([[sh -c "find /sys/class/drm/card* -path '*/device/gpu_busy_percent' 2>/dev/null | head -n1"]])
    if p then
        local path = p:read("*l")
        p:close()
        if path and path ~= "" then
            amd_gpu_busy_path_cache = path
            return path
        end
    end
    amd_gpu_busy_path_cache = nil
    return nil
end

local function format_bytes_per_sec(bytes)
    local units = { "B/s", "KiB/s", "MiB/s", "GiB/s" }
    local value = bytes or 0
    local unit = 1
    while value >= 1024 and unit < #units do
        value = value / 1024
        unit = unit + 1
    end
    if unit == 1 then
        return string_format("%d %s", math.floor(value + 0.5), units[unit])
    end
    return string_format("%.1f %s", value, units[unit])
end

local function kib_to_gib(kib)
    return (kib or 0) / 1024 / 1024
end

-- Buffer circular (ring buffer) para históricos
local function create_ring_buffer(size)
    local buffer = {}
    for i = 1, size do buffer[i] = 0 end
    local head = 1
    return {
        size = size,
        data = buffer,
        push = function(self, value)
            self.data[self.head] = value
            self.head = self.head % self.size + 1
        end,
        get_all = function(self)
            local all = {}
            for i = 1, self.size do
                all[i] = self.data[(self.head + i - 2) % self.size + 1]
            end
            return all
        end
    }
end

return function(args)
    args = args or {}
    local screen = args.screen
    local compact_width = args.width or dpi(450)
    local compact_height = args.height or dpi(132)
    local expanded_width = args.expanded_width or dpi(780)
    local expanded_height = args.expanded_height or dpi(290)
    local interval = args.interval or 1
    local samples = args.samples or 52
    local expanded_samples = args.expanded_samples or 110
    local radius = args.radius or dpi(12)

    local palette = args.palette or {
        cpu = "#00F6FF",
        mem = "#FF00F5",
        gpu = "#8BFF00",
        net = "#FF9F1C",
        grid = "#5A2A82",
        text = "#E8D9FF",
        overlay = "#0B0714",
        border = "#A020F0",
    }

    -- Históricos com buffer circular
    local history = {
        cpu = create_ring_buffer(expanded_samples),
        mem = create_ring_buffer(expanded_samples),
        gpu = create_ring_buffer(expanded_samples),
        net = create_ring_buffer(expanded_samples),
    }

    local last = {
        cpu = 0,
        mem = 0,
        gpu = 0,
        net = 0,
    }

    local stats = {
        mem_total_kib = 0,
        mem_used_kib = 0,
        net_rate = 0,
        iface = args.net_iface or detect_default_iface(),
        gpu_mode = "none",
        gpu_label = "GPU unavailable",
        net_peak = 0,
    }

    -- Variáveis de estado para CPU
    local prev_total = nil
    local prev_idle = nil

    -- Variáveis de estado para rede
    local iface = stats.iface
    local prev_rx = nil
    local prev_tx = nil
    local dynamic_net_peak = 128 * 1024

    -- Detecção e cache do modo GPU
    local gpu_mode = nil
    local amd_gpu_busy_path = detect_amd_gpu_busy_path()
    local radeontop_device = args.radeontop_device or "/dev/dri/card1"

    -- Valor cacheado para GPU (evita comando externo a cada segundo)
    local cached_gpu = 0

    -- Funções de amostragem (leves)
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
        stats.mem_total_kib = total
        stats.mem_used_kib = used

        return (used / total) * 100
    end

    -- Função de detecção do modo GPU (executada apenas uma vez)
    local function detect_gpu_mode_once()
        if gpu_mode ~= nil then
            return gpu_mode
        end

        if amd_gpu_busy_path and path_exists(amd_gpu_busy_path) then
            gpu_mode = "sysfs"
            return gpu_mode
        end

        if command_exists_cached("radeontop") then
            gpu_mode = "radeontop"
            return gpu_mode
        end

        gpu_mode = "none"
        return gpu_mode
    end

    -- Amostragem de GPU real (executada periodicamente, não a cada segundo)
    local function sample_gpu_real()
        local mode = detect_gpu_mode_once()
        stats.gpu_mode = mode

        if mode == "sysfs" then
            stats.gpu_label = "GPU amdgpu sysfs"
            if (not amd_gpu_busy_path) or (not path_exists(amd_gpu_busy_path)) then
                amd_gpu_busy_path = detect_amd_gpu_busy_path()
            end
            if amd_gpu_busy_path and path_exists(amd_gpu_busy_path) then
                return tonumber(read_first_line(amd_gpu_busy_path)) or 0
            end
            return 0

        elseif mode == "radeontop" then
            stats.gpu_label = "GPU radeontop"
            local cmd = string_format(
                "sh -c 'radeontop -d - -l 1 -i %s -p %q 2>/dev/null | tail -n 1'",
                tostring(interval),
                radeontop_device
            )
            local p = io_popen(cmd)
            if not p then return 0 end
            local out = p:read("*a") or ""
            p:close()
            local value = out:match("gpu%s+([%d%.]+)%%") or out:match("gpu%s*([%d%.]+)")
            return tonumber(value) or 0
        end

        stats.gpu_label = "GPU unavailable"
        return 0
    end

    local function sample_net()
        -- Se a interface atual não funcionar, tenta redetectar
        local rx_path = "/sys/class/net/" .. iface .. "/statistics/rx_bytes"
        local tx_path = "/sys/class/net/" .. iface .. "/statistics/tx_bytes"
        if not path_exists(rx_path) or not path_exists(tx_path) then
            iface = detect_default_iface()
            stats.iface = iface
            rx_path = "/sys/class/net/" .. iface .. "/statistics/rx_bytes"
            tx_path = "/sys/class/net/" .. iface .. "/statistics/tx_bytes"
            if not path_exists(rx_path) or not path_exists(tx_path) then
                stats.net_rate = 0
                return 0
            end
        end

        local rx = tonumber(read_first_line(rx_path)) or 0
        local tx = tonumber(read_first_line(tx_path)) or 0

        if not prev_rx or not prev_tx then
            prev_rx = rx
            prev_tx = tx
            stats.net_rate = 0
            return 0
        end

        local drx = math_max(0, rx - prev_rx)
        local dtx = math_max(0, tx - prev_tx)

        prev_rx = rx
        prev_tx = tx

        local rate = (drx + dtx) / interval
        stats.net_rate = rate
        stats.net_peak = math_max(stats.net_peak, rate)
        dynamic_net_peak = math_max(rate, dynamic_net_peak * 0.92, 128 * 1024)

        return (rate / dynamic_net_peak) * 100
    end

    -- Funções de desenho (mantidas, mas com pequenas otimizações)
    local function rounded_rect_at(cr, x, y, w, h, r)
        cr:save()
        cr:translate(x, y)
        shape_rounded_rect(cr, w, h, r)
        cr:restore()
    end

    local function build_points(values, x, y, w, h)
        local pts = {}
        local n = #values
        local step = w / math_max(n - 1, 1)
        for i, value in ipairs(values) do
            pts[i] = {
                x = x + (i - 1) * step,
                y = y + h * (1 - (value / 100))
            }
        end
        return pts
    end

    local function smooth_path(cr, points)
        if #points < 2 then return end
        cr:new_path()
        cr:move_to(points[1].x, points[1].y)
        for i = 1, #points - 1 do
            local p0 = points[i]
            local p1 = points[i + 1]
            local mx = (p0.x + p1.x) / 2
            cr:curve_to(mx, p0.y, mx, p1.y, p1.x, p1.y)
        end
    end

    local function draw_series_fill(cr, points, base_y, color_hex)
        if #points < 2 then return end
        local r, g, b = hex_to_rgba(color_hex)
        cr:new_path()
        cr:move_to(points[1].x, base_y)
        cr:line_to(points[1].x, points[1].y)
        for i = 1, #points - 1 do
            local p0 = points[i]
            local p1 = points[i + 1]
            local mx = (p0.x + p1.x) / 2
            cr:curve_to(mx, p0.y, mx, p1.y, p1.x, p1.y)
        end
        cr:line_to(points[#points].x, base_y)
        cr:close_path()
        local pat = pattern_linear(0, points[1].y, 0, base_y)
        pat:add_color_stop_rgba(0.0, r, g, b, 0.24)
        pat:add_color_stop_rgba(0.55, r, g, b, 0.08)
        pat:add_color_stop_rgba(1.0, r, g, b, 0.01)
        cr:set_source(pat)
        cr:fill()
    end

    local function draw_series_line(cr, points, color_hex, thickness)
        if #points < 2 then return end
        local r, g, b = hex_to_rgba(color_hex)
        local line_w = thickness or dpi(2.2)
        cr:set_line_join(cairo.LineJoin.ROUND)
        cr:set_line_cap(cairo.LineCap.ROUND)
        smooth_path(cr, points)
        cr:set_source_rgba(r, g, b, 0.16)
        cr:set_line_width(line_w + dpi(6))
        cr:stroke_preserve()
        cr:set_source_rgba(r, g, b, 0.98)
        cr:set_line_width(line_w)
        cr:stroke()
        local last_pt = points[#points]
        cr:arc(last_pt.x, last_pt.y, dpi(2.8), 0, 2 * math.pi)
        cr:set_source_rgba(r, g, b, 1)
        cr:fill()
        cr:arc(last_pt.x, last_pt.y, dpi(6.2), 0, 2 * math.pi)
        cr:set_source_rgba(r, g, b, 0.18)
        cr:fill()
    end

    local function draw_badge(cr, x, y, label, value, color_hex, big)
        local label_font = big and dpi(14) or dpi(12)
        local value_font = big and dpi(13) or dpi(11)
        local badge_h = big and dpi(32) or dpi(28)

        cr:select_font_face("JetBrainsMono Nerd Font", cairo.FontSlant.NORMAL, cairo.FontWeight.BOLD)
        cr:set_font_size(label_font)
        local label_ext = cr:text_extents(label)

        local value_text = string_format("%02d%%", math.floor(value + 0.5))
        cr:set_font_size(value_font)
        local value_ext = cr:text_extents(value_text)

        local bw = math_max(label_ext.width, value_ext.width) + dpi(24)
        local r, g, b = hex_to_rgba(color_hex)

        rounded_rect_at(cr, x, y, bw, badge_h, dpi(8))
        cr:set_source_rgba(r, g, b, 0.11)
        cr:fill()

        rounded_rect_at(cr, x, y, bw, badge_h, dpi(8))
        cr:set_source_rgba(r, g, b, 0.58)
        cr:set_line_width(1.4)
        cr:stroke()

        rounded_rect_at(cr, x + dpi(6), y + dpi(6), dpi(7), badge_h - dpi(12), dpi(3))
        cr:set_source_rgba(r, g, b, 1)
        cr:fill()

        local tr, tg, tb = hex_to_rgba(palette.text)
        cr:set_source_rgba(tr, tg, tb, 0.98)
        cr:select_font_face("JetBrainsMono Nerd Font", cairo.FontSlant.NORMAL, cairo.FontWeight.BOLD)
        cr:set_font_size(label_font)
        cr:move_to(x + dpi(18), y + dpi(14))
        cr:show_text(label)

        cr:set_source_rgba(r, g, b, 0.99)
        cr:set_font_size(value_font)
        cr:move_to(x + dpi(18), y + badge_h - dpi(4))
        cr:show_text(value_text)
    end

    local function draw_info_pill(cr, x, y, w, label, value, color_hex)
        local r, g, b = hex_to_rgba(color_hex)
        local tr, tg, tb = hex_to_rgba(palette.text)
        rounded_rect_at(cr, x, y, w, dpi(28), dpi(8))
        cr:set_source_rgba(r, g, b, 0.08)
        cr:fill()
        rounded_rect_at(cr, x, y, w, dpi(28), dpi(8))
        cr:set_source_rgba(r, g, b, 0.42)
        cr:set_line_width(1.2)
        cr:stroke()
        cr:select_font_face("JetBrainsMono Nerd Font", cairo.FontSlant.NORMAL, cairo.FontWeight.BOLD)
        cr:set_font_size(dpi(11))
        cr:set_source_rgba(r, g, b, 1)
        cr:move_to(x + dpi(10), y + dpi(12))
        cr:show_text(label)
        cr:set_source_rgba(tr, tg, tb, 0.96)
        cr:set_font_size(dpi(10))
        cr:move_to(x + dpi(10), y + dpi(23))
        cr:show_text(value)
    end

    local function draw_background(cr, w, h, big)
        local r, g, b = hex_to_rgba(palette.overlay)
        local br, bg, bb = hex_to_rgba(palette.border)
        rounded_rect_at(cr, 0, 0, w, h, radius)
        cr:set_source_rgba(r, g, b, 0.94)
        cr:fill()
        rounded_rect_at(cr, dpi(1), dpi(1), w - dpi(2), h - dpi(2), radius)
        cr:set_source_rgba(br, bg, bb, 0.18)
        cr:set_line_width(big and 10 or 7)
        cr:stroke()
        rounded_rect_at(cr, 0.5, 0.5, w - 1, h - 1, radius)
        cr:set_source_rgba(br, bg, bb, 0.96)
        cr:set_line_width(big and 3.2 or 2.2)
        cr:stroke()
        rounded_rect_at(cr, dpi(4), dpi(4), w - dpi(8), h - dpi(8), math_max(dpi(6), radius - dpi(2)))
        cr:set_source_rgba(br, bg, bb, 0.36)
        cr:set_line_width(big and 1.8 or 1.2)
        cr:stroke()
        rounded_rect_at(cr, dpi(1), dpi(1), w - dpi(2), h * 0.38, radius)
        cr:set_source_rgba(1, 1, 1, 0.025)
        cr:fill()
    end

    local function draw_grid(cr, x, y, w, h, big)
        local gr, gg, gb = hex_to_rgba(palette.grid)
        cr:set_source_rgba(gr, gg, gb, big and 0.22 or 0.17)
        cr:set_line_width(1)
        for i = 0, 4 do
            local gy = y + (h / 4) * i
            cr:move_to(x, gy)
            cr:line_to(x + w, gy)
            cr:stroke()
        end
        for i = 0, 7 do
            local gx = x + (w / 7) * i
            cr:move_to(gx, y)
            cr:line_to(gx, y + h)
            cr:stroke()
        end
    end

    local function draw_scale_labels(cr, x, y, h)
        local tr, tg, tb = hex_to_rgba(palette.text)
        cr:set_source_rgba(tr, tg, tb, 0.58)
        cr:select_font_face("JetBrainsMono Nerd Font", cairo.FontSlant.NORMAL, cairo.FontWeight.NORMAL)
        cr:set_font_size(dpi(10))
        for _, v in ipairs({100, 75, 50, 25, 0}) do
            local py = y + h * (1 - (v / 100))
            cr:move_to(x, py + dpi(3))
            cr:show_text(tostring(v))
        end
    end

    local function draw_chart(cr, w, h, big)
        local extra_info_h = big and dpi(44) or 0
        local pad_left = big and dpi(42) or dpi(12)
        local pad_right = big and dpi(16) or dpi(12)
        local pad_top = big and dpi(48) or dpi(40)
        local pad_bottom = (big and dpi(18) or dpi(12)) + extra_info_h

        local plot_x = pad_left
        local plot_y = pad_top
        local plot_w = w - pad_left - pad_right
        local plot_h = h - pad_top - pad_bottom
        local base_y = plot_y + plot_h

        draw_background(cr, w, h, big)
        draw_grid(cr, plot_x, plot_y, plot_w, plot_h, big)

        if big then
            draw_scale_labels(cr, dpi(8), plot_y, plot_h)
            draw_badge(cr, dpi(16),  dpi(10), "CPU", last.cpu, palette.cpu, true)
            draw_badge(cr, dpi(130), dpi(10), "MEM", last.mem, palette.mem, true)
            draw_badge(cr, dpi(244), dpi(10), "GPU", last.gpu, palette.gpu, true)
            draw_badge(cr, dpi(358), dpi(10), "NET", last.net, palette.net, true)
        else
            draw_badge(cr, dpi(10),  dpi(8), "CPU", last.cpu, palette.cpu, false)
            draw_badge(cr, dpi(106), dpi(8), "MEM", last.mem, palette.mem, false)
            draw_badge(cr, dpi(202), dpi(8), "GPU", last.gpu, palette.gpu, false)
            draw_badge(cr, dpi(298), dpi(8), "NET", last.net, palette.net, false)
        end

        local visible = big and expanded_samples or samples
        local function get_tail(ring)
            local all = ring:get_all()
            if #all > visible then
                local out = {}
                for i = #all - visible + 1, #all do
                    out[#out+1] = all[i]
                end
                return out
            end
            return all
        end

        local cpu_pts = build_points(get_tail(history.cpu), plot_x, plot_y, plot_w, plot_h)
        local mem_pts = build_points(get_tail(history.mem), plot_x, plot_y, plot_w, plot_h)
        local gpu_pts = build_points(get_tail(history.gpu), plot_x, plot_y, plot_w, plot_h)
        local net_pts = build_points(get_tail(history.net), plot_x, plot_y, plot_w, plot_h)

        draw_series_fill(cr, cpu_pts, base_y, palette.cpu)
        draw_series_fill(cr, mem_pts, base_y, palette.mem)
        draw_series_fill(cr, gpu_pts, base_y, palette.gpu)
        draw_series_fill(cr, net_pts, base_y, palette.net)

        draw_series_line(cr, cpu_pts, palette.cpu, big and dpi(2.8) or dpi(2.2))
        draw_series_line(cr, mem_pts, palette.mem, big and dpi(2.8) or dpi(2.2))
        draw_series_line(cr, gpu_pts, palette.gpu, big and dpi(2.8) or dpi(2.2))
        draw_series_line(cr, net_pts, palette.net, big and dpi(2.8) or dpi(2.2))

        if big then
            local mem_value = string_format("%.1f / %.1f GiB", kib_to_gib(stats.mem_used_kib), kib_to_gib(stats.mem_total_kib))
            local net_value = string_format("%s  •  %s", format_bytes_per_sec(stats.net_rate), stats.iface or "n/a")
            local gpu_value = stats.gpu_label
            local peak_value = format_bytes_per_sec(stats.net_peak)

            local pills_y = h - dpi(38)
            draw_info_pill(cr, dpi(16),  pills_y, dpi(175), "MEMORY", mem_value, palette.mem)
            draw_info_pill(cr, dpi(204), pills_y, dpi(175), "NETWORK", net_value, palette.net)
            draw_info_pill(cr, dpi(392), pills_y, dpi(175), "GPU MODE", gpu_value, palette.gpu)
            draw_info_pill(cr, dpi(580), pills_y, dpi(175), "NET PEAK", peak_value, palette.cpu)
        end
    end

    -- Widgets
    local compact_widget = wibox.widget.base.make_widget()
    compact_widget._preserve_colors = true
    function compact_widget:fit(_, _, _) return compact_width, compact_height end
    function compact_widget:draw(_, cr, w, h) draw_chart(cr, w, h, false) end

    local expanded_widget = wibox.widget.base.make_widget()
    expanded_widget._preserve_colors = true
    function expanded_widget:fit(_, _, _) return expanded_width, expanded_height end
    function expanded_widget:draw(_, cr, w, h) draw_chart(cr, w, h, true) end

    -- Popup
    local popup = awful.popup{
        screen = screen,
        ontop = true,
        visible = false,
        bg = "#00000000",
        placement = function(c) awful.placement.centered(c, { parent = screen }) end,
        widget = {
            expanded_widget,
            forced_width = expanded_width,
            forced_height = expanded_height,
            strategy = "exact",
            widget = wibox.container.constraint
        }
    }

    compact_widget:buttons(gears.table.join(
        awful.button({}, 1, function()
            popup.screen = screen or awful.screen.focused()
            popup.visible = not popup.visible
        end),
        awful.button({}, 3, function() popup.visible = false end)
    ))

    popup:buttons(gears.table.join(
        awful.button({}, 1, function() popup.visible = false end),
        awful.button({}, 3, function() popup.visible = false end)
    ))

    -- Timer principal (leve, apenas amostras de CPU, memória e rede)
    compact_widget._timer = gears.timer{
        timeout = interval,
        autostart = true,
        call_now = true,
        callback = function()
            last.cpu = clamp(sample_cpu(), 0, 100)
            last.mem = clamp(sample_mem(), 0, 100)
            last.gpu = cached_gpu   -- usa o valor cacheado da GPU
            last.net = clamp(sample_net(), 0, 100)

            history.cpu:push(last.cpu)
            history.mem:push(last.mem)
            history.gpu:push(last.gpu)
            history.net:push(last.net)

            compact_widget:emit_signal("widget::redraw_needed")
            expanded_widget:emit_signal("widget::redraw_needed")
        end
    }

    -- Timer para amostragem real da GPU (menos frequente, ex: a cada 5 segundos)
    local gpu_sample_interval = args.gpu_interval or 5
    gpu_timer = gears.timer{
        timeout = gpu_sample_interval,
        autostart = true,
        call_now = true,
        callback = function()
            cached_gpu = clamp(sample_gpu_real(), 0, 100)
            -- Atualiza o valor no histórico também (opcional, mas mantém sincronia)
        end
    }

    return compact_widget
end


--[[ GPT 

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi

-- ========================
-- 🔧 UTILS
-- ========================

local function clamp(v, min, max)
  return v < min and min or (v > max and max or v)
end

local function read_num(path)
  local f = io.open(path, "r")
  if not f then return 0 end
  local n = tonumber(f:read("*l")) or 0
  f:close()
  return n
end

-- ========================
-- ⚡ RING BUFFER (O(1))
-- ========================

local function new_ring(size)
  return {data = {}, index = 1, size = size}
end

local function push(r, v)
  r.data[r.index] = clamp(v, 0, 100)
  r.index = (r.index % r.size) + 1
end

local function values(r)
  local t = {}
  for i = 0, r.size - 1 do
    local idx = (r.index + i - 1) % r.size + 1
    t[#t+1] = r.data[idx] or 0
  end
  return t
end

-- ========================
-- 📊 SAMPLERS
-- ========================

-- CPU
local prev_total, prev_idle

local function sample_cpu()
  local f = io.open("/proc/stat")
  if not f then return 0 end
  local l = f:read("*l")
  f:close()

  local u,n,s,i,iw,irq,si,st = l:match(
    "^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(%d*)%s*(%d*)%s*(%d*)%s*(%d*)"
  )

  u,n,s,i,iw,irq,si,st =
    tonumber(u) or 0, tonumber(n) or 0, tonumber(s) or 0,
    tonumber(i) or 0, tonumber(iw) or 0,
    tonumber(irq) or 0, tonumber(si) or 0, tonumber(st) or 0

  local idle = i + iw
  local total = idle + u + n + s + irq + si + st

  if not prev_total then
    prev_total, prev_idle = total, idle
    return 0
  end

  local dt = total - prev_total
  local di = idle - prev_idle

  prev_total, prev_idle = total, idle

  if dt == 0 then return 0 end
  return ((dt - di) / dt) * 100
end

-- MEM (otimizado)
local function sample_mem(stats)
  local f = io.open("/proc/meminfo")
  if not f then return 0 end

  local total, avail

  for line in f:lines() do
    if not total then total = tonumber(line:match("MemTotal:%s+(%d+)")) end
    if not avail then avail = tonumber(line:match("MemAvailable:%s+(%d+)")) end
    if total and avail then break end
  end

  f:close()

  if not total or not avail then return 0 end

  stats.mem_total = total
  stats.mem_used = total - avail

  return ((total - avail) / total) * 100
end

-- GPU (leve)
local gpu_path = "/sys/class/drm/card0/device/gpu_busy_percent"
local gpu_mode = (io.open(gpu_path) and "sysfs") or "none"

local function sample_gpu()
  if gpu_mode == "sysfs" then
    return read_num(gpu_path)
  end
  return 0
end

-- NET (cacheado)
local iface = "eth0"
local rx_path = "/sys/class/net/"..iface.."/statistics/rx_bytes"
local tx_path = "/sys/class/net/"..iface.."/statistics/tx_bytes"

local prev_rx, prev_tx = 0, 0

local function sample_net(interval)
  local rx = read_num(rx_path)
  local tx = read_num(tx_path)

  local dr = rx - prev_rx
  local dt = tx - prev_tx

  prev_rx, prev_tx = rx, tx

  return ((dr + dt) / interval) / 1024 -- KB/s simplificado
end

-- ========================
-- 🎨 DRAW
-- ========================

local function draw_graph(cr, data, x,y,w,h)
  local step = w / (#data - 1)

  cr:set_line_width(2)

  for i=1,#data-1 do
    local v1 = data[i]
    local v2 = data[i+1]

    local x1 = x + (i-1)*step
    local x2 = x + i*step

    local y1 = y + h*(1 - v1/100)
    local y2 = y + h*(1 - v2/100)

    cr:move_to(x1,y1)
    cr:line_to(x2,y2)
  end

  cr:stroke()
end

-- ========================
-- 🧩 MAIN
-- ========================

return function(args)
  args = args or {}

  local interval = args.interval or 2
  local size = args.samples or 60

  local stats = {}

  local history = {
    cpu = new_ring(size),
    mem = new_ring(size),
    gpu = new_ring(size),
    net = new_ring(size),
  }

  local widget = wibox.widget.base.make_widget()

  function widget:fit()
    return dpi(400), dpi(120)
  end

  function widget:draw(_, cr, w, h)
    cr:set_source_rgba(0.1,0.1,0.1,0.9)
    cr:paint()

    cr:set_source_rgba(0,1,1,1)
    draw_graph(cr, values(history.cpu), 10,10,w-20,h-20)

    cr:set_source_rgba(1,0,1,1)
    draw_graph(cr, values(history.mem), 10,10,w-20,h-20)

    cr:set_source_rgba(0.5,1,0,1)
    draw_graph(cr, values(history.gpu), 10,10,w-20,h-20)

    cr:set_source_rgba(1,0.6,0,1)
    draw_graph(cr, values(history.net), 10,10,w-20,h-20)
  end

  -- ========================
  -- ⏱️ LOOP
  -- ========================

  gears.timer {
    timeout = interval,
    autostart = true,
    call_now = true,
    callback = function()
      push(history.cpu, sample_cpu())
      push(history.mem, sample_mem(stats))
      push(history.gpu, sample_gpu())
      push(history.net, sample_net(interval))

      widget:emit_signal("widget::redraw_needed")
    end
  }

  return widget
end --]]

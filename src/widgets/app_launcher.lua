---------------------------------
-- This is the app launcher widget --
---------------------------------

local awful = require("awful")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local gears = require("gears")
local gfs = require("gears.filesystem")
local wibox = require("wibox")
require("src.core.signals")

local accent = "#ff8c00"
local launcher_gif_path = gfs.get_configuration_dir() .. "src/assets/logo.gif"

-- Diretório temporário para os frames extraídos do GIF
local frames_dir = "/tmp/awesome_launcher_frames/"

local function desktop_entry_command(app_id, exec_line)
  if app_id and app_id ~= "" then
    return "gtk-launch " .. string.format("%q", app_id)
  end

  local command = exec_line or ""
  command = command:gsub("%%[fFuUdDnNickvm]", "")
  command = command:gsub("%%[cCkK]", "")
  command = command:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  if command == "" then
    return nil
  end

  return command
end

return function(s)
  -- Tamanho do botão circular — altere este único valor para redimensionar
  local SIZE = dpi(36)

  -- =========================================================
  -- Widget Cairo puro: desenha o GIF diretamente num círculo
  -- sem nenhum container, eliminando qualquer fundo retangular.
  -- =========================================================
  local launcher_widget = wibox.widget.base.make_widget()

  -- Superfície Cairo do frame atual
  local current_surface = nil

  function launcher_widget:fit(_, w, h)
    -- Ocupa exatamente SIZE×SIZE na wibar
    return math.min(w, SIZE), math.min(h, SIZE)
  end

  function launcher_widget:draw(_, cr, width, height)
    local r = math.min(width, height) / 2

    -- 1. Recorta tudo no círculo — nada fora dele é pintado
    cr:arc(r, r, r, 0, 2 * math.pi)
    cr:clip()

    if current_surface then
      local iw = current_surface:get_width()
      local ih = current_surface:get_height()

      -- Escala para cobrir todo o círculo (cover, não contain)
      local scale = math.max(width / iw, height / ih)
      local ox = (width  - iw * scale) / 2
      local oy = (height - ih * scale) / 2

      cr:translate(ox, oy)
      cr:scale(scale, scale)
      cr:set_source_surface(current_surface, 0, 0)
      cr:paint()
    else
      -- Fallback enquanto os frames carregam: círculo escuro
      cr:set_source_rgba(0.1, 0.1, 0.1, 1)
      cr:paint()
    end
  end

  launcher_widget._preserve_colors  = true
  launcher_widget._preserve_segment = true

  -- =========================================================
  -- Animação do GIF
  --
  -- Problemas resolvidos:
  --   1. LENTIDÃO NO INÍCIO: cache em disco — só extrai os frames
  --      com ImageMagick uma vez; nas próximas inicializações
  --      os PNGs já existem e são carregados diretamente.
  --
  --   2. TRAVAMENTO: surfaces são carregadas uma a uma via timer
  --      (load_timer), sem bloquear o loop principal do Lua.
  --      A animação começa assim que o 1º frame estiver pronto.
  -- =========================================================
  local gif_surfaces  = {}
  local current_frame = 1
  local frame_timer   = nil
  local load_timer    = nil

  -- Intervalo da animação em segundos (ajuste conforme o GIF original)
  local ANIM_INTERVAL = 0.06  -- ~16 fps

  local function start_animation()
    if frame_timer then frame_timer:stop() end

    frame_timer = gears.timer {
      timeout   = ANIM_INTERVAL,
      autostart = true,
      call_now  = true,
      callback  = function()
        if #gif_surfaces == 0 then return end
        current_surface = gif_surfaces[current_frame]
        current_frame   = (current_frame % #gif_surfaces) + 1
        launcher_widget:emit_signal("widget::redraw_needed")
      end
    }
  end

  -- Carrega as surfaces uma a uma sem travar o loop principal.
  local function load_surfaces_async(paths)
    local index = 1

    load_timer = gears.timer {
      timeout   = 0.001,
      autostart = true,
      call_now  = false,
      callback  = function()
        if index <= #paths then
          local surf = gears.surface.load_uncached(paths[index])
          if surf then
            gif_surfaces[#gif_surfaces + 1] = surf
          end
          -- Inicia animação assim que o primeiro frame estiver pronto
          if index == 1 and surf and not frame_timer then
            start_animation()
          end
          index = index + 1
        else
          load_timer:stop()
          load_timer = nil
        end
      end
    }
  end

  local function load_gif_frames()
    -- Verifica se os frames já estão em cache
    local check_cmd = string.format("ls %s*.png 2>/dev/null | wc -l", frames_dir)

    awful.spawn.easy_async_with_shell(check_cmd, function(stdout)
      local cached = tonumber(stdout:match("%d+")) or 0

      if cached > 0 then
        -- Cache HIT: carrega direto sem re-extrair
        local paths = {}
        for i = 0, cached - 1 do
          paths[i + 1] = string.format("%sframe_%04d.png", frames_dir, i)
        end
        load_surfaces_async(paths)
      else
        -- Cache MISS: extrai frames uma única vez
        -- Redimensiona para SIZE durante a extração (menos memória, mais rápido)
        local extract_cmd = string.format(
          "mkdir -p %s && convert -coalesce -resize %dx%d^ %s %sframe_%%04d.png 2>/dev/null; ls %s*.png 2>/dev/null | wc -l",
          frames_dir, dpi(36), dpi(36), launcher_gif_path, frames_dir, frames_dir
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
            -- Fallback: sem ImageMagick instalado
            local surf = gears.surface.load_uncached(launcher_gif_path)
            if surf then
              gif_surfaces = { surf }
              start_animation()
            end
          end
        end)
      end
    end)
  end

  load_gif_frames()

  -- =========================================================
  -- Popup de aplicativos (inalterado em lógica, apenas mantido)
  -- =========================================================
  local app_list = wibox.widget {
    spacing = dpi(8),
    layout  = wibox.layout.fixed.vertical
  }

  local app_scroll = wibox.widget {
    app_list,
    forced_height = dpi(320),
    widget        = wibox.container.scroll.vertical
  }

  local popup = awful.popup {
    screen       = s,
    visible      = false,
    ontop        = true,
    bg           = "#111111ee",
    border_color = accent,
    border_width = dpi(1),
    shape        = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 14)
    end,
    placement = function(c)
      awful.placement.top_left(c, { margins = { top = dpi(54), left = dpi(14) } })
    end,
    widget = {
      {
        {
          {
            markup = '<span foreground="' .. accent .. '"><b>Aplicativos</b></span>',
            widget = wibox.widget.textbox
          },
          {
            markup = '<span foreground="#a3a3a3">Programas instalados no Ubuntu</span>',
            widget = wibox.widget.textbox
          },
          {
            app_scroll,
            top    = dpi(12),
            widget = wibox.container.margin
          },
          spacing = dpi(8),
          layout  = wibox.layout.fixed.vertical
        },
        margins = dpi(14),
        widget  = wibox.container.margin
      },
      forced_width = dpi(300),
      widget       = wibox.container.constraint
    }
  }

  local function build_app_item(app_name, command)
    local row = wibox.widget {
      {
        {
          markup = '<span foreground="#f5f5f5">' .. gears.string.xml_escape(app_name) .. '</span>',
          widget = wibox.widget.textbox
        },
        left   = dpi(10),
        right  = dpi(10),
        top    = dpi(8),
        bottom = dpi(8),
        widget = wibox.container.margin
      },
      bg    = "#1a1a1a",
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 10)
      end,
      widget = wibox.container.background
    }

    Hover_signal(row, "#1a1a1a", accent)

    row:buttons(gears.table.join(
      awful.button({}, 1, function()
        popup.visible = false
        awful.spawn.with_shell(command)
      end)
    ))

    return row
  end

  local function set_loading_state(message)
    app_list:reset()
    app_list:add(wibox.widget {
      markup = '<span foreground="#a3a3a3">' .. gears.string.xml_escape(message) .. '</span>',
      widget = wibox.widget.textbox
    })
  end

  local function refresh_applications()
    set_loading_state("Carregando aplicativos...")

    awful.spawn.easy_async_with_shell([[
python3 - <<'PY'
from pathlib import Path
import configparser

paths = [Path('/usr/share/applications'), Path.home() / '.local/share/applications']
entries = []
seen = set()

for root in paths:
    if not root.exists():
        continue
    for desktop_file in sorted(root.glob('*.desktop')):
        app_id = desktop_file.name
        if app_id in seen:
            continue
        seen.add(app_id)
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            parser.read(desktop_file, encoding='utf-8')
        except Exception:
            continue
        if 'Desktop Entry' not in parser:
            continue
        entry = parser['Desktop Entry']
        if entry.get('Type') != 'Application':
            continue
        if entry.get('NoDisplay', 'false').lower() == 'true':
            continue
        if entry.get('Hidden', 'false').lower() == 'true':
            continue
        name = entry.get('Name', '').strip()
        exec_line = entry.get('Exec', '').strip()
        if not name or not exec_line:
            continue
        entries.append((name.lower(), name, app_id, exec_line))

for _, name, app_id, exec_line in sorted(entries):
    safe_name = name.replace('\t', ' ').replace('\n', ' ')
    safe_exec = exec_line.replace('\t', ' ').replace('\n', ' ')
    print(f"{safe_name}\t{app_id}\t{safe_exec}")
PY]],
      function(stdout)
        app_list:reset()

        local found_any = false
        for line in stdout:gmatch('[^\r\n]+') do
          local app_name, app_id, exec_line = line:match('^(.-)\t(.-)\t(.*)$')
          if app_name and app_id and exec_line then
            local command = desktop_entry_command(app_id, exec_line)
            if command then
              app_list:add(build_app_item(app_name, command))
              found_any = true
            end
          end
        end

        if not found_any then
          set_loading_state('Nenhum aplicativo encontrado.')
        end
      end
    )
  end

  launcher_widget:buttons(awful.util.table.join(
    awful.button({}, 1, function()
      popup.visible = not popup.visible
      if popup.visible then
        refresh_applications()
      end
    end)
  ))

  return launcher_widget
end


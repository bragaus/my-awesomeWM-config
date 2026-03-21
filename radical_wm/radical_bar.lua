--------------------------------------------------------------------------------------------------------------
-- This is the statusbar, every widget, module and so on is combined to all the stuff you see on the screen --
--------------------------------------------------------------------------------------------------------------

local awful = require("awful")
local color = require("src.theme.colors")
local dpi = require("beautiful").xresources.apply_dpi
local gears = require("gears")
local wibox = require("wibox")

return function(s, widgets_top, widgets_bottom)
  widgets_top = widgets_top or {}
  widgets_bottom = widgets_bottom or {}
  local top_left = awful.popup {
    screen = s,
    widget = wibox.container.background,
    ontop = false,
    bg = "#00000000",
    visible = true,
    maximum_width = dpi(980),
    placement = function(c)
      awful.placement.top_left(c, {
        margins = { top = dpi(10), left = dpi(10) }
      })
    end,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, dpi(4))
    end
  }

  local top_first = awful.popup {
    screen = s,
    widget = wibox.container.background,
    ontop = false,
    bg = "#00000000",
    visible = true,
    maximum_width = dpi(980),
    placement = function(c)
      awful.placement.top_left(c, {
        margins = { top = dpi(70), left = dpi(10) }
      })
    end,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, dpi(4))
    end
  }

  top_left:struts {
    top = 55
  }

  top_first:struts {
    top = 100
  }

  local segment_palette = {
    "#2b0c45",
    "#4c1d95",
    "#5b21b6",
    "#6d28d9"
  }

  local function segment_bg_for(index)
    return segment_palette[((index - 1) % #segment_palette) + 1]
  end

  local function normalize_widget_colors(widget)
    if widget._preserve_colors then
      return
    end

    local function tint_one(w)
      if w._preserve_colors then
        return
      end

      if w.bg ~= nil then
        w.bg = "#00000000"
      end

      if w.fg ~= nil then
        w.fg = "#ff8c00"
      end

      if w.set_image and w.get_image then
        local img = w:get_image()
        if img then
          w:set_image(gears.color.recolor_image(img, "#ff8c00"))
        end
      end
    end

    tint_one(widget)

    if widget.get_all_children then
      for _, child in ipairs(widget:get_all_children()) do
        tint_one(child)
      end
    end
  end

  local function create_powerline_segment(widget, index)
    local current_bg = segment_bg_for(index)

    normalize_widget_colors(widget)

    if widget._preserve_segment then
      return wibox.widget {
        widget,
        layout = wibox.layout.fixed.horizontal
      }
    end

    return wibox.widget {
      {
        {
          widget,
          left = dpi(10),
          right = dpi(10),
          top = dpi(4),
          bottom = dpi(4),
          widget = wibox.container.margin
        },
        bg = current_bg,
        widget = wibox.container.background
      },
      {
        {
          text = "",
          align = "center",
          valign = "center",
          font = "JetBrainsMono Nerd Font, ExtraBold 30",
          widget = wibox.widget.textbox
        },
        fg = current_bg,
        bg = "#00000000",
        forced_width = dpi(26),
        widget = wibox.container.background
      },
      layout = wibox.layout.fixed.horizontal
    }
  end

  local function prepare_widgets(widget_list)
    local layout = wibox.layout.fixed.horizontal()
    layout.spacing = -dpi(18)

    for i, widget in ipairs(widget_list) do
      layout:add(create_powerline_segment(widget, i))
    end

    return wibox.widget {
      layout,
      forced_height = dpi(48),
      widget = wibox.container.constraint
    }
  end

  top_left:setup {
    prepare_widgets(widgets_top),
    layout = wibox.layout.fixed.horizontal
  }

  top_first:setup {
    prepare_widgets(widgets_bottom),
    layout = wibox.layout.fixed.horizontal
  }
end

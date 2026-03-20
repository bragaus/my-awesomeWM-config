--------------------------------------------------------------------------------------------------------------
-- This is the statusbar, every widget, module and so on is combined to all the stuff you see on the screen --
--------------------------------------------------------------------------------------------------------------
-- Awesome Libs
local awful = require("awful")
local color = require("src.theme.colors")
local dpi = require("beautiful").xresources.apply_dpi
local gears = require("gears")
local wibox = require("wibox")

return function(s, widgets)

  local top_right = awful.popup {
    screen = s,
    widget = wibox.container.background,
    ontop = false,
    bg = "#00000000",
    visible = true,
    placement = function(c) awful.placement.top_right(c, { margins = dpi(10) }) end,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 4)
    end
  }

  top_right:struts {
    top = 55
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
    local function tint_one(w)
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

    return wibox.widget {
      {
        {
          text = "",
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
      forced_height = 48,
      widget = wibox.container.constraint
    }
  end

  top_right:setup {
    nil,
    nil,
    prepare_widgets(widgets),
    layout = wibox.layout.align.horizontal
  }
end


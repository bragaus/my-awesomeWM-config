----------------------------------
-- This is the layoutbox widget --
----------------------------------

-- Awesome Libs
local awful = require("awful")
local dpi = require("beautiful").xresources.apply_dpi
local gears = require("gears")
local wibox = require("wibox")
local gfs = require("gears.filesystem")
require("src.core.signals")

local cyber_orange = "#ff8c00"

-- Returns the layoutbox widget
return function(s)
  local layout_icon = wibox.widget {
    resize = true,
    widget = wibox.widget.imagebox
  }

  local layout = wibox.widget {
    {
      {
        layout_icon,
        id = "icon_layout",
        widget = wibox.container.place
      },
      id = "icon_margin",
      left = dpi(5),
      right = dpi(5),
      forced_width = dpi(40),
      widget = wibox.container.margin
    },
    bg = "#4c1d95",
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 5)
    end,
    widget = wibox.container.background,
    screen = s
  }

  local layout_icon_map = {
    floating = "floating.svg",
    tile = "tile.svg",
    fairh = "fairh.svg",
    fairv = "fairv.svg",
    fullscreen = "fullscreen.svg",
    max = "max.svg",
    cornerne = "cornerne.svg",
    cornernw = "cornernw.svg",
    cornerse = "cornerse.svg",
    cornersw = "cornersw.svg",
    dwindle = "dwindle.svg"
  }

  local function update_layout_icon()
    local current_layout = awful.layout.get(s)
    local layout_name = awful.layout.getname(current_layout)
    local icon_file = layout_icon_map[layout_name]

    if icon_file then
      local icon_path = gfs.get_configuration_dir() .. "src/assets/layout/" .. icon_file
      layout_icon:set_image(gears.color.recolor_image(icon_path, cyber_orange))
    end
  end

  -- Signals
  Hover_signal(layout, "#6d28d9", cyber_orange)

  layout:connect_signal(
    "button::press",
    function()
      awful.layout.inc(-1, s)
      update_layout_icon()
    end
  )

  tag.connect_signal(
    "property::layout",
    function(t)
      if t.screen == s and t.selected then
        update_layout_icon()
      end
    end
  )

  update_layout_icon()

  return layout
end


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
--[[ humildade nao e pensar menos de si, [e pensar menos em sim e mais no outro
-- DEUS NAO MUDA NADA QUE VC TOLERA! 
--
-- Aprenda a ser fiel no pouco e eu te sobre muito
--
-- ]]

  local top_first = awful.popup {
    screen = s,
    widget = wibox.container.background,
    ontop = false,
    bg = "#00000000",
    visible = true,
    maximum_width = dpi(980),
    placement = function(c) awful.placement.top_left(c, { margins = dpi(10) }) end,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 4)
    end
  }
  
  --[[ areas de trabalho vai ficar na esquerda ]]--
  local top_left = awful.popup {
    screen = s,
    widget = wibox.container.background,
    ontop = false,
    bg = "#00000000",
    visible = true,
    maximum_width = dpi(980),
    placement = function(c) awful.placement.top_left(c, { margins = dpi(10) }) end,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, 4)
    end
  }

  local naughty = require("naughty")
local gdebug = require("gears.debug")

--naughty.notify({
--    title = "Widget debug",
 --   text = gdebug.dump_return(top_first),
 --   timeout = 0
--})

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

--[[naughty.notify({
    title = "Widget debug",
    text = gdebug.dump_return(index),
    timeout = 0
})--]]
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
    --[[naughty.notify({
      title = "Index",
      text = gdebug.dump_return(index),
      timeout = 0
    })--]]

    local current_bg = segment_bg_for(index)
    
    --[[naughty.notify({
      title = "Current bg",
      text = gdebug.dump_return(current_bg),
      timeout = 0
    })--]]


    normalize_widget_colors(widget)

    local myWibox = wibox.widget {
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


   --[[ naughty.notify({
      title = "MyWibox",
      text = gdebug.dump_return(myWibox),
      timeout = 0
    })--]]

    return myWibox
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

  top_left:setup {
    prepare_widgets(widgets),
    nil,
    nil,
    layout = wibox.layout.fixed.horizontal
  }
end

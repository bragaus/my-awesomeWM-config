--------------------------------------------------------------------------------------------------------------
-- This is the statusbar, every widget, module and so on is combined to all the stuff you see on the screen --
--------------------------------------------------------------------------------------------------------------
-- Awesome Libs
local awful = require("awful")
local dpi = require("beautiful").xresources.apply_dpi

awful.screen.connect_for_each_screen(
-- For each screen this function is called once
-- If you want to change the modules per screen use the indices
-- e.g. 1 would be the primary screen and 2 the secondary screen.
  function(s)
  -- Create 9 tags
  awful.layout.layouts = user_vars.layouts
  awful.tag(
    { "PLANO-WEB3", "VIBE-STUDING", "GHOST-SIGN", "NEW-ICHIMOKU" },
    s,
    user_vars.layouts[12]
  )
--[[ uma das coisas mais tristes na vida e chegar ao fim e olhar oara traz com remorso, sabendo que voce poderia teer sido feito e tido muito mais --]]
  require("src.modules.powermenu")(s)
  -- TODO: rewrite calendar osd, maybe write an own inplementation
  -- require("src.modules.calendar_osd")(s)
  require("src.modules.volume_osd")(s)
  require("src.modules.brightness_osd")(s)
  require("src.modules.titlebar")
  require("src.modules.volume_controller")(s)

  -- Widgets
  --s.battery = require("src.widgets.battery")()
  --s.audio = require("src.widgets.audio")(s)
  --s.date = require("src.widgets.date")()
  --s.clock = require("src.widgets.clock")()
  --s.bluetooth = require("src.widgets.bluetooth")()
  s.layoutlist = require("src.widgets.layout_list")(s)
  --s.powerbutton = require("src.widgets.power")()
  --s.kblayout = require("src.widgets.kblayout")(s)
  s.taglist = require("src.widgets.taglist")(s)
  --[[nem sempre o processo tem a ver com a promessa, mas acredite voce esta crescendo e tudo esta cooperando para o seu bem --]]
  --s.tasklist = require("src.widgets.tasklist")(s)
  --s.cpu_freq = require("src.widgets.cpu_info")("freq", "average")

  -- Add more of these if statements if you want to change
  -- the modules/widgets per screen.
  if s.index == 1 then
    s.cpu_usage = require("src.widgets.cpu_info")("usage")
    s.cpu_temp = require("src.widgets.cpu_info")("temp")
    s.gpu_usage = require("src.widgets.gpu_info")("usage")
    --s.gpu_temp = require("src.widgets.gpu_info")("temp")
    s.tasklist = require("src.widgets.tasklist")(s)

    require("radical_wm.left_bar")(s, { s.layoutlist }) --s.systray, s.taglist })
    require("radical_wm.center_bar")(s, { s.tasklist })
    --require("crylia_bar.right_bar")(s, { s.gpu_usage, s.gpu_temp, s.cpu_usage, s.cpu_temp, s.audio, s.kblayout, s.date, s.clock, s.powerbutton })
    --require("crylia_bar.dock")(s, user_vars.dock_programs)

  end

  if s.index == 2 then

s.cyber_chart = require("src.widgets.system_monitor_chart") {
  width = dpi(320),
  height = dpi(96),
  interval = 1,
  samples = 42,
  radius = dpi(10),
  palette = {
    cpu = "#00F6FF",
    mem = "#FF00F5",
    gpu = "#8BFF00",
    net = "#FF9F1C",
    grid = "#5A2A82",
    text = "#E8D9FF",
    overlay = "#0B0714"
  }
}

    s.tasklist = require("src.widgets.tasklist")(s)
    s.network = require("src.widgets.network")()
    s.ram_info = require("src.widgets.ram_info")()
    s.audio = require("src.widgets.audio")(s)
    s.kblayout = require("src.widgets.kblayout")(s)
    s.date = require("src.widgets.date")()
    s.clock = require("src.widgets.clock")()
    s.powerbutton = require("src.widgets.power")()
    s.layoutlist = require("src.widgets.layout_list")(s)
    s.cpu_usage = require("src.widgets.cpu_info")("usage")
    s.cpu_temp = require("src.widgets.cpu_info")("temp")
    s.gpu_usage = require("src.widgets.gpu_info")("usage")
    s.app_launcher = require("src.widgets.app_launcher")(s)
    --s.systray = require("src.widgets.systray")(s)


   -- s.battery = require("src.widgets.battery")()
   -- require("crylia_bar.center_bar")(s, { s.systray })
   -- require("crylia_bar.first_bar")(s { s.app_launcher })
   -- require("radical_wm.left_bar")(s, { s.layoutlist, s.taglist })
    require("radical_wm.radical_bar")(s, { s.layoutlist, s.tasklist, s.taglist }, { s.app_launcher })
    require("radical_wm.center_bar")(s, { s.cyber_chart })
    require("radical_wm.right_bar")(s, { s.cpu_usage, s.gpu_usage, s.ram_info, s.network, s.audio, s.kblayout, s.date, s.clock, s.powerbutton })
    require("radical_wm.dock")(s, user_vars.dock_programs)
  end
end
)

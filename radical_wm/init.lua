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
s.cyber_chart = require("src.widgets.system_monitor_chart") {
  width = dpi(1180),
  height = dpi(720),
  interval = 1,
  samples = 42,
  radius = dpi(18),
  palette = {
    accent = "#ff7a00",
    cpu = "#ff9a1f",
    mem = "#9c63ff",
    gpu = "#62b9ff",
    net = "#55ffd7",
    grid = "#ff7a00",
    text = "#fff4e8",
    overlay = "#120d22",
    glow = "#8d72ff"
  }
}


    s.cpu_usage = require("src.widgets.cpu_info")("usage")
    s.cpu_temp = require("src.widgets.cpu_info")("temp")
    s.gpu_usage = require("src.widgets.gpu_info")("usage")
    --s.gpu_temp = require("src.widgets.gpu_info")("temp")
    s.tasklist = require("src.widgets.tasklist")(s)

    require("radical_wm.left_bar")(s, { s.layoutlist }) --s.systray, s.taglist })
    require("radical_wm.center_bar")(s, { s.tasklist })
    --require("crylia_bar.right_bar")(s, { s.gpu_usage, s.gpu_temp, s.cpu_usage, s.cpu_temp, s.audio, s.kblayout, s.date, s.clock, s.powerbutton })
    require("radical_wm.center_bar")(s, { s.cyber_chart })
    --require("crylia_bar.dock")(s, user_vars.dock_programs)

  end

  if s.index == 2 then

s.cyber_chart = require("src.widgets.system_monitor_chart") {
  width = dpi(1180),
  height = dpi(720),
  interval = 1,
  samples = 42,
  radius = dpi(18),
  palette = {
    accent = "#ff7a00",
    cpu = "#ff9a1f",
    mem = "#9c63ff",
    gpu = "#62b9ff",
    net = "#55ffd7",
    grid = "#ff7a00",
    text = "#fff4e8",
    overlay = "#120d22",
    glow = "#8d72ff"
  }
}

    s.tasklist = require("src.widgets.tasklist")(s)
    s.kblayout = require("src.widgets.kblayout")(s)
    s.powerbutton = require("src.widgets.power")()
    s.layoutlist = require("src.widgets.layout_list")(s)
    s.app_launcher = require("src.widgets.app_launcher")(s)
    s.clock_br = require("src.widgets.world_clock") { city = "BRASIL", timezone = "America/Sao_Paulo", country = "br", width = dpi(84), segment_bg = "#1f8f52" }
    s.clock_fr = require("src.widgets.world_clock") { city = "FRANCA", timezone = "Europe/Paris", country = "fr", width = dpi(84), segment_bg = "#191338" }
    s.clock_jp = require("src.widgets.world_clock") { city = "JAPAO", timezone = "Asia/Tokyo", country = "jp", width = dpi(84), segment_bg = "#C24347" }
    s.clock_us = require("src.widgets.world_clock") { city = "EUA", timezone = "America/New_York", country = "us", width = dpi(84), segment_bg = "#1E588D" }
    --s.systray = require("src.widgets.systray")(s)


   -- s.battery = require("src.widgets.battery")()
   -- require("crylia_bar.center_bar")(s, { s.systray })
   -- require("crylia_bar.first_bar")(s { s.app_launcher })
    -- require("radical_wm.left_bar")(s, { s.layoutlist, s.taglist })
    require("radical_wm.radical_bar")(s, { s.layoutlist, s.tasklist, s.taglist }, { s.app_launcher })
    require("radical_wm.center_bar")(s, { s.cyber_chart })
    require("radical_wm.right_bar")(s, { s.clock_br, s.clock_fr, s.clock_jp, s.clock_us, s.powerbutton })
    require("radical_wm.dock")(s, user_vars.dock_programs)
  end
end
)

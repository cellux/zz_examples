local M = {}

local sched = require('sched')
local ui = require('ui')
local fs = require('fs')
local sdl = require('sdl2')
local util = require('util')
local time = require('time')

function M.main()
   local ui = ui {
      gl_profile = 'core',
      gl_version = '3.0',
      title = "texture",
      fullscreen_desktop = true,
      quit_on_escape = true,
   }
   local texture = ui:Texture { width = 256, height = 256 }
   texture:clear(Color(255,255,0,255))
   local blitter = ui:TextureBlitter()
   ui:show()
   ui:layout()
   local loop = ui:RenderLoop {
      frame_time = 0,
      measure = true,
   }
   function loop:clear()
      ui:clear(Color(64,0,0))
   end
   function loop:draw()
      local x = (ui.rect.w - texture.width) / 2 + 100 * math.sin(sched.now*2)
      local y = (ui.rect.h - texture.height) / 2 + 100 * math.cos(sched.now*2.5)
      local dst_rect = Rect(x, y, texture.width, texture.height)
      blitter:blit(texture, dst_rect)
   end
   sched(loop)
end

return M

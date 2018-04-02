local M = {}

local ui = require('ui')
local vfs = require('vfs')
local sched = require('sched')

function M.main()
   local ui = ui {
      title = "chargrid",
      fullscreen_desktop = true,
      quit_on_escape = true,
   }

   local font_size = 12 -- initial font size in points
   local font = ui:Font {
      source = vfs.readfile("DroidSansMono.ttf"),
      size = font_size
   }

   local grid = ui:Grid { font = font }

   local packer = ui:HBox()
   packer:add(grid)
   packer:add(ui:Spacer())
   local palette_display = ui:Quad {
      texture = grid.palette.texture,
   }
   packer:add(palette_display)
   local font_display = ui:Quad {
      texture = function() return font.atlas.texture end,
   }
   packer:add(font_display)
   ui:add(packer)
   ui:show()
   ui:layout()

   grid:write(0,0, "Hello, world! www")
   grid:write(1,1, "Hello, Mikey!")
   grid:bg(1)
   grid:write(2,2, "ÁRVÍZTŰRŐ TÜKÖRFÚRÓGÉP")

   local loop = ui:RenderLoop { measure = true }
   sched(loop)
   sched.wait('quit')
end

return M

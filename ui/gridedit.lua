local M = {}

local ui = require('ui')
local fs = require('fs')
local vfs = require('vfs')
local sched = require('sched')

function M.main()
   pf("arg: %s", require('inspect')(_G.arg))
   local ui = ui {
      title = "gridedit",
      fullscreen_desktop = true,
      quit_on_escape = true,
   }

   local file_path = arg[1]
   if not file_path then
      ef("Usage: %s <path>", arg[0])
   end
   local text = ''
   if fs.exists(file_path) then
      text = tostring(fs.readfile(file_path))
   end

   local font_size = 12 -- initial font size in points
   local font = ui:Font {
      source = vfs.readfile("DroidSansMono.ttf"),
      size = font_size
   }
   local grid = ui:Grid { font = font }
   local editor = grid:TextEdit()
   editor:text(text)
   grid:add(editor)
   ui:add(grid)
   ui:show()
   ui:layout()

   local keymapper = ui:KeyMapper()
   keymapper:push(editor.default_keymap)

   local loop = ui:RenderLoop { measure = true }
   sched(loop)
   sched.wait('quit')
end

return M

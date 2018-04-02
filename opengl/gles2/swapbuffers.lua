local M = {}

local sched = require('sched')
local ui = require('ui')
local gl = require('gl')
local sdl = require('sdl2')

-- in another program I experienced strange behavior: the sequence of
-- glSwapBuffers() calls made the backbuffer visible only after 3 or 4
-- swaps
--
-- this is supposed to test whether glSwapBuffers() immediately brings
-- the backbuffer to the front (making it visible)

local colors = {
   { 0,0,0 },
   { 0,0,1 },
   { 0,1,0 },
   { 0,1,1 },
   { 1,0,0 },
   { 1,0,1 },
   { 1,1,0 },
   { 1,1,1 },
}

function M.main()
   local window = ui.Window {
      title = "swapbuffers",
      gl_profile = 'es',
      gl_version = '2.0',
      quit_on_escape = true,
   }
   window:show()
   local index = 0
   local function next_color()
      index = index + 1
      if index > #colors then
         index = 1
      end
      local r = colors[index][1]
      local g = colors[index][2]
      local b = colors[index][3]
      gl.ClearColor(r,g,b,1)
      pf("glClearColor(%d,%d,%d,1)", r, g, b)
      gl.Clear(gl.GL_COLOR_BUFFER_BIT)
      pf("glClear(GL_COLOR_BUFFER_BIT)")
      window.window:GL_SwapWindow()
      pf("glSwapWindow()")
      local gl_error = gl.GetError()
      if gl_error ~= gl.GL_NO_ERROR then
         ef("GL error: %d", gl_error)
      end
   end
   local function keydown_handler(evdata)
      if evdata.key.keysym.sym == sdl.SDLK_SPACE then
         next_color()
      end
   end
   sched.on('sdl.keydown', keydown_handler)
   pf("press any key to clear the backbuffer and call glSwapWindow(), ESC to exit")
   sched.wait('quit')
end

return M

local M = {}

local ffi = require('ffi')
local sdl = require('sdl2')
local bit = require('bit')
local sched = require('sched')

function M.main()
   pf("SDL version: %d.%d.%d", sdl.GetVersion())
   pf("Running on platform '%s'", sdl.GetPlatform())
   pf("Amount of RAM configured in the system: %d MB", sdl.GetSystemRAM())
   pf("Number of available CPU cores: %d", sdl.GetCPUCount())
   local n_displays = sdl.GetNumVideoDisplays()
   pf("Number of video displays: %d", n_displays)
   for d=1,n_displays do
      pf("Display #%d:", d)
      pf("  Name: %s", sdl.GetDisplayName(d))
      local bounds = sdl.GetDisplayBounds(d)
      pf("  Bounds: %s", bounds)
      local n_displaymodes = sdl.GetNumDisplayModes(d)
      pf("  Number of display modes: %d", n_displaymodes)
      for m=1,n_displaymodes do
         local mode = sdl.GetDisplayMode(d,m)
         pf("    #%d: %s", m, mode)
      end
      pf("  Desktop display mode: %s", sdl.GetDesktopDisplayMode(d))
      pf("  Current display mode: %s", sdl.GetCurrentDisplayMode(d))
   end
   print("Creating SDL window...")
   local w = sdl.CreateWindow("hello", 0, 0, 800, 600,
                              bit.bor(sdl.SDL_WINDOW_OPENGL,
                                      sdl.SDL_WINDOW_RESIZABLE))
   w:ShowWindow()
   pf("Screen DPI: %dx%d", w:dpi())
   print("To quit the example app, press Escape while the SDL window has keyboard focus or simply close the window")
   sched.on('sdl.keydown', function(evdata)
      pf("got sdl.keydown event, keysym=%s", evdata.key.keysym.sym)
      if evdata.key.keysym.sym == sdl.SDLK_ESCAPE then
         sched.quit()
      end
   end)
   sched.on('sdl.textinput', function(evdata)
      local text = ffi.string(evdata.text.text)
      pf("got sdl.textinput event, text=%s, length=%d", text, #text)
   end)
   sched.on('sdl.quit', sched.quit)
   local fps = w:GetWindowDisplayMode().refresh_rate
   pf("Window refresh rate: %d", fps)
   if fps == 0 then
      fps = 60
   end
   sched(function()
      -- a primitive render loop
      while sched.running() do
         now = sched.now
         -- we should redraw the screen here
         sched.wait(now+1/fps)
      end
   end)
   sched.wait('quit')
   print("got quit signal, destroying window")
   w:DestroyWindow()
end

return M

local M = {}

local egl = require('egl')
local gl = require('gl')
local sdl = require('sdl2')
local sched = require('sched')
local time = require('time')

function M.main()
   local dpy = egl.GetDisplay()
   local major, minor = dpy:Initialize()
   pf("EGL version: %d.%d", major, minor)
   local config = dpy:ChooseConfig {
      surface_type = egl.EGL_WINDOW_BIT,
      renderable_type = egl.EGL_OPENGL_ES2_BIT,
   }
   if not config then
      pf("No suitable EGLConfig found.")
   else
      pf("EGLConfig attributes:")
      local function gca(attribute)
         return dpy:GetConfigAttrib(config, attribute)
      end
      pf("  CONFIG_ID: %d", gca(egl.EGL_CONFIG_ID))
      pf("  BUFFER_SIZE: %d", gca(egl.EGL_BUFFER_SIZE))
      pf("  ALPHA_SIZE: %d", gca(egl.EGL_ALPHA_SIZE))
      pf("  BLUE_SIZE: %d", gca(egl.EGL_BLUE_SIZE))
      pf("  GREEN_SIZE: %d", gca(egl.EGL_GREEN_SIZE))
      pf("  RED_SIZE: %d", gca(egl.EGL_RED_SIZE))
      pf("  DEPTH_SIZE: %d", gca(egl.EGL_DEPTH_SIZE))
      pf("  STENCIL_SIZE: %d", gca(egl.EGL_STENCIL_SIZE))
      pf("  SURFACE_TYPE: %04x", gca(egl.EGL_SURFACE_TYPE))
      pf("  MIN_SWAP_INTERVAL: %d", gca(egl.EGL_MIN_SWAP_INTERVAL))
      pf("  MAX_SWAP_INTERVAL: %d", gca(egl.EGL_MAX_SWAP_INTERVAL))
      pf("  RENDERABLE_TYPE: %04x", gca(egl.EGL_RENDERABLE_TYPE))
      
      -- create an SDL window and then create an EGLSurface on it
      
      sdl.GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK,
                          sdl.SDL_GL_CONTEXT_PROFILE_ES)
      sdl.GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 2)
      sdl.GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 0)
      local win = sdl.CreateWindow("EGL window",          -- title
                                   -1, -1,                -- x,y
                                   nil, nil,              -- w,h
                                   sdl.SDL_WINDOW_OPENGL) -- flags
      local wminfo = win:GetWindowWMInfo()
      local attrib_list = egl.attrib_list {
         render_buffer = egl.EGL_SINGLE_BUFFER,
      }
      local surface = dpy:CreateWindowSurface(config,
                                              wminfo.info.x11.window,
                                              attrib_list)
      if surface:QuerySurface(egl.EGL_RENDER_BUFFER) ~= egl.EGL_SINGLE_BUFFER then
         ef("surface does not support single-buffer rendering")
      end
      pf("Surface attributes:")
      local function qs(attribute)
         return surface:QuerySurface(attribute)
      end
      pf("  WIDTH: %d", qs(egl.EGL_WIDTH))
      pf("  HEIGHT: %d", qs(egl.EGL_HEIGHT))
      pf("  HORIZONTAL_RESOLUTION: %d", qs(egl.EGL_HORIZONTAL_RESOLUTION))
      pf("  VERTICAL_RESOLUTION: %d", qs(egl.EGL_VERTICAL_RESOLUTION))
      pf("  SWAP_BEHAVIOR: %04x", qs(egl.EGL_SWAP_BEHAVIOR))
      egl.BindAPI(egl.EGL_OPENGL_ES_API)
      local attrib_list = egl.attrib_list {
         context_client_version = 2,
      }
      local ctx = dpy:CreateContext(config, nil, attrib_list)
      ctx:MakeCurrent(surface, surface)
      sched(function()
         while true do
            local t = time.time()
            local r = 0.5 + 0.5*math.sin(t)
            local g = 0.5 + 0.5*math.sin(t*1.33)
            local b = 0.5 + 0.5*math.sin(t*0.97)
            gl.glClearColor(r,g,b,1)
            gl.glClear(gl.GL_COLOR_BUFFER_BIT)
            surface:SwapBuffers()
            sched.sleep(0.1)
         end
      end)
      sched.on('sdl.keydown', function(evdata)
         if evdata.key.keysym.sym == sdl.SDLK_ESCAPE then
            sched.quit()
         end
      end)
      sched.on('sdl.quit', sched.quit)
      sched.wait('quit')
      ctx:DestroyContext()
      surface:DestroySurface()
      win:DestroyWindow()
   end
   dpy:Terminate()
end

return M

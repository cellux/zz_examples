local M = {}

local ffi = require('ffi')
local sdl = require('sdl2')
local gl = require('gl')
local sched = require('sched')

local function getinfo()
   local w = sdl.CreateWindow("glinfo", -1, -1, nil, nil,
                              bit.bor(sdl.SDL_WINDOW_OPENGL,
                                      sdl.SDL_WINDOW_HIDDEN))
   -- glGetString() returns valid information only after an OpenGL
   -- context has been created, hence the hidden SDL window
   local ctx = w:GL_CreateContext()
   local function p(name)
      pf("%s: %s", name, gl.GetString(gl[name]))
   end
   p("GL_VENDOR")
   p("GL_RENDERER")
   p("GL_VERSION")
   p("GL_EXTENSIONS")
   p("GL_SHADING_LANGUAGE_VERSION")
   ctx:GL_DeleteContext()
   w:DestroyWindow()
end

function M.main()
   pf("\n--- trying to create a plain OpenGL context ---")
   getinfo()

   pf("\n--- trying to create an OpenGL ES 2.0 context ---")
   sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK,
                           sdl.SDL_GL_CONTEXT_PROFILE_ES)
   sdl.GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 2)
   sdl.GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 0)
   getinfo()
end

return M

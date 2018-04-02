local M = {}

local ui = require('ui')
local gl = require('gl')
local ffi = require('ffi')
local sched = require('sched')

function M.main()
   local window = ui.Window {
      title = "shader-vbo1",
      gl_profile = 'es',
      gl_version = '2.0',
      quit_on_escape = true,
   }

   local FS = ffi.sizeof("GLfloat")

   local vertex_shader = gl.CreateShader(gl.GL_VERTEX_SHADER)
   vertex_shader:ShaderSource [[
      #version 100
      attribute vec4 vposition;
      attribute vec4 vcolor;
      varying lowp vec4 fcolor;
      void main() {
        fcolor = vcolor;
        gl_Position = vposition;
      }
   ]]
   vertex_shader:CompileShader()

   local fragment_shader = gl.CreateShader(gl.GL_FRAGMENT_SHADER)
   fragment_shader:ShaderSource [[
      #version 100
      varying lowp vec4 fcolor;
      void main() {
         gl_FragColor = fcolor;
      }
   ]]
   fragment_shader:CompileShader()

   local shader_program = gl.CreateProgram()
   shader_program:AttachShader(vertex_shader)
   shader_program:AttachShader(fragment_shader)
   shader_program:BindAttribLocation(0, "vposition")
   shader_program:BindAttribLocation(1, "vcolor")
   --shader_program:BindFragDataLocation(0, "gl_FragColor")
   shader_program:LinkProgram()

   local vao = gl.VertexArray()
   gl.BindVertexArray(vao)
   local vbo = gl.Buffer()
   gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)
   local vertex_data = gl.FloatArray {
   --   X    Y    Z          R    G    B
       1.0, 1.0, 0.0,       1.0, 0.0, 0.0, -- vertex 0
      -1.0, 1.0, 0.0,       0.0, 1.0, 0.0, -- vertex 1
       1.0,-1.0, 0.0,       0.0, 0.0, 1.0, -- vertex 2
       1.0,-1.0, 0.0,       0.0, 0.0, 1.0, -- vertex 3
      -1.0, 1.0, 0.0,       0.0, 1.0, 0.0, -- vertex 4
      -1.0,-1.0, 0.0,       1.0, 0.0, 0.0, -- vertex 5
   } -- 6 vertices with 6 components (floats) each
   gl.BufferData(gl.GL_ARRAY_BUFFER,
                 ffi.sizeof(vertex_data), vertex_data,
                 gl.GL_STATIC_DRAW)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 0*FS)
   gl.EnableVertexAttribArray(1)
   gl.VertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 3*FS)
   gl.BindVertexArray(nil)

   local app = ui.Widget()
   function app:draw()
      gl.Clear(gl.GL_COLOR_BUFFER_BIT)
      gl.UseProgram(shader_program)
      gl.BindVertexArray(vao)
      gl.DrawArrays(gl.GL_TRIANGLES, 0, 6)
   end
   window:add(app)
   window:show()
   sched(window:RenderLoop())

   sched.wait('quit')

   vao:DeleteVertexArray()
   vbo:DeleteBuffer()
   shader_program:DetachShader(vertex_shader)
   shader_program:DetachShader(fragment_shader)
   vertex_shader:DeleteShader()
   fragment_shader:DeleteShader()
   shader_program:DeleteProgram()
end

return M

local M = {}

local ui = require('ui')
local gl = require('gl')
local ffi = require('ffi')
local bit = require('bit')
local sched = require('sched')
local time = require('time')
local mathx = require('mathx')

function M.main()
   local window = ui.Window {
      title = "perspective",
      gl_profile = 'core',
      gl_version = '3.3',
      quit_on_escape = true,
      --fullscreen_desktop = true,
   }

   local FS = ffi.sizeof("GLfloat")

   local rm = gl.ResourceManager()

   local vertex_shader = rm:Shader(gl.GL_VERTEX_SHADER)
   vertex_shader:ShaderSource [[
        #version 330
        uniform mat4 ViewProjection; // the projection matrix uniform
        layout(location = 0) in vec4 vposition;
        layout(location = 1) in vec4 vcolor;
        out vec4 fcolor;
        void main() {
           fcolor = vcolor;
           gl_Position = vposition * ViewProjection;
        }
   ]]
   vertex_shader:CompileShader()

   local fragment_shader = rm:Shader(gl.GL_FRAGMENT_SHADER)
   fragment_shader:ShaderSource [[
        #version 330
        in vec4 fcolor;
        layout(location = 0) out vec4 FragColor;
        void main() {
           FragColor = fcolor;
        }
   ]]
   fragment_shader:CompileShader()

   local shader_program = rm:Program()
   shader_program:AttachShader(vertex_shader)
   shader_program:AttachShader(fragment_shader)
   shader_program:LinkProgram()
   local view_projection_location = shader_program:GetUniformLocation("ViewProjection")

   local vao = rm:VAO()
   gl.BindVertexArray(vao)
   local vbo = rm:VBO()
   gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)
   local vertex_data = gl.FloatArray {
      --  X    Y    Z          R    G    B
      -- face 0:
         1.0, 1.0, 1.0,       1.0, 0.0, 0.0, -- vertex 0
        -1.0, 1.0, 1.0,       1.0, 0.0, 0.0, -- vertex 1
         1.0,-1.0, 1.0,       1.0, 0.0, 0.0, -- vertex 2
        -1.0,-1.0, 1.0,       1.0, 0.0, 0.0, -- vertex 3
      
      -- face 1:
         1.0, 1.0, 1.0,       0.0, 1.0, 0.0, -- vertex 0
         1.0,-1.0, 1.0,       0.0, 1.0, 0.0, -- vertex 1
         1.0, 1.0,-1.0,       0.0, 1.0, 0.0, -- vertex 2
         1.0,-1.0,-1.0,       0.0, 1.0, 0.0, -- vertex 3

      -- face 2:
         1.0, 1.0, 1.0,       0.0, 0.0, 1.0, -- vertex 0
         1.0, 1.0,-1.0,       0.0, 0.0, 1.0, -- vertex 1
        -1.0, 1.0, 1.0,       0.0, 0.0, 1.0, -- vertex 2
        -1.0, 1.0,-1.0,       0.0, 0.0, 1.0, -- vertex 3
      
      -- face 3:
         1.0, 1.0,-1.0,       1.0, 1.0, 0.0, -- vertex 0
         1.0,-1.0,-1.0,       1.0, 1.0, 0.0, -- vertex 1
        -1.0, 1.0,-1.0,       1.0, 1.0, 0.0, -- vertex 2
        -1.0,-1.0,-1.0,       1.0, 1.0, 0.0, -- vertex 3

      -- face 4:
        -1.0, 1.0, 1.0,       0.0, 1.0, 1.0, -- vertex 0
        -1.0, 1.0,-1.0,       0.0, 1.0, 1.0, -- vertex 1
        -1.0,-1.0, 1.0,       0.0, 1.0, 1.0, -- vertex 2
        -1.0,-1.0,-1.0,       0.0, 1.0, 1.0, -- vertex 3

      -- face 5:
         1.0,-1.0, 1.0,       1.0, 0.0, 1.0, -- vertex 0
        -1.0,-1.0, 1.0,       1.0, 0.0, 1.0, -- vertex 1
         1.0,-1.0,-1.0,       1.0, 0.0, 1.0, -- vertex 2
        -1.0,-1.0,-1.0,       1.0, 0.0, 1.0, -- vertex 3
   } -- 6 faces with 4 vertices with 6 components (floats)
   gl.BufferData(gl.GL_ARRAY_BUFFER,
                 ffi.sizeof(vertex_data), vertex_data,
                 gl.GL_STATIC_DRAW)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 0*FS)
   gl.EnableVertexAttribArray(1)
   gl.VertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 3*FS)
   local ibo = rm:VBO()
   gl.BindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ibo)
   local index_data = gl.UByteArray {
      -- face 0:
         0,1,2,      -- first triangle
         2,1,3,      -- second triangle
      -- face 1:
         4,5,6,      -- first triangle
         6,5,7,      -- second triangle
      -- face 2:
         8,9,10,     -- first triangle
         10,9,11,    -- second triangle
      -- face 3:
         12,13,14,   -- first triangle
         14,13,15,   -- second triangle
      -- face 4:
         16,17,18,   -- first triangle
         18,17,19,   -- second triangle
      -- face 5:
         20,21,22,   -- first triangle
         22,21,23,   -- second triangle
   }
   gl.BufferData(gl.GL_ELEMENT_ARRAY_BUFFER,
                 ffi.sizeof(index_data), index_data,
                 gl.GL_STATIC_DRAW)
   gl.BindVertexArray(nil)

   window:show()

   local function MathEngine()
      local ctx = mathx.Compiler()
      local half_pi = math.pi / 2
      local t = ctx:num():input("t")
      local m_rotate_1 = ctx:mat3_rotate(half_pi*t*0.3, ctx:vec(3,{1,1,1}):normalize())
      local m_rotate_2 = ctx:mat3_rotate(half_pi*t*0.8, ctx:vec(3,{1,-1,1}):normalize())
      local m_translate = ctx:mat4_translate(ctx:vec(3,{0,0,5}))
      local m_view = m_rotate_1:extend(4) * m_rotate_2:extend(4) * m_translate
      local fovy = half_pi*0.6
      local aspect_ratio = window.rect.w / window.rect.h
      local znear = 0.1
      local zfar = 100
      local m_projection = ctx:mat4_perspective(fovy,
                                                aspect_ratio,
                                                znear,
                                                zfar)
      --local m_projection = ctx:mat4_perspective(0.99)
      return ctx:compile(m_view * m_projection)
   end
   local engine = MathEngine()

   gl.glEnable(gl.GL_DEPTH_TEST)

   local loop = window:RenderLoop()

   function loop:clear()
      gl.Clear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
   end

   function loop:draw()
      local t = time.time(ffi.C.CLOCK_MONOTONIC)
      local view_projection_matrix = engine(t)
      gl.UseProgram(shader_program)
      gl.UniformMatrix4fv(view_projection_location, 1, gl.GL_FALSE, view_projection_matrix)
      gl.BindVertexArray(vao)
      gl.DrawElements(gl.GL_TRIANGLES, 6*6, gl.GL_UNSIGNED_BYTE, 0)
   end

   sched(loop)
   sched.wait('quit')
   rm:delete()
end

return M

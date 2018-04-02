local M = {}

local ui = require('ui')
local gl = require('gl')
local sdl = require('sdl2')
local ffi = require('ffi')
local bit = require('bit')
local sched = require('sched')
local time = require('time')
local mathx = require('mathx')

local FS = ffi.sizeof("GLfloat")

local function Particles(rm)
   local vertex_shader = rm:Shader(gl.GL_VERTEX_SHADER)
   vertex_shader:ShaderSource [[
        #version 330
        layout(location = 0) in vec4 vposition;
        void main() {
           gl_Position = vposition;
        }
   ]]
   vertex_shader:CompileShader()

   local geometry_shader = rm:Shader(gl.GL_GEOMETRY_SHADER)
   geometry_shader:ShaderSource [[
      #version 330
      uniform mat4 view;
      uniform mat4 proj;
      layout (points) in;
      layout (triangle_strip, max_vertices = 4) out;
      out vec2 txcoord;
      void main() {
         vec4 pos = gl_in[0].gl_Position * view;
         txcoord = vec2(-1,-1);
         gl_Position = (pos + vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2( 1,-1);
         gl_Position = (pos + vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2(-1, 1);
         gl_Position = (pos + vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2( 1, 1);
         gl_Position = (pos + vec4(txcoord,0,0)) * proj;
         EmitVertex();
      }
   ]]
   geometry_shader:CompileShader()

   local fragment_shader = rm:Shader(gl.GL_FRAGMENT_SHADER)
   fragment_shader:ShaderSource [[
      #version 330
      in vec2 txcoord;
      layout(location = 0) out vec4 FragColor;
      void main() {
         float s = 0.2*(1/(1+15.*dot(txcoord, txcoord))-1/16.);
         FragColor = s*vec4(1,0.9,0.6,1);
      }
   ]]
   fragment_shader:CompileShader()

   local shader_program = rm:Program()
   shader_program:AttachShader(vertex_shader)
   shader_program:AttachShader(geometry_shader)
   shader_program:AttachShader(fragment_shader)
   shader_program:LinkProgram()

   local view_location = shader_program:GetUniformLocation("view")
   local proj_location = shader_program:GetUniformLocation("proj")

   local vao = rm:VAO()
   gl.BindVertexArray(vao)

   local vbo = rm:Buffer()
   gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)

   local particles = 128 * 1024
   local vertex_data = ffi.new("GLfloat[?]", particles*3)
   local function mr(term_count)
      term_count = term_count or 1
      local sum = 0
      for i=1,term_count do
         sum = sum + math.random()
      end
      return sum
   end
   for i=0,particles-1 do
      local arm = math.floor(3 * mr())
      local alpha = 1 / (0.1 + mr()^0.7) - 1 / 1.1
      local r = 4.0 * alpha
      alpha = alpha + arm * 2.0 * 3.1416 / 3.0
      vertex_data[3*i+0] = r * math.sin(alpha)
      vertex_data[3*i+1] = 0
      vertex_data[3*i+2] = r * math.cos(alpha)
      vertex_data[3*i+0] = vertex_data[3*i+0] + (4.0 - 0.2 * alpha) * (2-(mr(4)))
      vertex_data[3*i+1] = vertex_data[3*i+1] + (2.0 - 0.1 * alpha) * (2-(mr(4)))
      vertex_data[3*i+2] = vertex_data[3*i+2] + (4.0 - 0.2 * alpha) * (2-(mr(4)))
   end

   gl.BufferData(gl.GL_ARRAY_BUFFER,
                 ffi.sizeof(vertex_data), vertex_data,
                 gl.GL_STATIC_DRAW)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3*FS, 0*FS)

   -- unbind vao to prevent inadvertent changes
   gl.BindVertexArray(nil)

   local self = {}

   function self:draw(view_matrix, proj_matrix)
      gl.Disable(gl.GL_DEPTH_TEST)
      gl.Enable(gl.GL_BLEND)
      gl.BlendFunc(gl.GL_ONE, gl.GL_ONE)
      gl.UseProgram(shader_program)
      gl.UniformMatrix4fv(view_location, 1, gl.GL_FALSE, view_matrix)
      gl.UniformMatrix4fv(proj_location, 1, gl.GL_FALSE, proj_matrix)
      gl.BindVertexArray(vao)
      gl.DrawArrays(gl.GL_POINTS, 0, particles)
   end

   return self
end

-- main

function M.main()
   local window = ui.Window {
      title = "geometry shader - blending",
      gl_profile = 'core',
      gl_version = '3.3',
      quit_on_escape = true,
      --fullscreen_desktop = true,
   }
   window:show()

   local rm = gl.ResourceManager()
   local particles = Particles(rm)

   local function MathEngine(window)
      local ctx = mathx.Compiler()
      local t = ctx:num():input("t")
      local m_rotate_y = ctx:mat4_rotate(math.rad(-22.5)*t, ctx:vec(3,{0,1,0}):normalize())
      local m_rotate_x = ctx:mat4_rotate(math.rad(30)*ctx:sin(0.1*t), ctx:vec(3,{1,0,0}):normalize())
      local m_translate = ctx:mat4_translate(ctx:vec(3,{0,0,50}))
      local m_view = (m_rotate_y * m_rotate_x * m_translate)
      local fovy = math.pi / 2
      local aspect_ratio = window.rect.w / window.rect.h
      local znear = 0.1
      local zfar = 100
      local m_proj = ctx:mat4_perspective(fovy, aspect_ratio, znear, zfar)
      return ctx:compile(m_view, m_proj)
   end

   local engine = MathEngine(window)

   local loop = window:RenderLoop {
      measure = true,
   }

   function loop:clear()
      gl.Clear(gl.GL_COLOR_BUFFER_BIT)
   end

   function loop:draw()
      local t = time.time(ffi.C.CLOCK_MONOTONIC)
      local view_matrix, proj_matrix = engine(t)
      particles:draw(view_matrix, proj_matrix)
   end

   sched(loop)
   sched.wait('quit')
   rm:delete()
end

return M

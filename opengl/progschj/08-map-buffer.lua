local M = {}

local ui = require('ui')
local gl = require('gl')
local glu = require('glu')
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
         gl_Position = (pos + 0.2*vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2( 1,-1);
         gl_Position = (pos + 0.2*vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2(-1, 1);
         gl_Position = (pos + 0.2*vec4(txcoord,0,0)) * proj;
         EmitVertex();
         txcoord = vec2( 1, 1);
         gl_Position = (pos + 0.2*vec4(txcoord,0,0)) * proj;
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
         FragColor = s*vec4(0.3,0.3,1.0,1);
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

   local g = -9.81 -- gravity force
   local bounce = 1.2 -- inelastic: 1.0, elastic: 2.0

   local function ParticleArray(nparticles)
      local self = {
         location = ffi.new("GLfloat[?]", nparticles*3),
         velocity = ffi.new("GLfloat[?]", nparticles*3),
      }
      local translate = {0,20,0}
      local scale = {5,5,5}
      function self:reset(index)
         local loc = self.location + (index-1)*3
         loc[0] = scale[1] * (0.5 - math.random()) + translate[1]
         loc[1] = scale[2] * (0.5 - math.random()) + translate[2]
         loc[2] = scale[3] * (0.5 - math.random()) + translate[3]
         local vel = self.velocity + (index-1)*3
         vel[0] = 0
         vel[1] = 0
         vel[2] = 0
      end
      function self:update(index, dt)
         local vel = self.velocity + (index-1)*3
         vel[1] = vel[1] + g * dt
         local loc = self.location + (index-1)*3
         loc[0] = loc[0] + vel[0] * dt
         loc[1] = loc[1] + vel[1] * dt
         loc[2] = loc[2] + vel[2] * dt
         if loc[1] < -30 then
            self:reset(index)
         end
      end
      for i=1,nparticles do
         self:reset(i)
      end
      return self
   end

   local nparticles = 128 * 1024
   local pa = ParticleArray(nparticles)

   local nbuffers = 3
   local vaos = {}
   local vbos = {}
   for i=1,nbuffers do
      local vao = rm:VAO()
      gl.BindVertexArray(vao)
      local vbo = rm:Buffer()
      gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)
      -- fill with initial data
      gl.BufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof(pa.location), pa.location, gl.GL_DYNAMIC_DRAW)
      -- set up generic attrib pointers
      gl.EnableVertexAttribArray(0)
      gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3*FS, 0*FS)
      vaos[i] = vao
      vbos[i] = vbo
   end
   -- unbind vao to prevent inadvertent changes
   gl.BindVertexArray(nil)

   local function Sphere(center, radius)
      return {
         center = ffi.new("GLfloat[3]", center),
         radius = radius,
      }
   end

   local spheres = {}
   table.insert(spheres, Sphere({0,12,1}, 3))
   table.insert(spheres, Sphere({-3,0,0}, 7))
   table.insert(spheres, Sphere({5,-10,0}, 12))

   local self = {}

   local current_buffer = 1

   function self:next_buffer()
      current_buffer = current_buffer + 1
      if current_buffer > nbuffers then
         current_buffer = 1
      end
   end

   function self:prepare()
      gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbos[current_buffer])
      -- explicitly invalidate buffer
      gl.BufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof(pa.location), nil, gl.GL_DYNAMIC_DRAW)
      -- map the buffer
      local mapped = gl.MapBufferRange(gl.GL_ARRAY_BUFFER, 0, ffi.sizeof(pa.location), bit.bor(gl.GL_MAP_WRITE_BIT, gl.GL_MAP_INVALIDATE_BUFFER_BIT))
      -- copy data into mapped memory
      ffi.copy(mapped, pa.location, ffi.sizeof(pa.location))
      -- unmap the buffer
      gl.UnmapBuffer(gl.GL_ARRAY_BUFFER)
   end

   function self:draw(view_matrix, proj_matrix)
      gl.Disable(gl.GL_DEPTH_TEST)
      gl.Enable(gl.GL_BLEND)
      gl.BlendFunc(gl.GL_ONE, gl.GL_ONE)
      gl.UseProgram(shader_program)
      gl.UniformMatrix4fv(view_location, 1, gl.GL_FALSE, view_matrix)
      gl.UniformMatrix4fv(proj_location, 1, gl.GL_FALSE, proj_matrix)
      gl.BindVertexArray(vaos[current_buffer])
      gl.DrawArrays(gl.GL_POINTS, 0, nparticles)
   end

   local function Bouncer()
      local cc = mathx.Compiler()
      local loc = cc:vec(3):input("location")
      local vel = cc:vec(3):input("velocity")
      local sphere_center = cc:vec(3):input("sphere_center")
      local sphere_radius = cc:num():input("sphere_radius")
      local bounce = cc:num():input("bounce")
      local diff = loc - sphere_center
      local dist = #diff
      local dp = cc:dot(diff, vel)
      return cc:compile(
         cc:when(cc:logand(cc:lt(dist, sphere_radius),
                           cc:lt(dp, 0)),
                 cc:assign(vel, vel - (diff * bounce/(dist*dist)*dp))))
   end
   local bouncer = Bouncer()

   function self:update(dt)
      for i=1,nparticles do
         for j=1,#spheres do
            local s = spheres[j]
            bouncer(pa.location+(i-1)*3,
                    pa.velocity+(i-1)*3,
                    s.center, s.radius,
                    bounce)
         end
         pa:update(i, dt)
      end
   end

   return self
end

-- main

function M.main()
   local window = ui.Window {
      title = "map buffer",
      gl_profile = 'core',
      gl_version = '3.3',
      quit_on_escape = true,
      --fullscreen_desktop = true,
   }
   window:show()

   local rm = glu.ResourceManager()
   local particles = Particles(rm)

   local function MathEngine(window)
      local ctx = mathx.Compiler()
      local t = ctx:num():input("t")
      local m_rotate_y = ctx:mat4_rotate(math.rad(-22.5)*t, ctx:vec(3,{0,1,0}):normalize())
      local m_rotate_x = ctx:mat4_rotate(math.rad(30), ctx:vec(3,{1,0,0}):normalize())
      local m_translate = ctx:mat4_translate(ctx:vec(3,{0,0,30}))
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

   function loop:prepare()
      particles:prepare()
   end

   function loop:clear()
      gl.Clear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
   end

   function loop:draw()
      local t = time.time(ffi.C.CLOCK_MONOTONIC)
      local view_matrix, proj_matrix = engine(t)
      particles:draw(view_matrix, proj_matrix)
   end

   function loop:update(dt)
      particles:update(dt)
      particles:next_buffer()
   end

   sched(loop)
   sched.wait('quit')
   rm:delete()
end

return M

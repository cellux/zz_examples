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

local function vec(size, ...)
   return ffi.new("GLfloat[?]", size, ...)
end

local function vec3(...)
   return vec(3, ...)
end

local nparticles = 128 * 1024

local ymin = -20
local ptrans = vec3(0, 20, 0)
local pscale = 5

local function update_ptrans()
   ptrans[0] = math.sin(sched.now)*5
end

local function build_spheres(defs)
   local spheres = ffi.new("GLfloat[?]", 4*#defs)
   local i = 0
   local function add(x)
      spheres[i] = x
      i = i + 1
   end
   for _,def in ipairs(defs) do
      add(def.center[1])
      add(def.center[2])
      add(def.center[3])
      add(def.radius)
   end
   return spheres, #defs
end

local spheres, nspheres = build_spheres {
   { center = {  0,  12,   1}, radius = 3 },
   { center = { -3,   0,   0}, radius = 7 },
   { center = { -5,  10,   0}, radius = 12 },
}

local g = vec3(0, -9.81, 0) -- gravity
local bounce = 1.2 -- inelastic: 1.0, elastic: 2.0

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

   local transform_vertex_shader = rm:Shader(gl.GL_VERTEX_SHADER)
   transform_vertex_shader:ShaderSource([[
      #version 330
      const int nspheres = ]]..nspheres..[[;
      uniform vec4 spheres[nspheres];
      uniform vec3 g;
      uniform float dt;
      uniform float bounce;
      uniform int seed;
      uniform float ymin;
      uniform vec3 ptrans;
      uniform float pscale;
      layout(location = 0) in vec3 inposition;
      layout(location = 1) in vec3 invelocity;
      out vec3 outposition;
      out vec3 outvelocity;

      float hash(int x) {
         x = x*1235167 + gl_VertexID*948737 + seed*9284365;
         x = (x >> 13) ^ x;
         return ((x * (x * x * 60493 + 19990303) + 1376312589) & 0x7fffffff)/float(0x7fffffff-1);
      }

      void main() {
         outvelocity = invelocity;
         for (int j=0;j<nspheres;j++) {
            vec3 center = spheres[j].xyz;
            float radius = spheres[j].w;
            vec3 diff = inposition-center;
            float dist = length(diff);
            float vdot = dot(diff, invelocity);
            if (dist < radius && vdot < 0.0) {
               outvelocity -= bounce*diff*vdot/(dist*dist);
            }
         }
         outvelocity += dt*g;
         outposition = inposition + dt*outvelocity;
         if (outposition.y < ymin) {
             outvelocity = vec3(0,0,0);
             outposition = 0.5-vec3(hash(3*gl_VertexID+0),hash(3*gl_VertexID+1),hash(3*gl_VertexID+2));
             outposition = ptrans + pscale * outposition;
         }
      }
   ]])
   transform_vertex_shader:CompileShader()

   local transform_shader_program = rm:Program()
   transform_shader_program:AttachShader(transform_vertex_shader)
   local varyings = {"outposition", "outvelocity"}
   transform_shader_program:TransformFeedbackVaryings(varyings, gl.GL_INTERLEAVED_ATTRIBS)
   transform_shader_program:LinkProgram()

   local spheres_location = transform_shader_program:GetUniformLocation("spheres")
   local g_location = transform_shader_program:GetUniformLocation("g")
   local dt_location = transform_shader_program:GetUniformLocation("dt")
   local bounce_location = transform_shader_program:GetUniformLocation("bounce")
   local seed_location = transform_shader_program:GetUniformLocation("seed")
   local ymin_location = transform_shader_program:GetUniformLocation("ymin")
   local ptrans_location = transform_shader_program:GetUniformLocation("ptrans")
   local pscale_location = transform_shader_program:GetUniformLocation("pscale")

   ffi.cdef [[
     struct Particle {
       struct { GLfloat x,y,z; } pos;
       struct { GLfloat x,y,z; } vel;
     }
   ]]

   local function ParticleArray(nparticles)
      local self = {
         vertices = ffi.new("struct Particle[?]", nparticles)
      }
      function self:reset(index)
         local p = self.vertices[index-1]
         p.pos.x = pscale * (0.5 - math.random()) + ptrans[0]
         p.pos.y = pscale * (0.5 - math.random()) + ptrans[1]
         p.pos.z = pscale * (0.5 - math.random()) + ptrans[2]
         p.vel.x = 0
         p.vel.y = 0
         p.vel.z = 0
      end
      update_ptrans()
      for i=1,nparticles do
         self:reset(i)
      end
      return self
   end

   local pa = ParticleArray(nparticles)

   local nbuffers = 2
   local vaos = {}
   local vbos = {}
   for i=1,nbuffers do
      local vao = rm:VAO()
      gl.BindVertexArray(vao)
      local vbo = rm:Buffer()
      gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)
      -- fill with initial data
      gl.BufferData(gl.GL_ARRAY_BUFFER, ffi.sizeof(pa.vertices), pa.vertices, gl.GL_STATIC_DRAW)
      -- set up generic attrib pointers
      gl.EnableVertexAttribArray(0)
      gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 0*FS)
      gl.EnableVertexAttribArray(1)
      gl.VertexAttribPointer(1, 3, gl.GL_FLOAT, gl.GL_FALSE, 6*FS, 3*FS)
      vaos[i] = vao
      vbos[i] = vbo
   end

   -- unbind vao to prevent inadvertent changes
   gl.BindVertexArray(nil)

   local self = {}

   local current_buffer = 1

   local function next_buffer()
      local next_buffer = current_buffer + 1
      if next_buffer > nbuffers then
         next_buffer = 1
      end
      return next_buffer
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

   function self:update(dt)
      gl.UseProgram(transform_shader_program)
      gl.Uniform4fv(spheres_location, nspheres, spheres)
      gl.Uniform3fv(g_location, 1, g)
      gl.Uniform1f(dt_location, dt)
      gl.Uniform1f(bounce_location, bounce)
      gl.Uniform1i(seed_location, math.random(0,bit.lshift(1,30)-1))
      gl.Uniform1f(ymin_location, ymin)
      update_ptrans()
      gl.Uniform3fv(ptrans_location, 1, ptrans)
      gl.Uniform1f(pscale_location, pscale)
      gl.BindVertexArray(vaos[current_buffer])
      gl.BindBufferBase(gl.GL_TRANSFORM_FEEDBACK_BUFFER, 0, vbos[next_buffer()])
      gl.Enable(gl.GL_RASTERIZER_DISCARD)
      gl.BeginTransformFeedback(gl.GL_POINTS)
      gl.DrawArrays(gl.GL_POINTS, 0, nparticles)
      gl.EndTransformFeedback()
      gl.Disable(gl.GL_RASTERIZER_DISCARD)
      current_buffer = next_buffer()
   end

   return self
end

-- main

function M.main()
   local window = ui.Window {
      title = "transform feedback",
      gl_profile = 'core',
      gl_version = '3.3',
      quit_on_escape = true,
      fullscreen_desktop = true,
   }
   window:show()

   local rm = gl.ResourceManager()
   local particles = Particles(rm)

   local function MatrixBuilder(window)
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

   local build_mat = MatrixBuilder(window)

   local loop = window:RenderLoop {
      measure = true,
   }

   function loop:clear()
      gl.Clear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
   end

   function loop:draw()
      local t = time.time(ffi.C.CLOCK_MONOTONIC)
      local view_matrix, proj_matrix = build_mat(t)
      particles:draw(view_matrix, proj_matrix)
   end

   function loop:update(dt)
      particles:update(dt)
   end

   sched(loop)
   sched.wait('quit')
   rm:delete()
end

return M

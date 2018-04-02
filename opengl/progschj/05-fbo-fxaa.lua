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

local function Framebuffer(rm, window)
   local width, height = window.rect.w, window.rect.h

   local texture = rm:Texture()
   gl.BindTexture(gl.GL_TEXTURE_2D, texture)
   gl.TexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR)
   gl.TexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)
   gl.TexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE)
   gl.TexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE)
   gl.TexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, width, height, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, nil)

   local rbf = rm:Renderbuffer()
   gl.BindRenderbuffer(gl.GL_RENDERBUFFER, rbf)
   gl.RenderbufferStorage(gl.GL_RENDERBUFFER, gl.GL_DEPTH_COMPONENT24, width, height)

   local fbo = rm:Framebuffer()
   gl.BindFramebuffer(gl.GL_FRAMEBUFFER, fbo)
   gl.FramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, texture, 0)
   gl.FramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_RENDERBUFFER, rbf)

   local self = {}

   function self:bindFramebuffer()
      fbo:BindFramebuffer()
   end

   function self:bindTexture(texture_unit)
      gl.ActiveTexture(gl.GL_TEXTURE0 + texture_unit)
      gl.BindTexture(gl.GL_TEXTURE_2D, texture)
   end

   return self
end

local function Cube(rm)
   local vertex_shader = rm:Shader(gl.GL_VERTEX_SHADER)
   vertex_shader:ShaderSource [[
        #version 330
        uniform mat4 transform;
        layout(location = 0) in vec4 vposition;
        layout(location = 1) in vec4 vcolor;
        out vec4 fcolor;
        void main() {
           fcolor = vcolor;
           gl_Position = vposition * transform;
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
           // the following line is required for fxaa (will not work with blending!)
           FragColor.a = dot(fcolor.rgb, vec3(0.299, 0.587, 0.114));
        }
   ]]
   fragment_shader:CompileShader()

   local shader_program = rm:Program()
   shader_program:AttachShader(vertex_shader)
   shader_program:AttachShader(fragment_shader)
   shader_program:LinkProgram()

   local transform_location = shader_program:GetUniformLocation("transform")

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

   local self = {}

   function self:draw(transform)
      gl.Enable(gl.GL_DEPTH_TEST)
      gl.UseProgram(shader_program)
      gl.UniformMatrix4fv(transform_location, 1, gl.GL_FALSE, transform)
      gl.BindVertexArray(vao)
      gl.DrawElements(gl.GL_TRIANGLES, 6*6, gl.GL_UNSIGNED_BYTE, 0)
   end

   return self
end

local function FXAA(rm)
   local vertex_shader = rm:Shader(gl.GL_VERTEX_SHADER)
   vertex_shader:ShaderSource [[
      #version 330
      layout(location = 0) in vec4 vposition;
      layout(location = 1) in vec2 vtexcoord;
      out vec2 ftexcoord;
      void main() {
        ftexcoord = vtexcoord;
        gl_Position = vposition;
      }
   ]]
   vertex_shader:CompileShader()
   
   -- this is a Timothy Lottes FXAA 3.11
   -- check out the following link for detailed information:
   -- http://timothylottes.blogspot.ch/2011/07/fxaa-311-released.html
   --
   -- the shader source has been stripped with a preprocessor for
   -- brevity reasons (it's still pretty long for inlining...).
   -- the used defines are:
   -- #define FXAA_PC 1
   -- #define FXAA_GLSL_130 1
   -- #define FXAA_QUALITY__PRESET 13

   local fragment_shader = rm:Shader(gl.GL_FRAGMENT_SHADER)
   fragment_shader:ShaderSource [[
      #version 330
      uniform sampler2D intexture;
      in vec2 ftexcoord;
      layout(location = 0) out vec4 FragColor;
      
      float FxaaLuma(vec4 rgba) {
          return rgba.w;
      }
      
      vec4 FxaaPixelShader(
          vec2 pos,
          sampler2D tex,
          vec2 fxaaQualityRcpFrame,
          float fxaaQualitySubpix,
          float fxaaQualityEdgeThreshold,
          float fxaaQualityEdgeThresholdMin
      ) {
          vec2 posM;
          posM.x = pos.x;
          posM.y = pos.y;
          vec4 rgbyM = textureLod(tex, posM, 0.0);
          float lumaS = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2( 0, 1)));
          float lumaE = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2( 1, 0)));
          float lumaN = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2( 0,-1)));
          float lumaW = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2(-1, 0)));
          float maxSM = max(lumaS, rgbyM.w);
          float minSM = min(lumaS, rgbyM.w);
          float maxESM = max(lumaE, maxSM);
          float minESM = min(lumaE, minSM);
          float maxWN = max(lumaN, lumaW);
          float minWN = min(lumaN, lumaW);
          float rangeMax = max(maxWN, maxESM);
          float rangeMin = min(minWN, minESM);
          float rangeMaxScaled = rangeMax * fxaaQualityEdgeThreshold;
          float range = rangeMax - rangeMin;
          float rangeMaxClamped = max(fxaaQualityEdgeThresholdMin, rangeMaxScaled);
          bool earlyExit = range < rangeMaxClamped;
          if(earlyExit)
              return rgbyM;
      
          float lumaNW = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2(-1,-1)));
          float lumaSE = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2( 1, 1)));
          float lumaNE = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2( 1,-1)));
          float lumaSW = FxaaLuma(textureLodOffset(tex, posM, 0.0, ivec2(-1, 1)));
          float lumaNS = lumaN + lumaS;
          float lumaWE = lumaW + lumaE;
          float subpixRcpRange = 1.0/range;
          float subpixNSWE = lumaNS + lumaWE;
          float edgeHorz1 = (-2.0 * rgbyM.w) + lumaNS;
          float edgeVert1 = (-2.0 * rgbyM.w) + lumaWE;
          float lumaNESE = lumaNE + lumaSE;
          float lumaNWNE = lumaNW + lumaNE;
          float edgeHorz2 = (-2.0 * lumaE) + lumaNESE;
          float edgeVert2 = (-2.0 * lumaN) + lumaNWNE;
          float lumaNWSW = lumaNW + lumaSW;
          float lumaSWSE = lumaSW + lumaSE;
          float edgeHorz4 = (abs(edgeHorz1) * 2.0) + abs(edgeHorz2);
          float edgeVert4 = (abs(edgeVert1) * 2.0) + abs(edgeVert2);
          float edgeHorz3 = (-2.0 * lumaW) + lumaNWSW;
          float edgeVert3 = (-2.0 * lumaS) + lumaSWSE;
          float edgeHorz = abs(edgeHorz3) + edgeHorz4;
          float edgeVert = abs(edgeVert3) + edgeVert4;
          float subpixNWSWNESE = lumaNWSW + lumaNESE;
          float lengthSign = fxaaQualityRcpFrame.x;
          bool horzSpan = edgeHorz >= edgeVert;
          float subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
          if(!horzSpan) lumaN = lumaW;
          if(!horzSpan) lumaS = lumaE;
          if(horzSpan) lengthSign = fxaaQualityRcpFrame.y;
          float subpixB = (subpixA * (1.0/12.0)) - rgbyM.w;
          float gradientN = lumaN - rgbyM.w;
          float gradientS = lumaS - rgbyM.w;
          float lumaNN = lumaN + rgbyM.w;
          float lumaSS = lumaS + rgbyM.w;
          bool pairN = abs(gradientN) >= abs(gradientS);
          float gradient = max(abs(gradientN), abs(gradientS));
          if(pairN) lengthSign = -lengthSign;
          float subpixC = clamp(abs(subpixB) * subpixRcpRange, 0.0, 1.0);
          vec2 posB;
          posB.x = posM.x;
          posB.y = posM.y;
          vec2 offNP;
          offNP.x = (!horzSpan) ? 0.0 : fxaaQualityRcpFrame.x;
          offNP.y = ( horzSpan) ? 0.0 : fxaaQualityRcpFrame.y;
          if(!horzSpan) posB.x += lengthSign * 0.5;
          if( horzSpan) posB.y += lengthSign * 0.5;
          vec2 posN;
          posN.x = posB.x - offNP.x * 1.0;
          posN.y = posB.y - offNP.y * 1.0;
          vec2 posP;
          posP.x = posB.x + offNP.x * 1.0;
          posP.y = posB.y + offNP.y * 1.0;
          float subpixD = ((-2.0)*subpixC) + 3.0;
          float lumaEndN = FxaaLuma(textureLod(tex, posN, 0.0));
          float subpixE = subpixC * subpixC;
          float lumaEndP = FxaaLuma(textureLod(tex, posP, 0.0));
          if(!pairN) lumaNN = lumaSS;
          float gradientScaled = gradient * 1.0/4.0;
          float lumaMM = rgbyM.w - lumaNN * 0.5;
          float subpixF = subpixD * subpixE;
          bool lumaMLTZero = lumaMM < 0.0;
          lumaEndN -= lumaNN * 0.5;
          lumaEndP -= lumaNN * 0.5;
          bool doneN = abs(lumaEndN) >= gradientScaled;
          bool doneP = abs(lumaEndP) >= gradientScaled;
          if(!doneN) posN.x -= offNP.x * 1.5;
          if(!doneN) posN.y -= offNP.y * 1.5;
          bool doneNP = (!doneN) || (!doneP);
          if(!doneP) posP.x += offNP.x * 1.5;
          if(!doneP) posP.y += offNP.y * 1.5;
          if(doneNP) {
              if(!doneN) lumaEndN = FxaaLuma(textureLod(tex, posN.xy, 0.0));
              if(!doneP) lumaEndP = FxaaLuma(textureLod(tex, posP.xy, 0.0));
              if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
              if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
              doneN = abs(lumaEndN) >= gradientScaled;
              doneP = abs(lumaEndP) >= gradientScaled;
              if(!doneN) posN.x -= offNP.x * 2.0;
              if(!doneN) posN.y -= offNP.y * 2.0;
              doneNP = (!doneN) || (!doneP);
              if(!doneP) posP.x += offNP.x * 2.0;
              if(!doneP) posP.y += offNP.y * 2.0;
              if(doneNP) {
                  if(!doneN) lumaEndN = FxaaLuma(textureLod(tex, posN.xy, 0.0));
                  if(!doneP) lumaEndP = FxaaLuma(textureLod(tex, posP.xy, 0.0));
                  if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                  if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                  doneN = abs(lumaEndN) >= gradientScaled;
                  doneP = abs(lumaEndP) >= gradientScaled;
                  if(!doneN) posN.x -= offNP.x * 2.0;
                  if(!doneN) posN.y -= offNP.y * 2.0;
                  doneNP = (!doneN) || (!doneP);
                  if(!doneP) posP.x += offNP.x * 2.0;
                  if(!doneP) posP.y += offNP.y * 2.0;
                  if(doneNP) {
                      if(!doneN) lumaEndN = FxaaLuma(textureLod(tex, posN.xy, 0.0));
                      if(!doneP) lumaEndP = FxaaLuma(textureLod(tex, posP.xy, 0.0));
                      if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                      if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                      doneN = abs(lumaEndN) >= gradientScaled;
                      doneP = abs(lumaEndP) >= gradientScaled;
                      if(!doneN) posN.x -= offNP.x * 4.0;
                      if(!doneN) posN.y -= offNP.y * 4.0;
                      doneNP = (!doneN) || (!doneP);
                      if(!doneP) posP.x += offNP.x * 4.0;
                      if(!doneP) posP.y += offNP.y * 4.0;
                      if(doneNP) {
                          if(!doneN) lumaEndN = FxaaLuma(textureLod(tex, posN.xy, 0.0));
                          if(!doneP) lumaEndP = FxaaLuma(textureLod(tex, posP.xy, 0.0));
                          if(!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
                          if(!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
                          doneN = abs(lumaEndN) >= gradientScaled;
                          doneP = abs(lumaEndP) >= gradientScaled;
                          if(!doneN) posN.x -= offNP.x * 12.0;
                          if(!doneN) posN.y -= offNP.y * 12.0;
                          doneNP = (!doneN) || (!doneP);
                          if(!doneP) posP.x += offNP.x * 12.0;
                          if(!doneP) posP.y += offNP.y * 12.0;
                      }
                  }
              }
          }
      
          float dstN = posM.x - posN.x;
          float dstP = posP.x - posM.x;
          if(!horzSpan) dstN = posM.y - posN.y;
          if(!horzSpan) dstP = posP.y - posM.y;
      
          bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
          float spanLength = (dstP + dstN);
          bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
          float spanLengthRcp = 1.0/spanLength;
      
          bool directionN = dstN < dstP;
          float dst = min(dstN, dstP);
          bool goodSpan = directionN ? goodSpanN : goodSpanP;
          float subpixG = subpixF * subpixF;
          float pixelOffset = (dst * (-spanLengthRcp)) + 0.5;
          float subpixH = subpixG * fxaaQualitySubpix;
      
          float pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
          float pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
          if(!horzSpan) posM.x += pixelOffsetSubpix * lengthSign;
          if( horzSpan) posM.y += pixelOffsetSubpix * lengthSign;
          
          return vec4(textureLod(tex, posM, 0.0).xyz, rgbyM.w);
      }
      
      void main() {    
          FragColor = FxaaPixelShader(
                          ftexcoord,
                          intexture,
                          1.0/textureSize(intexture,0),
                          0.75,
                          0.166,
                          0.0625
                      );
      }
   ]]
   fragment_shader:CompileShader()

   local shader_program = rm:Program()
   shader_program:AttachShader(vertex_shader)
   shader_program:AttachShader(fragment_shader)
   shader_program:LinkProgram()

   local intexture_location = shader_program:GetUniformLocation("intexture")
   local vao = rm:VAO()
   gl.BindVertexArray(vao)
   local vbo = rm:VBO()
   gl.BindBuffer(gl.GL_ARRAY_BUFFER, vbo)
   local vertex_data = gl.FloatArray {
    --  X    Y    Z          U    V
       1.0, 1.0, 0.0,       1.0, 1.0, -- vertex 0
      -1.0, 1.0, 0.0,       0.0, 1.0, -- vertex 1
       1.0,-1.0, 0.0,       1.0, 0.0, -- vertex 2
      -1.0,-1.0, 0.0,       0.0, 0.0, -- vertex 3
   } -- 4 vertices with 5 components (floats) each
   gl.BufferData(gl.GL_ARRAY_BUFFER,
                 ffi.sizeof(vertex_data), vertex_data,
                 gl.GL_STATIC_DRAW)
   gl.EnableVertexAttribArray(0)
   gl.VertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5*FS, 0*FS)
   gl.EnableVertexAttribArray(1)
   gl.VertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5*FS, 3*FS)

   local ibo = rm:VBO()
   gl.BindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ibo)
   local index_data = gl.UByteArray {
      0,1,2, -- first triangle
      2,1,3, -- second triangle
   }
   gl.BufferData(gl.GL_ELEMENT_ARRAY_BUFFER,
                 ffi.sizeof(index_data), index_data,
                 gl.GL_STATIC_DRAW)
   gl.BindVertexArray(nil)

   local self = {}

   function self:draw(texture_unit)
      -- we are not 3d rendering so no depth test
      gl.Disable(gl.GL_DEPTH_TEST)
      -- use the shader program
      gl.UseProgram(shader_program)
      -- set uniforms
      gl.Uniform1i(intexture_location, texture_unit)
      -- bind the vao
      gl.BindVertexArray(vao);
      -- draw
      gl.DrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_BYTE, 0)
   end

   return self
end

-- main

function M.main()
   local window = ui.Window {
      title = "fbo-fxaa",
      gl_profile = 'core',
      gl_version = '3.3',
      quit_on_escape = true,
      --fullscreen_desktop = true,
   }
   window:show()

   local rm = gl.ResourceManager()

   local framebuffer = Framebuffer(rm, window)
   local cube = Cube(rm)
   local fxaa = FXAA(rm)

   local function MathEngine(window)
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
      local m_view_projection = m_view * m_projection
      return ctx:compile(m_view_projection)
   end

   local engine = MathEngine(window)

   local fxaa_enabled = true
   sched.on('sdl.keydown', function(evdata)
      if evdata.key.keysym.sym == sdl.SDLK_SPACE then
         fxaa_enabled = not fxaa_enabled
      end
   end)

   local loop = window:RenderLoop {
      measure = true,
   }

   function loop:prepare()
      if fxaa_enabled then
         -- render cube into a texture
         framebuffer:bindFramebuffer()
      else
         -- render cube directly to screen, without any post-processing
         gl.BindFramebuffer(gl.GL_FRAMEBUFFER, nil)
      end
   end

   function loop:clear()
      gl.Clear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
   end

   function loop:draw()
      local t = time.time(ffi.C.CLOCK_MONOTONIC)
      local view_projection_matrix = engine(t)
      cube:draw(view_projection_matrix)
      -- apply post processing only when fxaa is on
      if fxaa_enabled then
         -- bind source texture to texture unit 0
         framebuffer:bindTexture(0)
         -- render to screen
         gl.BindFramebuffer(gl.GL_FRAMEBUFFER, nil)
         -- apply effect
         fxaa:draw(0)
      end
   end

   sched(loop)
   sched.wait('quit')
   rm:delete()
end

return M

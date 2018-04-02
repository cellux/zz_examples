local M = {}

local ffi = require('ffi')
local ui = require('ui')
local sched = require('sched')
local freetype = require('freetype')
local vfs = require('vfs')
local gl = require('gl')

local round = require('util').round

function M.main()
   local ui = ui {
      title = "render-glyph",
      quit_on_escape = true,
   }

   local function p26_6(name, value)
      pf("%s=%d (%d px)", name, tonumber(value), round(value/64))
   end

   local function Glyph(codepoint)
      local self = ui:Widget()
      local face = freetype.Face(vfs.readfile("DejaVuSerif.ttf"))
      local texture -- this will store the glyph
      function self:layout()
         face:Set_Pixel_Sizes(self.parent.rect.h)
         pf("face info:")
         pf("  num_glyphs=%d", tonumber(face.face.num_glyphs))
         pf("  family_name=%s", ffi.string(face.face.family_name))
         pf("  style_name=%s", ffi.string(face.face.style_name))
         pf("  bbox=(xMin=%d,yMin=%d,xMax=%d,yMax=%d)",
            tonumber(face.face.bbox.xMin),
            tonumber(face.face.bbox.yMin),
            tonumber(face.face.bbox.xMax),
            tonumber(face.face.bbox.yMax))
         pf("  units_per_EM=%d", face.face.units_per_EM)
         pf("  ascender=%d", face.face.ascender)
         pf("  descender=%d", face.face.descender)
         pf("  height=%d", face.face.height)
         pf("  max_advance_width=%d", face.face.max_advance_width)
         pf("  max_advance_height=%d", face.face.max_advance_height)
         pf("  underline_position=%d", face.face.underline_position)
         pf("  underline_thickness=%d", face.face.underline_thickness)
         local metrics = face.face.size.metrics
         pf("  size.metrics.x_ppem=%d", metrics.x_ppem)
         pf("  size.metrics.y_ppem=%d", metrics.y_ppem)
         p26_6("  size.metrics.ascender", metrics.ascender)
         p26_6("  size.metrics.descender", metrics.descender)
         p26_6("  size.metrics.height", metrics.height)
         p26_6("  size.metrics.max_advance", metrics.max_advance)
         face:Load_Char(codepoint)
         face:Render_Glyph(freetype.FT_RENDER_MODE_LCD)
         pf("glyph info for code point U+%04x:", codepoint)
         local glyph = face.face.glyph
         local metrics = glyph.metrics
         p26_6("  metrics.width", metrics.width)
         p26_6("  metrics.height", metrics.height)
         p26_6("  metrics.horiBearingX", metrics.horiBearingX)
         p26_6("  metrics.horiBearingY", metrics.horiBearingY)
         p26_6("  metrics.horiAdvance", metrics.horiAdvance)
         p26_6("  metrics.vertBearingX", metrics.vertBearingX)
         p26_6("  metrics.vertBearingY", metrics.vertBearingY)
         p26_6("  metrics.vertAdvance", metrics.vertAdvance)
         p26_6("  advance.x", glyph.advance.x)
         p26_6("  advance.y", glyph.advance.y)
         pf("  bitmap_left=%d", glyph.bitmap_left)
         pf("  bitmap_top=%d", glyph.bitmap_top)
         pf("  bitmap.rows=%d", glyph.bitmap.rows)
         pf("  bitmap.width=%d", glyph.bitmap.width)
         pf("  bitmap.pitch=%d", glyph.bitmap.pitch)
         pf("  bitmap.num_grays=%d", glyph.bitmap.num_grays)
         pf("  bitmap.pixel_mode=%d", glyph.bitmap.pixel_mode)

         local pixels = glyph.bitmap.buffer
         local pitch = glyph.bitmap.pitch
         local width = glyph.bitmap.width/3
         local height = glyph.bitmap.rows

         local pbuf = ui:PixelBuffer("rgb", width, height)
         local writer = pbuf:Writer { format = "rgb" }
         writer:write(pixels, pitch)

         texture = ui:Texture {
            format = "rgb",
            width = width,
            height = height,
         }
         texture:update(pbuf)
      end

      local blitter = ui:TextureBlitter()

      function self:draw()
         local dst_rect = Rect(0, 0, texture.width, texture.height)
         gl.glEnable(gl.GL_BLEND)
         gl.glBlendEquation(gl.GL_FUNC_ADD)
         gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_COLOR)
         blitter:blit(texture, dst_rect)
      end

      function self:delete()
         if texture then
            texture:delete()
            texture = nil
         end
         if face then
            face:delete()
            face = nil
         end
      end
      return self
   end

   local glyph = Glyph(0x151) -- ő
   ui:add(glyph)

   local loop = ui:RenderLoop()
   function loop:clear()
      -- non-black background to show that the glyph is properly alpha-blended
      ui:clear(Color(64,0,0,255))
   end
   sched(loop)

   ui:show()
   ui:layout()

   sched.wait('quit')

   glyph:delete()
end

return M

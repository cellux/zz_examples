local M = {}

local ui = require('ui')
local gl = require('gl')
local sched = require('sched')
local freetype = require('freetype')
local vfs = require('vfs')
local iconv = require('iconv')
local round = require('util').round

function M.main()
   local ui = ui {
      title = "render-text",
      width = 800, height = 600,
      quit_on_escape = true,
   }

   local verses = tostring(vfs.readfile("verses_on_faith_mind.txt"))
   local face = freetype.Face(vfs.readfile("DejaVuSerif.ttf"))
   local size = 20 -- initial font size in points

   local text_top = 0
   sched(function()
         while true do
            text_top = text_top-1
            sched.sleep(0.01)
         end
   end)

   local texture
   local black = Color(0,0,0,255)

   local function create_texture()
      -- this should be called every time the value of 'size' changes
      if texture then
         texture:delete()
         texture = nil
      end
      face:Set_Char_Size(0, size*64, ui:dpi())
      local max_width = round(face.face.size.metrics.max_advance/64)
      local max_height = round(face.face.size.metrics.height/64)
      -- create texture to hold glyph bitmaps
      texture = ui:Texture {
         format = "rgb",
         width = max_width,
         height = max_height,
      }
   end
   create_texture()

   local blitter = ui:TextureBlitter()

   local function lines(s)
      local index = 1
      local function next()
         local rv = nil
         if index <= #s then
            local lf_pos = s:find("\n", index, true)
            if lf_pos then
               rv = s:sub(index, lf_pos-1)
               index = lf_pos+1
            else
               rv = s:sub(index)
               index = #s+1
            end
         end
         return rv
      end
      return next
   end

   local function draw_char(face, charcode, ox, oy)
      -- this is hopelessly inefficient
      face:Load_Char(charcode)
      face:Render_Glyph(freetype.FT_RENDER_MODE_LCD)
      local glyph = face.face.glyph
      local pixels = glyph.bitmap.buffer
      -- pixels can be nil when we draw a whitespace character
      if pixels ~= nil then
         local pitch = glyph.bitmap.pitch
         local width = glyph.bitmap.width/3
         local height = glyph.bitmap.rows
         local pixbuf = ui:PixelBuffer("rgb", width, height)
         local writer = pixbuf:Writer { format = "rgb" }
         writer:write(pixels, pitch)
         texture:update(pixbuf, pixbuf.rect)
         local dst_rect = Rect(ox+glyph.bitmap_left,
                               oy-glyph.bitmap_top,
                               width, height)
         gl.glEnable(gl.GL_BLEND)
         gl.glBlendEquation(gl.GL_FUNC_ADD)
         gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_COLOR)
         blitter:blit(texture, dst_rect, pixbuf.rect)
      end
      return round(glyph.advance.x/64)
   end

   local function draw_string(face, s, x, y)
      local ascender = round(face.face.size.metrics.ascender / 64)
      local cp = iconv.utf8_codepoints(s)
      local ox = x
      local oy = y+ascender
      for i=1,#cp do
         local advance = draw_char(face, cp[i], ox, oy)
         ox = ox + advance
         if ox >= ui.rect.w then
            break
         end
      end
      return round(face.face.size.metrics.height/64)
   end

   local loop = ui:RenderLoop { measure = true }

   function loop:clear()
      ui:clear(Color(0,64,0))
   end

   function loop:draw()
      local top = text_top
      for line in lines(verses) do
         local advance = draw_string(face, line, 0, top)
         top = top + advance
         if top >= ui.rect.h then
            break
         end
      end
   end

   sched(loop)
   ui:show()
   sched.wait('quit')

   if texture then
      texture:delete()
      texture = nil
   end
   face:Done_Face()
end

return M

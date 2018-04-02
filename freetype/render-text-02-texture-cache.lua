local M = {}

local ui = require('ui')
local gl = require('gl')
local sched = require('sched')
local freetype = require('freetype')
local vfs = require('vfs')
local sdl = require('sdl2')
local iconv = require('iconv')
local round = require('util').round

function M.main()
   local ui = ui {
      title = "render-text",
      fullscreen_desktop = true,
      quit_on_escape = true,
   }

   local function Font(source, size)
      local self = {
         face = freetype.Face(source),
         size = nil, -- initialized below
      }
      function self:set_size(size)
         self.size = size -- measured in points
         self.face:Set_Char_Size(0, self.size*64, ui:dpi())
         local metrics = self.face.face.size.metrics
         self.ascender = round(metrics.ascender / 64)
         self.descender = round(metrics.descender / 64)
         self.height = round(metrics.height / 64)
         self.max_advance = round(metrics.max_advance / 64)
      end
      self:set_size(size)
      local glyph_cache = {}
      function self:get_glyph(charcode)
         if not glyph_cache[charcode] then
            self.face:Load_Char(charcode)
            self.face:Render_Glyph(freetype.FT_RENDER_MODE_LCD)
            local g = self.face.face.glyph
            local gd = { -- glyph data
               bearing_x = g.bitmap_left,
               bearing_y = g.bitmap_top,
               advance_x = round(g.advance.x/64),
               advance_y = round(g.advance.y/64),
               width = 0,
               height = 0,
               texture = nil,
               srcrect = Rect(0,0,0,0),
            }
            local pixels = g.bitmap.buffer
            -- pixels can be nil when we draw a whitespace character
            local pixbuf
            if pixels ~= nil then
               local pitch = g.bitmap.pitch
               gd.width = g.bitmap.width/3
               gd.height = g.bitmap.rows
               local pixbuf = ui:PixelBuffer("rgb", gd.width, gd.height)
               local writer = pixbuf:Writer { format = "rgb" }
               writer:write(pixels, pitch)
               gd.srcrect.w = gd.width
               gd.srcrect.h = gd.height
               gd.texture = ui:Texture {
                  format = "rgb",
                  width = gd.width,
                  height = gd.height,
               }
               gd.texture:update(pixbuf)
            end
            glyph_cache[charcode] = gd
         end
         return glyph_cache[charcode]
      end
      function self:delete()
         for charcode,gd in pairs(glyph_cache) do
            if gd.texture then
               gd.texture:delete()
               gd.texture = nil
            end
         end
         glyph_cache = {}
         if self.face then
            self.face:delete()
            self.face = nil
         end
      end
      return self
   end

   local verses = tostring(vfs.readfile("verses_on_faith_mind.txt"))

   local font_size = 20 -- initial font size in points
   local font = Font(vfs.readfile("DejaVuSerif.ttf"), font_size)

   local text_top = 0
   local text_speed = 1
   sched(function()
         while true do
            text_top = text_top-text_speed
            sched.sleep(0.01)
         end
   end)

   local keymapper = ui:KeyMapper()
   keymapper:push {
      [sdl.SDLK_SPACE] = function()
         text_speed = 1-text_speed
      end,
   }

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

   local blitter = ui:TextureBlitter()

   local function draw_char(font, charcode, ox, oy)
      local glyph_data = font:get_glyph(charcode)
      if glyph_data.width > 0 then
         local dstrect = Rect(ox+glyph_data.bearing_x,
                              oy-glyph_data.bearing_y,
                              glyph_data.width, glyph_data.height)
         gl.glEnable(gl.GL_BLEND)
         gl.glBlendEquation(gl.GL_FUNC_ADD)
         gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_COLOR)
         blitter:blit(glyph_data.texture, dstrect, glyph_data.srcrect)
      end
      return glyph_data.advance_x
   end

   local function draw_string(font, s, x, y)
      local cp = iconv.utf8_codepoints(s)
      local ox = x
      local oy = y+font.ascender
      for i=1,#cp do
         local advance = draw_char(font, cp[i], ox, oy)
         ox = ox + advance
         if ox >= ui.rect.w then
            break
         end
      end
      return font.height
   end

   local black = Color(0,0,0,255)

   local loop = ui:RenderLoop { measure = true }

   function loop:clear()
      ui:clear(black)
   end

   function loop:draw()
      local top = text_top
      for line in lines(verses) do
         if top >= -font.height then
            draw_string(font, line, 0, top)
         end
         top = top + font.height
         if top >= ui.rect.h then
            break
         end
      end
   end

   sched(loop)
   ui:show()
   sched.wait('quit')
   font:delete()
end

return M

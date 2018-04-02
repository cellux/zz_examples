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

   local function TextureAtlas(size)
      local self = {
         size = size,
         items = {},
      }
      local function ItemPacker(texture, size)
         local shelf_x = 0
         local shelf_y = 0
         local shelf_h = 0
         return function(src, src_rect)
            -- src: the pixels of the glyph which should be packed
            -- src_rect: location/size of the glyph in src
            --
            -- src can be a texture or a pixel buffer
            local width, height = src_rect.w, src_rect.h
            if shelf_x + width > size then
               shelf_y = shelf_y + shelf_h
               shelf_x = 0
               shelf_h = 0
            end
            if shelf_x + width > size or shelf_y + height > size then
               return "full"
            end
            local dstrect = Rect(shelf_x, shelf_y, width, height)
            texture:update(src, dstrect, src_rect)
            shelf_x = shelf_x + width
            if height > shelf_h then
               shelf_h = height
            end
            return dstrect
         end
      end
      local function create_texture(size)
         local t = ui:Texture {
            format = "rgb",
            width = size,
            height = size
         }
         t:clear(Color(0,0,0,0))
         return t
      end
      self.texture = create_texture(self.size)
      local pack = ItemPacker(self.texture, self.size)
      function self:resize(new_size)
         pf("resizing atlas to %d", new_size)
         local new_texture = create_texture(new_size)
         local sorted_items = {}
         for k,v in pairs(self.items) do
            table.insert(sorted_items, { key=k, rect=v })
         end
         table.sort(sorted_items, function(a,b) return a.rect.h < b.rect.h end)
         local new_pack = ItemPacker(new_texture, new_size)
         local new_items = {}
         for _,v in ipairs(sorted_items) do
            local dstrect = new_pack(self.texture, v.rect)
            assert(dstrect ~= "full")
            new_items[v.key] = dstrect
         end
         self.texture:delete()
         self.texture = new_texture
         pack = new_pack
         self.items = new_items
         self.size = new_size
      end
      function self:add(key, pixbuf)
         assert(self.items[key] == nil)
         local dstrect = pack(pixbuf, pixbuf.rect)
         if dstrect == "full" then
            self:resize(self.size*2)
            dstrect = pack(pixbuf, pixbuf.rect)
         end
         assert(dstrect ~= "full")
         self.items[key] = dstrect
         return dstrect
      end
      function self:get(key)
         return self.items[key]
      end
      function self:delete()
         if self.texture then
            self.texture:delete()
            self.texture = nil
         end
      end
      return self
   end

   local blitter = ui:TextureBlitter()

   local function Font(source, size)
      local self = {
         face = freetype.Face(source),
         size = nil, -- initialized below
         atlas = TextureAtlas(32),
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
            if pixels ~= nil then
               local pitch = g.bitmap.pitch
               gd.width = g.bitmap.width/3
               gd.height = g.bitmap.rows
               local pixbuf = ui:PixelBuffer("rgb", gd.width, gd.height)
               local writer = pixbuf:Writer { format = "rgb" }
               writer:write(pixels, pitch)
               gd.srcrect = self.atlas:add(charcode, pixbuf)
               gd.texture = self.atlas.texture
            end
            glyph_cache[charcode] = gd
         end
         local gd = glyph_cache[charcode]
         if gd.texture and gd.texture ~= self.atlas.texture then
            gd.texture = self.atlas.texture
            gd.srcrect = self.atlas:get(charcode)
         end
         return gd
      end
      function self:atlas_size()
         return self.atlas.size
      end
      function self:draw(dstrect)
         local srcrect = Rect(0, 0, self.atlas.size, self.atlas.size)
         blitter:blit(self.atlas.texture, dstrect, srcrect)
      end
      function self:delete()
         self.atlas:delete()
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
      local atlas_size = font:atlas_size()
      font:draw(Rect(ui.rect.w - atlas_size, 0, atlas_size, atlas_size))
   end

   sched(loop)
   ui:show()
   sched.wait('quit')
   font:delete()
end

return M

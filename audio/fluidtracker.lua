local M = {}

local ffi = require('ffi')
local sched = require('sched')
local sdl = require('sdl2')
local fluid = require('fluidsynth')
local audio = require('audio')
local ui = require('ui')
local fs = require('fs')
local vfs = require('vfs')
local time = require('time')

local FONT_SIZE = 11
local SAMPLE_RATE = 48000

local function Logger()
   return function(template, ...)
      if template then
         pf("[%s] "..template, time.time(), ...)
      end
   end
end

local log = Logger()

local sf2_path = arg[1]
if not fs.exists(sf2_path) then
   ef("Usage: fluidtracker <sf2-path>")
end

local piano_key_map = {
   [sdl.SDLK_z] = 0,
   [sdl.SDLK_s] = 1,
   [sdl.SDLK_x] = 2,
   [sdl.SDLK_d] = 3,
   [sdl.SDLK_c] = 4,
   [sdl.SDLK_v] = 5,
   [sdl.SDLK_g] = 6,
   [sdl.SDLK_b] = 7,
   [sdl.SDLK_h] = 8,
   [sdl.SDLK_n] = 9,
   [sdl.SDLK_j] = 10,
   [sdl.SDLK_m] = 11,

   [sdl.SDLK_q] = 12,
   [sdl.SDLK_2] = 13,
   [sdl.SDLK_w] = 14,
   [sdl.SDLK_3] = 15,
   [sdl.SDLK_e] = 16,
   [sdl.SDLK_r] = 17,
   [sdl.SDLK_5] = 18,
   [sdl.SDLK_t] = 19,
   [sdl.SDLK_6] = 20,
   [sdl.SDLK_y] = 21,
   [sdl.SDLK_7] = 22,
   [sdl.SDLK_u] = 23,
}

local digit_key_map = {
   [sdl.SDLK_0] = 0x00,
   [sdl.SDLK_1] = 0x01,
   [sdl.SDLK_2] = 0x02,
   [sdl.SDLK_3] = 0x03,
   [sdl.SDLK_4] = 0x04,
   [sdl.SDLK_5] = 0x05,
   [sdl.SDLK_6] = 0x06,
   [sdl.SDLK_7] = 0x07,
   [sdl.SDLK_8] = 0x08,
   [sdl.SDLK_9] = 0x09,
   [sdl.SDLK_a] = 0x0a,
   [sdl.SDLK_b] = 0x0b,
   [sdl.SDLK_c] = 0x0c,
   [sdl.SDLK_d] = 0x0d,
   [sdl.SDLK_e] = 0x0e,
   [sdl.SDLK_f] = 0x0f,
}

local function Tracker(synth, grid, keymapper, global_env)
   local octave = 4
   local min_octave = 0
   local max_octave = 10

   local prognum = 0
   local max_prognum = 127
   local min_prognum = 0

   local mode = nil

   local normal_fg = 7

   local normal_bg = 0
   local hilite_bg = 1
   local play_pos_bg = 2
   local edit_bg = 4

   local playing_pattern = nil
   local tick_duration = 1/4 -- seconds

   local self = {
      env = global_env,
   }

   local pattern_area_width
   local pattern_area_height
   local visible_track_count
   function self:resize()
      local row_number_width = 4 + 1 -- "0000 "
      pattern_area_width = grid.width - row_number_width
      local header_height = 1
      pattern_area_height = grid.height - header_height
      local track_width = 6 -- "C-370 "
      visible_track_count = math.floor(pattern_area_width / track_width)
   end
   self:resize()

   local function Event(track)
      local self = {}
      local label = nil
      local note = nil
      local arg = nil
      local code = ''
      local chunk = nil
      local env = {
         note = function()
            return note
         end,
         arg = function()
            if arg then track.arg = arg end
            return track.arg
         end,
      }
      setmetatable(env, { __index = track.env })
      function self:display()
         local label_str = label and sf('%3s', label) or '...'
         local arg_str = arg and sf('%02x', arg) or '  '
         return label_str..arg_str
      end
      function self:code(new_code)
         if new_code then
            local new_chunk, err = loadstring(new_code)
            if not new_chunk then
               pf("event compilation failed: %s", err)
            else
               chunk = setfenv(new_chunk, env)
               code = new_code
            end
         end
         return code
      end
      function self:play()
         sched(chunk)
      end
      local function note2label(note)
         local octave = math.floor(note / 12)
         local note_offset = note % 12
         local prefix = {
            "C-", "C#", "D-", "D#", "E-", "F-",
            "F#", "G-", "G#", "A-", "A#", "B-",
         }
         return sf('%2s%1d', prefix[note_offset+1], octave)
      end
      function self:label(new_label)
         if new_label then
            label = new_label
         end
         return label
      end
      function self:note(new_note, new_label)
         if new_note then
            note = new_note
            label = new_label or note2label(new_note)
         end
         return note
      end
      function self:clear_note()
         note = nil
         label = nil
      end
      function self:arg(new_arg)
         if new_arg then
            arg = new_arg
         end
         return arg
      end
      function self:arg_hi(digit)
         if digit then
            local new_hi = bit.lshift(bit.band(digit, 0x0f), 4)
            local new_lo = bit.band(arg or 0, 0x0f)
            arg = bit.bor(new_hi, new_lo)
         end
         return arg and bit.rshift(bit.band(arg, 0xf0), 4)
      end
      function self:arg_lo(digit)
         if digit then
            local new_hi = bit.band(arg or 0, 0xf0)
            local new_lo = bit.band(digit, 0x0f)
            arg = bit.bor(new_hi, new_lo)
         end
         return arg and bit.band(arg, 0x0f)
      end
      function self:clear_arg()
         arg = nil
      end
      self:code [[ noteon(0, note(), arg()) ]]
      return self
   end

   local function Track(pattern)
      local self = {
         env = setmetatable({}, { __index = pattern.env }),
      }
      local events = {}
      local event_column_offsets = { 0, 3, 4 }
      function self:draw(x, y, is_current)
         local row = pattern.top_row
         local y_end = math.min(y + pattern_area_height, grid.height)
         while y < y_end do
            local e = events[row]
            local display = e and e:display() or '...  '
            local hilite = is_current and row == pattern.current_row
            if mode=="event-edit" and hilite then
               local col = 1
               local offset = event_column_offsets[col]
               grid:bg(col == pattern.event_column and edit_bg or normal_bg)
               grid:write(x+offset, y, display:sub(1,3))
               local col = 2
               local offset = event_column_offsets[col]
               grid:bg(col == pattern.event_column and edit_bg or normal_bg)
               grid:write(x+offset, y, display:sub(4,4))
               local col = 3
               local offset = event_column_offsets[col]
               grid:bg(col == pattern.event_column and edit_bg or normal_bg)
               grid:write(x+offset, y, display:sub(5,5))
            else
               grid:bg(hilite and hilite_bg or normal_bg)
               grid:write(x, y, display)
            end
            y = y + 1
            row = row + 1
         end
         grid:redraw()
      end
      function self:del_event(row)
         events[row] = nil
      end
      function self:clear_note(row)
         if events[row] then
            events[row]:clear_note()
         end
      end
      function self:set_note(row, note, label)
         if not events[row] then
            events[row] = Event(self)
         end
         events[row]:note(note, label)
      end
      function self:set_arg(row, arg)
         if not events[row] then
            events[row] = Event(self)
         end
         events[row]:arg(arg)
      end
      function self:set_digit(row, column, digit)
         if not events[row] then
            events[row] = Event(self)
         end
         if column == 2 then
            events[row]:arg_hi(digit)
         elseif column == 3 then
            events[row]:arg_lo(digit)
         end
      end
      function self:clear_arg(row)
         if events[row] then
            events[row]:clear_arg()
         end
      end
      function self:last_event_index()
         return table.maxn(events)
      end
      function self:play(row)
         if events[row] then
            events[row]:play()
         end
      end
      return self
   end

   local function Pattern(tracker)
      local self = {
         length = 0,
         play_from = 0,
         play_end = 0,
         play_pos = 0,
         current_row = 0,
         top_row = 0,
         current_track = 1,
         left_track = 1,
         event_column = 1,
         page_size = 16,
         env = setmetatable({}, { __index = tracker.env }),
      }

      local tracks = { Track(self) }

      function self:draw(x,y)
         x = x or 0
         y = y or 0
         -- row numbers
         for i=0, pattern_area_height-1 do
            local row = self.top_row + i
            if row == self.play_pos then
               grid:bg(play_pos_bg)
            elseif row == self.play_from then
               grid:fg(play_pos_bg)
            else
               grid:bg(normal_bg)
            end
            grid:write(x, 1+i, sf('%04x', row))
            if row == self.play_end then
               grid:bg(play_pos_bg)
            else
               grid:bg(normal_bg)
            end
            grid:write(x+4, 1+i, ' ')
            grid:fg(normal_fg)
         end
         -- track numbers and tracks
         for i=0, visible_track_count-1 do
            local track_index = self.left_track + i
            local track = tracks[track_index]
            if not track then break end
            local x = 5 + i * 6
            grid:bg(normal_bg)
            grid:write(x, 0, sf('%03d', track_index))
            track:draw(x, 1, self.current_track == track_index)
         end
         grid:redraw()
      end

      local function adjust()
         if self.current_row < self.top_row then
            self.top_row = self.current_row
         elseif self.current_row - self.top_row >= pattern_area_height then
            self.top_row = self.current_row - pattern_area_height + 1
         end
      end

      function self:up(steps)
         steps = steps or 1
         self.current_row = self.current_row - steps
         if self.current_row < 0 then
            self.current_row = 0
         end
         adjust()
      end

      function self:page_up()
         if self.current_row > 0 then
            local steps = self.current_row % self.page_size
            if steps == 0 then
               steps = self.page_size
            end
            self:up(steps)
         end
      end

      function self:screen_home()
         self.current_row = self.top_row
      end

      function self:pattern_home()
         self.top_row = 0
         self.current_row = self.top_row
         self.left_track = 1
         self.current_track = self.left_track
      end

      function self:down(steps)
         steps = steps or 1
         self.current_row = self.current_row + steps
         adjust()
      end

      function self:page_down()
         local steps = self.page_size - self.current_row % self.page_size
         if steps == 0 then
            steps = self.page_size
         end
         self:down(steps)
      end

      function self:pattern_end()
         local track = tracks[self.current_track]
         self.current_row = track:last_event_index()
         adjust()
      end

      function self:screen_end()
         self.current_row = self.top_row + pattern_area_height - 1
         adjust()
      end

      function self:left()
         if mode=="event-edit" then
            if self.event_column > 1 then
               self.event_column = self.event_column - 1
            elseif self.current_track > 1 then
               self.current_track = self.current_track - 1
               self.event_column = 3
            end
         elseif self.current_track > 1 then
            self.current_track = self.current_track - 1
         end
         if self.current_track < self.left_track then
            self.left_track = self.current_track
         end
      end

      function self:right()
         if mode=="event-edit" then
            if self.event_column < 3 then
               self.event_column = self.event_column + 1
            elseif self.current_track < #tracks then
               self.current_track = self.current_track + 1
               self.event_column = 1
            end
         elseif self.current_track < #tracks then
            self.current_track = self.current_track + 1
         end
         if self.current_track - self.left_track >= visible_track_count then
            self.left_track = self.current_track - visible_track_count + 1
         end
      end

      function self:add_track()
         table.insert(tracks, Track(self))
      end

      function self:del_event()
         tracks[self.current_track]:del_event(self.current_row)
      end

      function self:clear_note()
         tracks[self.current_track]:clear_note(self.current_row)
      end

      function self:set_note(note)
         tracks[self.current_track]:set_note(self.current_row, note)
      end

      function self:set_arg(arg)
         tracks[self.current_track]:set_arg(self.current_row, arg)
      end

      function self:set_digit(digit)
         tracks[self.current_track]:set_digit(self.current_row, self.event_column, digit)
      end

      function self:clear_arg()
         tracks[self.current_track]:clear_arg(self.current_row)
      end

      function self:play_row()
         for i=1,#tracks do
            tracks[i]:play(self.play_pos)
         end
         self.play_pos = self.play_pos + 1
      end

      return self
   end

   -- Tracker

   local patterns = {}
   patterns[0] = Pattern(self)
   local pat = 0 -- index of current pattern

   function self:current_pattern()
      return patterns[pat]
   end

   function self:draw()
      self:current_pattern():draw(0,0)
   end

   local function event_edit_mode_keymap(sym, mod)
      local p = self:current_pattern()
      if sym == sdl.SDLK_TAB then
         keymapper:pop()
         mode = nil
      elseif sym == sdl.SDLK_PERIOD then
         if p.event_column == 1 then
            p:clear_note()
         else
            p:clear_arg()
         end
      elseif p.event_column == 1 then
         local offset = piano_key_map[sym]
         if offset then
            p:set_note(octave * 12 + offset)
         else
            return true
         end
      else
         local digit = digit_key_map[sym]
         if digit then
            p:set_digit(digit)
         else
            return true
         end
      end
      p:draw()
   end

   local tracker_keymap = {
      [sdl.SDLK_ESCAPE] = function()
         if playing_pattern then
            playing_pattern = nil
         else
            return true
         end
      end,
      [sdl.SDLK_SPACE] = function()
         local p = self:current_pattern()
         p.play_pos = p.play_from
         playing_pattern = p
         p:draw()
      end,
      [sdl.SDLK_b] = function(sym, mod)
         local p = self:current_pattern()
         if mod.shift then
            p.play_from = 0
         else
            p.play_from = p.current_row
         end
         p:draw()
      end,
      [sdl.SDLK_e] = function(sym, mod)
         local p = self:current_pattern()
         if mod.shift then
            p.play_end = 0
         else
            p.play_end = p.current_row
         end
         p:draw()
      end,
      [sdl.SDLK_DELETE] = function()
         local p = self:current_pattern()
         p:del_event()
         p:draw()
      end,
      [sdl.SDLK_TAB] = function()
         keymapper:push(event_edit_mode_keymap)
         mode = "event-edit"
         local p = self:current_pattern()
         p:draw()
      end,
      [sdl.SDLK_UP] = function()
         local p = self:current_pattern()
         p:up()
         p:draw()
      end,
      [sdl.SDLK_PAGEUP] = function()
         local p = self:current_pattern()
         p:page_up()
         p:draw()
      end,
      [sdl.SDLK_HOME] = function(sym, mod)
         local p = self:current_pattern()
         if mod.ctrl then
            p:pattern_home()
         else
            p:screen_home()
         end
         p:draw()
      end,
      [sdl.SDLK_DOWN] = function()
         local p = self:current_pattern()
         p:down()
         p:draw()
      end,
      [sdl.SDLK_PAGEDOWN] = function()
         local p = self:current_pattern()
         p:page_down()
         p:draw()
      end,
      [sdl.SDLK_END] = function(sym, mod)
         local p = self:current_pattern()
         if mod.ctrl then
            p:pattern_end()
         else
            p:screen_end()
         end
         p:draw()
      end,
      [sdl.SDLK_LEFT] = function()
         local p = self:current_pattern()
         p:left()
         p:draw()
      end,
      [sdl.SDLK_RIGHT] = function()
         local p = self:current_pattern()
         p:right()
         p:draw()
      end,
      [sdl.SDLK_KP_PLUS] = function(sym, mod)
         if mod.shift then
            local p = self:current_pattern()
            p:add_track()
            p:draw()
         else
            if octave < max_octave then
               octave = octave + 1
            end
         end
      end,
      [sdl.SDLK_KP_MINUS] = function()
         if octave > min_octave then
            octave = octave - 1
         end
      end,
   }
   keymapper:push(tracker_keymap)

   local function play()
      while true do
         local pp = playing_pattern
         if pp then
            pp:play_row()
            pp:draw()
            if pp.play_pos == pp.play_end then
               playing_pattern = nil
            end
         end
         sched.wait(sched.now + tick_duration)
      end
   end
   sched.background(play)

   return self
end

function M.main()
   local ui = ui {
      title = "FluidTracker",
      fullscreen_desktop = true,
      selective_redraw = true,
   }

   log("loading font")
   local font = ui:Font {
      source = vfs.readfile("DroidSansMono.ttf"),
      size = FONT_SIZE
   }

   log("creating grid")
   local grid = ui:Grid { font = font }
   ui:add(grid)

   ui:show()
   ui:layout()

   log("assembling synth settings")
   local settings = fluid.Settings()
   settings:setnum("synth.gain", 1)
   settings:setint("synth.midi-channels", 256)
   settings:setnum("synth.sample-rate", SAMPLE_RATE)

   log("creating synth")
   local synth = fluid.Synth(settings)
   log("loading soundfont: %s", sf2_path)
   local sf_id = synth:sfload(sf2_path, true)

   log("creating audio engine")
   local engine = audio.Engine {
      freq = SAMPLE_RATE,
      channels = 2,
      samples = 1024,
   }
   log("adding fluidsynth as an audio source")
   engine:add(fluid.AudioSource(synth))
   log("starting audio engine")
   engine:start()

   log("creating keymapper")
   local keymapper = ui:KeyMapper()

   log("creating top-level keymap")
   local top_level_keymap = {
      [sdl.SDLK_ESCAPE] = function()
         keymapper:disable()
         log("stopping audio engine")
         engine:stop()
         log("deleting audio engine")
         engine:delete()
         log("deleting synth")
         synth:delete()
         settings:delete()
         log("exiting")
         sched.quit()
      end,
   }
   keymapper:push(top_level_keymap)

   local global_env = {
      noteon = function(chan, key, vel)
         if chan and key and vel then
            synth:noteon(chan, key, vel)
         end
      end,
      noteoff = function(chan, key)
         if chan and key then
            synth:noteoff(chan, key)
         end
      end,
   }

   log("creating tracker")
   local tracker = Tracker(synth, grid, keymapper, global_env)
   tracker:draw() -- this draws into the grid only

   log("starting render loop")
   local loop = ui:RenderLoop { measure = true }
   sched(loop)
   sched.wait('quit')
end

return M

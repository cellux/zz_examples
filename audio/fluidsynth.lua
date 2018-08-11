local M = {}

local ffi = require('ffi')
local sched = require('sched')
local sdl = require('sdl2')
local ui = require('ui')
local fluid = require('fluidsynth')
local fs = require('fs')
local vfs = require('vfs')
local process = require('process')
local audio = require('audio')

local FONT_SIZE = 11
local SAMPLE_RATE = 48000

local function Logger(grid)
   local log_row = 0
   return function(template, ...)
      if template then
         grid:write(0, log_row, sf(template, ...))
      end
      if log_row < grid.height - 1 then
         log_row = log_row + 1
      else
         grid:scroll_up()
      end
      grid:redraw()
      sched.yield()
   end
end

function M.main()
   local sf2_path = arg[1]
   if not fs.exists(sf2_path) then
      pf("Usage: fluidsynth <sf2-path>")
      process.exit(0)
   end

   local ui = ui {
      title = "FluidSynth",
      fullscreen_desktop = true,
      selective_redraw = true,
   }

   local font = ui:Font {
      source = vfs.readfile("DroidSansMono.ttf"),
      size = FONT_SIZE
   }

   local grid = ui:Grid { font = font }
   ui:add(grid)
   ui:show()
   ui:layout()

   local loop = ui:RenderLoop { measure = true }
   sched(loop)

   local log = Logger(grid)
   local settings = fluid.Settings()
   settings:setnum("synth.gain", 1)
   settings:setint("synth.midi-channels", 256)
   settings:setnum("synth.sample-rate", SAMPLE_RATE)
   log("synth.sample-rate=%s", settings:getnum("synth.sample-rate"))
   log("synth.audio-channels=%s", settings:getint("synth.audio-channels"))
   log("synth.midi-channels=%s", settings:getint("synth.midi-channels"))
   log("synth.gain=%s", settings:getnum("synth.gain"))

   local synth = fluid.Synth(settings)
   local sf_id = synth:sfload(sf2_path, true)
   log("successfully loaded %s, id=%d", sf2_path, sf_id)

   log("GetCurrentAudioDriver()=%s", sdl.GetCurrentAudioDriver())
   for i=1,sdl.GetNumAudioDevices() do
      log("GetAudioDeviceName(%d)=%s", i, sdl.GetAudioDeviceName(i))
   end

   local source = fluid.AudioSource(synth)
   local device = audio.Device {
      freq = SAMPLE_RATE,
      channels = 2,
      samples = 1024,
      source = source,
   }

   local spec = device.spec
   log("SDL_OpenAudioDevice():")
   log("  freq=%d", spec.freq)
   log("  format=%d", spec.format)
   log("  channels=%d", spec.channels)
   log("  samples=%d", spec.samples)
   log("  size=%d", spec.size)

   log("zsxdcvgbhnjm: notes from current octave")
   log("q2w3er5t6y7u: notes from next octave")
   log("UP: octave up")
   log("DOWN: octave down")
   log("RIGHT: next program")
   log("LEFT: previous program")
   log("BACKSPACE: all notes off")
   log("ESC: quit")
   log()

   log("starting audio device")
   device:start()
   log("now play.")

   local octave = 5
   local min_octave = 0
   local max_octave = 10
   
   local prognum = 0
   local max_prognum = 127
   local min_prognum = 0

   local function log_channel_info(chan)
      local info = synth:get_channel_info(chan)
      log("sfont_id=%d bank=%d program=%d: %s", info.sfont_id, info.bank, info.program, info.name)
   end

   local keymapper = ui:KeyMapper()

   local function quit()
      keymapper:disable()
      log("stopping audio device")
      device:stop()
      log("closing audio device")
      device:close()
      log("cleanup fluidsynth")
      synth:delete()
      settings:delete()
      log("exiting")
      sched.quit()
   end

   local key_map = {
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

   local function handle_keydown(sym)
      if sym == sdl.SDLK_UP then
         if octave < max_octave then
            octave = octave + 1
         end
      elseif sym == sdl.SDLK_DOWN then
         if octave > min_octave then
            octave = octave - 1
         end
      elseif sym == sdl.SDLK_RIGHT then
         if prognum < max_prognum then
            prognum = prognum + 1
            synth:program_change(0, prognum)
            log_channel_info(0)
         end
      elseif sym == sdl.SDLK_LEFT then
         if prognum > min_prognum then
            prognum = prognum - 1
            synth:program_change(0, prognum)
            log_channel_info(0)
         end
      elseif sym == sdl.SDLK_BACKSPACE then
         synth:all_notes_off(0)
      elseif sym == sdl.SDLK_ESCAPE then
         quit()
      else
         local key = key_map[sym]
         if key then
            synth:noteon(0, octave*12+key, 127)
         end
      end
   end
   keymapper:push(handle_keydown)
end

return M

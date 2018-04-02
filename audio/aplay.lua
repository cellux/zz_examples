local M = {}

local audio = require('audio')
local sndfile = require('sndfile')
local argparser = require('argparser')
local process = require('process')
local sched = require('sched')

local function usage()
   pf [[
Usage: aplay [options] <audiofile>

Options:

  -l|--list                  List available audio devices
  -d|--device <device-id>    Use specified audio device
]]
end

local function list_devices()
   pf("Audio driver: %s", audio.driver())
   pf("Available audio devices:")
   for device in audio.devices() do
      pf("%d: %s", device.id, device.name)
   end
end

local function play(path)
   pf("Loading audio file: %s", path)
   local buf, sfinfo = sndfile.load(path)
   local player = audio.SamplePlayer {
      buf = buf,
      channels = sfinfo.channels,
      frames = sfinfo.frames,
   }
   pf("Loaded %d frames, %d channels.", player.frames, player.channels)
   local engine = audio.Engine()
   pf("Playing audio file...")
   engine:add(player)
   engine:start()
   local end_signal = player:play()
   end_signal:poll()
   engine:stop()
   engine:remove(player)
   engine:delete()
end

local ap = argparser("aplay", "play audio file")

ap:add {
   name = "file",
   type = "string",
   desc = "audio file to play",
}
ap:add {
   name = "list",
   type = "bool",
   option = "-l|--list",
   desc = "show list of available audio devices",
}
ap:add {
   name = "device",
   type = "number",
   option = "-d|--device",
   desc = "index of audio device to use",
}

function M.main()
   local args = ap:parse()
   if args.list then
      list_devices()
   elseif args.file then
      play(args.file)
   else
      usage()
   end
end

return M

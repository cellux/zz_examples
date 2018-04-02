local M = {}

local ui = require('ui')
local sched = require('sched')

function M.main()
   local window = ui.Window {
      title = "skeleton",
      quit_on_escape = true,
   }
   window:show()
   sched(window:RenderLoop())
end

return M

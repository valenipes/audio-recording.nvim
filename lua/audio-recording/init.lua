local core = require('audio-recording.core')
local config = require('audio-recording.config')

local M = {}

function M.setup(user_config)
  user_config = user_config or {}
  config.setup(user_config)
  core.setup(config.get())
end

M.start_recording = function(...) return core.start_recording(...) end
M.stop_recording  = function(...) return core.stop_recording(...) end
M.annotate        = function(...) return core.annotate(...) end
M.save_marks_for_buf = function(...) return core.save_marks_for_buf(...) end

return M

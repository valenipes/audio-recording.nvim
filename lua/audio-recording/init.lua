local core = require('audio-recording.core')
local config = require('audio-recording.config')

local M = {}

function M.setup(user_config)
  user_config = user_config or {}
  config.setup(user_config)
  core.setup(config.get())
end

return M

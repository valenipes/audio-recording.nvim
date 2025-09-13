local Job = require('plenary.job')
local debug_buf = require('audio-recording.debug_buf')

local M = {}

function M.new_shell_job(self, source, encoder, audio_filename, on_exit)
  local cmd = string.format('%s | %s', source:cmd(), encoder:cmd(audio_filename))
  local j = Job:new({
    command = 'sh',
    args = { '-c', cmd },
    on_stdout = vim.schedule_wrap(function(_, data, _)
      if data ~= nil and debug_buf then
        debug_buf.write(function(bufnr)
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, { data })
        end)
      end
    end),
    on_exit = vim.schedule_wrap(function(_, code)
      if debug_buf then
        debug_buf.write(function(bufnr)
          local out = string.format('Recording "%s" finished (exit=%s)', audio_filename, tostring(code))
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, { out })
        end)
      end
      if type(on_exit) == 'function' then pcall(on_exit, code) end
    end),
  })
  return j
end

return M

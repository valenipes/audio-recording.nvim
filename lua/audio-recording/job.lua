local debug_buf = require('audio-recording.debug_buf')
local vim_schedule = vim.schedule_wrap

local M = {}

-- Simple job wrapper using vim.fn.jobstart for sh -c "<cmd>"
function M.new_shell_job(self, source, encoder, audio_filename, on_exit)
   local cmd = string.format('%s | %s 2>/dev/null', source:cmd(), encoder:cmd(audio_filename))

   local job = {
      jid = nil,
      cmd = cmd,
      on_exit = on_exit,
      running = false,
   }
   
   -- handles stdout, prints it in the debug buffer if enabled
   local function handle_stdout(_, data, _)
      if data and #data > 0 and debug_buf then
         vim.schedule(function()
            local out = {}
            for _, line in ipairs(data) do
               if line ~= '' then table.insert(out, line) end
            end
            if #out > 0 then debug_buf.write(out) end
         end)
      end
   end


   local function handle_exit(_, code, _)
      vim_schedule(function()
         if debug_buf then
            debug_buf.write(string.format('Recording "%s" finished (exit=%s)', audio_filename, tostring(code)))
         end
         if type(job.on_exit) == 'function' then pcall(job.on_exit, code) end
      end)
      job.running = false
      job.jid = nil
   end

   function job:start()
      if self.running then return end
      -- jobstart expects a command/table; use shell -c to evaluate piping
      local opts = {
         stdout_buffered = true,
         on_stdout = handle_stdout,
         on_stderr = function() end,
         on_exit = handle_exit,
      }
      local ok, jid = pcall(function()
         return vim.fn.jobstart({ 'sh', '-c', self.cmd }, opts)
      end)
      if ok and jid and jid > 0 then
         self.jid = jid
         self.running = true
         return true
      else
         return false
      end
   end

   function job:shutdown()
      if self.jid and vim.fn.jobwait({ self.jid }, 0)[1] == -1 then
         -- if still running, try to stop it
         pcall(function() vim.fn.jobstop(self.jid) end)
      end
      self.running = false
      self.jid = nil
   end

   function job:strip_internal_buffers() end

   return job
end

return M

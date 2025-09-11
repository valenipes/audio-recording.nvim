local Job = require('plenary.job')
local PWSource = require('audio.sources.pipewire')
local OpusEncoder = require('audio.encoders.opus')

local function format_timestamp(timestamp)
   return os.date('%Y-%m-%d_%H:%M:%S', timestamp)
end

local M = {
   config = {
      recording_dir = '.recordings/',
      debug_mode = true
   },
   state = {
      filename = nil,
      extmarks_path = nil,
      current_bufnr = nil,
      audio_filename = nil,
      start_timestamp = 0,
      has_the_user_added_extmarks = false,
      is_recording_ongoing = false
   },
   debug_buffer = nil,
   jobs = {
      shell = nil,
   }
}

M._ns = M._ns or vim.api.nvim_create_namespace("audio_rec_extmarks")

function M:create_new_buf(filename)
if not self.config.debug_mode then return end

   if not self.debug_buffer then
      self.debug_buffer = {
         bufnr = vim.api.nvim_create_buf(true, true),
      }
   end
   vim.api.nvim_buf_set_name(self.debug_buffer.bufnr, 'rec://' .. filename)
end


function M:write_to_buf(callback)
   if not self.debug_buffer then return end

   vim.api.nvim_buf_set_option(self.debug_buffer.bufnr, 'modifiable', true)
   callback(self.debug_buffer.bufnr) -- this means that the function write_to_buf is not entirely defined here, but instead when it's called you can specify other commands.
   vim.api.nvim_buf_set_option(self.debug_buffer.bufnr, 'modifiable', false)
end


function M:get_filename()
   local current_bufnr = vim.api.nvim_get_current_buf()
   local current_buf_full_path = vim.api.nvim_buf_get_name(current_bufnr)
   self.state.filename = vim.fn.fnamemodify(current_buf_full_path, ":t") -- file name with filetype
end


function M:get_extmarks_path()
   self.state.extmarks_path = self.config.recording_dir .. "/" .. self.state.filename .. "_extmarks" .. ".lua" -- file where to save extmarks
end


function M:get_current_bufnr()
   self.state.current_bufnr = vim.api.nvim_get_current_buf()
end


function M:new_job(source, encoder, audio_filename)
   if self.state.is_recording_ongoing then return end

   -- FIXME: Plenary removes \r from the input, which results in garbled data
   --        This hack spawns a shell to encode the file
   self.jobs.shell = Job:new({
      command = 'sh',
      args = {
         '-c',
         string.format('%s | %s', source:cmd(), encoder:cmd(audio_filename))
      },
      on_stdout = vim.schedule_wrap(function(_, data, _) -- If I understand correctly, schedule_wrap is required to execute write_to_buf on the main nvim loop; https://github.com/nvim-lua/plenary.nvim/issues/189
         if self.debug_buffer then
            M:write_to_buf(function(debug_bufnr)
               vim.api.nvim_buf_set_lines(debug_bufnr, -1, -1, true, { data })
            end)
         end
      end),
      on_exit = vim.schedule_wrap(function(_, _)
         if self.debug_buffer then
            M:write_to_buf(function(debug_bufnr)
               local output = string.format('Recording "%s" finished!', audio_filename)
               vim.api.nvim_buf_set_lines(debug_bufnr, -1, -1, true, { output })
            end)
         end
      end)
   })
end


function M:save_marks_for_buf(current_bufnr)

   if not self.state.extmarks_path then
      vim.notify("No extmarks file.")
      return
   end

   local raw_extmarks_metadata = vim.api.nvim_buf_get_extmarks(current_bufnr, M._ns, 0, -1, { details = true })
   local extmarks_metadata = {}

   for _, m in ipairs(raw_extmarks_metadata) do
      local details = m[4] or {}
      table.insert(extmarks_metadata, {
         id = m[1],
         row = m[2],
         col = m[3],
         virt_text = details.virt_text,
         virt_text_pos = details.virt_text_pos, -- or "eol",
         hl_mode = details.hl_mode,
         right_gravity = details.right_gravity,
      })
   end

   local f, err = io.open(self.state.extmarks_path, "w")
   if not f then
      vim.notify("audio-recording, cannot write annotation marks: " .. tostring(err), vim.log.levels.WARN)
      return
   end
   f:write("return " .. vim.inspect(extmarks_metadata))
   f:close()
end


function M:start_recording(source, encoder)
   if self.state.is_recording_ongoing then
      vim.notify("audio-recording: Already recording!")
      return
   end

   source = source or PWSource.new()
   encoder = encoder or OpusEncoder.new(source.opts)


   self.state.start_timestamp = os.time()
   self.state.audio_filename = self.config.recording_dir .. self.state.filename .. "_" .. format_timestamp(self.state.start_timestamp)  .. '.ogg'

   vim.fn.mkdir(self.config.recording_dir, 'p')

   self:new_job(source, encoder, self.state.audio_filename)

   self.jobs.shell:start()
   self.state.is_recording_ongoing = true

   vim.notify("audio-recording: recording started!")

   if self.config.debug_mode then
      self:create_new_buf(self.state.filename)
      self:write_to_buf(function(debug_bufnr)
         local lines = {
            'File name: ' .. self.state.filename , 'Recording to: ' .. self.state.audio_filename, 'Using "' .. source.name() .. '" as the source and "' .. encoder.name() .. '" as the encoder with these settings:',
         }
         local opts_str = vim.split(vim.inspect(encoder.opts), '\n', { trimempty = true })
         for _, v in pairs(opts_str) do
            table.insert(lines, v)
         end
         vim.api.nvim_buf_set_lines(debug_bufnr, 0, -1, false, lines)
      end)
   end
end

function M:stop_recording()
   if not self.state.is_recording_ongoing then
      vim.notify("audio-recording: no recording started yet.")
      return
   end

   self.jobs.shell:shutdown()
   self.state.is_recording_ongoing = false
   vim.notify("audio-recording: recording finished!")
end


local function clear_marks_for_buf(current_bufnr)
   current_bufnr = current_bufnr or vim.api.nvim_get_current_buf()
   pcall(vim.api.nvim_buf_clear_namespace, current_bufnr, M._ns, 0, -1)
end

local function load_marks_for_buf(current_bufnr)
   current_bufnr = vim.api.nvim_get_current_buf()
   if not M.state.extmarks_path or vim.fn.filereadable(M.state.extmarks_path) == 0 then return end

   local k, marks = pcall(dofile, M.state.extmarks_path)
   if not k or type(marks) ~= "table" then
      vim.notify("audio-recording: failed to load extmarks for buffer", vim.log.levels.WARN)
      return
   end

   clear_marks_for_buf(current_bufnr)

   local line_count = vim.api.nvim_buf_line_count(current_bufnr)
   for _, m in ipairs(marks) do
      local row = math.max(0, math.min(m.row or 0, line_count - 1))
      local col = 0
      local opts = {}
      if m.virt_text then opts.virt_text = m.virt_text end
      opts.virt_text_pos = "eol"
      if m.hl_mode then opts.hl_mode = m.hl_mode end
      if m.right_gravity ~= nil then opts.right_gravity = m.right_gravity end
      pcall(vim.api.nvim_buf_set_extmark, current_bufnr, M._ns, row, col, opts)
   end
end

vim.api.nvim_create_autocmd({ "BufReadPost" }, {  -- removed "BufWinEnter" since it's redundant
   callback = function()
        pcall(function() M:get_filename() end)
        pcall(function() M:get_extmarks_path() end)
        pcall(function() M:get_current_bufnr() end)
      if vim.fn.glob(M.state.extmarks_path) ~= ""  then -- if the file extmarks_path exists
         pcall(load_marks_for_buf, M.current_bufnr)
      end
   end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*",
  callback = function(args)
    local bufnr = args.buf
    local ok, err = pcall(function() M:save_marks_for_buf(bufnr) end)
    if not ok then
      vim.notify("save_marks_for_buf failed: " .. tostring(err), vim.log.levels.WARN)
    end
  end,
})



function M:annotate(opts)
   if not self.state.is_recording_ongoing then
      return
   end

   self.state.has_the_user_added_extmarks = true

   opts = opts or {}
   local default_opts = {
      format = ' [%s] ',
      insert_text = true
   }
   opts = vim.tbl_extend('force', default_opts, opts)

   local diff = os.difftime(os.time(), self.state.start_timestamp)
   local timestamp = os.date('!%T', diff)

   if opts.insert_text then
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = 0
      local line_text = string.format(opts.format, timestamp .. " - Rec " ..  os.date('%Y-%m-%d_%H:%M:%S', self.state.start_timestamp))

      -- sets extmark at the end of the line
      vim.api.nvim_buf_set_extmark(0, M._ns, row, col, {
         virt_text = { { line_text, "Comment" } },
         virt_text_pos = "eol",
         hl_mode = "combine",
      })
--      pcall(function() self:save_marks_for_buf(self.state.current_bufnr) end)
   end

   return timestamp
end



local function del_extmarks_on_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local ext = vim.api.nvim_buf_get_extmarks(bufnr, M._ns, {row, 0}, {row, -1}, {})
  for _, m in ipairs(ext) do
    vim.api.nvim_buf_del_extmark(bufnr, M._ns, m[1])
  end
end

vim.keymap.set('n', 'dd', function()
  del_extmarks_on_cursor()
  vim.api.nvim_command('normal! dd')
end, { silent = true })

local function setup_commands()
   vim.api.nvim_create_user_command('rec', function(opt)
      if #opt.fargs == 0 then
         return
      end

      if opt.fargs[1] == 'start' then
         M:start_recording()
      elseif opt.fargs[1] == 'stop' then
         M:stop_recording()
      elseif opt.fargs[1] == 'annotate' then
         M:annotate()
      end
   end, {
      nargs = '*',
      force = true,
      complete = function(arglead, cmdline, cursorpos)
         return { "start", "stop", "annotate" }
      end,
   })
end

setup_commands()

return M

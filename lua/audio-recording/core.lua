local utils = require('audio-recording.utils')
local job_mod = require('audio-recording.job')
local debug_buf = require('audio-recording.debug_buf')

local PWSource = require('audio.sources.pipewire')
local OpusEncoder = require('audio.encoders.opus')

local M = {
  config = {},
  state = {
    filename = nil,
    extmarks_path = nil,
    current_bufnr = nil,
    audio_filename = nil,
    start_timestamp = 0,
    has_the_user_added_extmarks = false,
    is_recording_ongoing = false,
  },
  jobs = {
    shell = nil,
  }
}

M._ns = vim.api.nvim_create_namespace('audio_rec_extmarks')

function M:get_filename()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr) or ''
  self.state.filename = vim.fn.fnamemodify(name, ':t') -- base name
  if self.state.filename == '' then
    self.state.filename = 'nofile'
  end
  return self.state.filename
end

function M:get_extmarks_path()
  if not self.state.filename then return nil end
  self.state.extmarks_path = self.config.recording_dir .. self.state.filename .. "_extmarks.lua"
  return self.state.extmarks_path
end

function M:get_current_bufnr()
  self.state.current_bufnr = vim.api.nvim_get_current_buf()
  return self.state.current_bufnr
end

function M:save_marks_for_buf(bufnr)
  bufnr = bufnr or self.state.current_bufnr or vim.api.nvim_get_current_buf()
  if not self.state.extmarks_path then
    vim.notify("No extmarks file.", vim.log.levels.WARN)
    return
  end
  local raw = vim.api.nvim_buf_get_extmarks(bufnr, self._ns, 0, -1, { details = true })
  local out = {}
  for _, m in ipairs(raw) do
    local details = m[4] or {}
    table.insert(out, {
      id = m[1],
      row = m[2],
      col = m[3],
      virt_text = details.virt_text,
      virt_text_pos = details.virt_text_pos,
      hl_mode = details.hl_mode,
      right_gravity = details.right_gravity,
    })
  end
  local ok, err = utils.safe_write_file(self.state.extmarks_path, "return " .. vim.inspect(out))
  if not ok then
    vim.notify("audio-recording: cannot write annotation marks: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M:load_marks_for_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not self.state.extmarks_path or vim.fn.filereadable(self.state.extmarks_path) == 0 then return end
  local ok, marks = pcall(dofile, self.state.extmarks_path)
  if not ok or type(marks) ~= 'table' then
    vim.notify("audio-recording: failed to load extmarks for buffer", vim.log.levels.WARN)
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self._ns, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, m in ipairs(marks) do
    local row = math.max(0, math.min(m.row or 0, line_count - 1))
    local col = 0
    local opts = {}
    if m.virt_text then opts.virt_text = m.virt_text end
    opts.virt_text_pos = "eol"
    if m.hl_mode then opts.hl_mode = m.hl_mode end
    if m.right_gravity ~= nil then opts.right_gravity = m.right_gravity end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, self._ns, row, col, opts)
  end
end

function M:new_job(source, encoder, audio_filename)
  if self.state.is_recording_ongoing then return end
  local j = job_mod.new_shell_job(self, source, encoder, audio_filename, function() end)
  self.jobs.shell = j
  return j
end

function M:start_recording(source, encoder)
  if self.state.is_recording_ongoing then
    vim.notify("audio-recording: Already recording!")
    return
  end

  source = source or PWSource.new()
  encoder = encoder or OpusEncoder.new(source.opts)

  self.state.start_timestamp = os.time()
  local fname = self.state.filename or self:get_filename()
  self.state.audio_filename = self.config.recording_dir .. fname .. "_" .. utils.format_timestamp(self.state.start_timestamp) .. '.ogg'

  utils.mkdir_p(self.config.recording_dir)

  self:new_job(source, encoder, self.state.audio_filename)

  if self.jobs.shell then
    self.jobs.shell:start()
    self.state.is_recording_ongoing = true
    vim.notify("audio-recording: recording started!")
  else
    vim.notify("audio-recording: failed to create job", vim.log.levels.ERROR)
  end

  if self.config.debug_mode then
    debug_buf.create(fname)
    debug_buf.write(function(bufnr)
      local lines = {
        'File name: ' .. tostring(fname),
        'Recording to: ' .. tostring(self.state.audio_filename),
        'Source: ' .. source.name(),
        'Encoder: ' .. encoder.name(),
        'Encoder opts:',
      }
      local opts_str = vim.split(vim.inspect(encoder.opts), '\n', { trimempty = true })
      for _, v in ipairs(opts_str) do table.insert(lines, v) end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end)
  end
end

function M:stop_recording()
  if not self.state.is_recording_ongoing then
    vim.notify("audio-recording: no recording started yet.")
    return
  end
  if self.jobs.shell then
    pcall(function() self.jobs.shell:shutdown() end)
  end
  self.state.is_recording_ongoing = false
  vim.notify("audio-recording: recording finished!")
end

function M:annotate(opts)
  if not self.state.is_recording_ongoing then
      vim.notify("audio-recording: cannot annotate, no recording ongoing.")
      return
   end
  self.state.has_the_user_added_extmarks = true
  opts = opts or {}
  local default_opts = { format = ' [%s] ', insert_text = true }
  opts = vim.tbl_extend('force', default_opts, opts)

  local diff = os.difftime(os.time(), self.state.start_timestamp)
  local timestamp = os.date('!%T', diff)

  if opts.insert_text then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = 0
    local line_text = string.format(opts.format, timestamp .. " - Rec " .. utils.format_timestamp(self.state.start_timestamp))
    vim.api.nvim_buf_set_extmark(0, self._ns, row, col, {
      virt_text = { { line_text, "Comment" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end

  return timestamp
end

function M:del_extmarks_on_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local ext = vim.api.nvim_buf_get_extmarks(bufnr, self._ns, { row, 0 }, { row, -1 }, {})
  for _, m in ipairs(ext) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, self._ns, m[1])
  end
end

function M.setup(cfg)
  M.config = cfg or M.config or {}

  pcall(function() M:get_filename() end)
  pcall(function() M:get_extmarks_path() end)
  pcall(function() M:get_current_bufnr() end)

  require('audio-recording.nvim_integration').setup(M)
end

return M


local utils = require('audio-recording.utils')
local job_mod = require('audio-recording.job')
local debug_buf = require('audio-recording.debug_buf')

local PWSource = require('audio.sources.pipewire')
local OpusEncoder = require('audio.encoders.opus')
-- Utilities to debug:
-- List of namespaces -- :lua print(vim.inspect(vim.api.nvim_get_namespaces()))
-- Check content of namespace -- :lua print(vim.inspect(vim.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details =true }) or {}))
-- Check the content of a table -- :lua print(vim.inspect(require("audio-recording.core").extmarks_table))

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
      append_ext_to_word = {
         in_word = false,
         start_row = nil,
         start_col = nil,
      },
      player_pid = nil,
   },
   jobs = {
      shell = nil,
   },
   extmarks_table = {},
   automatic_word_mode_state = {
      in_word = false,
      start_row = nil,
      start_col = nil,
   }
}

-- These functions return the namespace id
-- fixme: all extmarks, manual and automatic, are added in the same namespace and saved in the same file _extmarks.lua... for the future, it'd be better to store them in different namespaces saving them in different files. This is needed to avoid conflicts: every namespace has its indices, if multiple extmarks have the same index in the _extmarks.lua, there is conflict based on how the code is written.
-- M.audio_recording_ns = vim.api.nvim_create_namespace('audio_recording.manual_extmarks')
M.audio_recording_ns = vim.api.nvim_create_namespace('audio_recording.extmarks')

local function get_text_range(bufnr, srow, scol, erow, ecol)
   -- FIXME: srow's and erow's clamping is useless, substitute with a =~ nil check, >0 check and also insert the corresponding errors.
   bufnr = bufnr or vim.api.nvim_get_current_buf()
   local line_count = vim.api.nvim_buf_line_count(bufnr)                            -- total number of lines in the buffer
   srow = math.max(0, math.min(srow or 0, line_count - 1))                          -- starting row
   erow = math.max(0, math.min(erow or srow, line_count - 1))                       -- ending row, for a certain word, should always be the same of srow
   if srow == erow then
      local line = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, true)[1] or "" -- returns the line
      local start_col = math.max(0, math.min(scol or 0, #line))                     -- #line is the total number of columns
      local end_col = math.max(0, math.min(ecol or start_col, #line))
      return string.sub(line, start_col + 1, end_col)
   else
      vim.notify("audio-recording: extmark's start row not equal to end row, no range returned", vim.log.levels.WARN)
   end
end

local function prune_extmarks_by_word_match(bufnr)
   -- FIXME: prune_extmarks_by_word_match iterates inside namespaces, but it should iterate in M.extmarks_table, because it must be persistent and namespaces are not.
   bufnr = bufnr or vim.api.nvim_get_current_buf()
   local existing_ext_table = {}

   local function collect_from_ns(ns_id)
      local raw = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true }) or
          {} -- with the interval (0,-1), returns all extmarks

      -- Typical raw structure of an extmark:
      -- { { 1, 0, 49, {
      --   end_col = 53,
      --   end_right_gravity = false,
      --   end_row = 0,
      --   ns_id = 13,
      --   right_gravity = true
      -- } }, { 2, 0, 54, {
      --   end_col = 58,
      --   end_right_gravity = false,
      --   end_row = 0,
      --   ns_id = 13,
      --   right_gravity = true
      -- } } }
      for _, r in ipairs(raw) do
         local id = r[1]
         local srow = r[2]
         local scol = r[3]
         local details = r[4] or {}
         existing_ext_table[id] = {
            start_row = srow,
            start_col = scol,
            end_row = details.end_row or srow,
            end_col = details.end_col or scol,
            details = details,
         }
      end
   end

   -- collect_from_ns(M.audio_recording_ns)
   collect_from_ns(M.audio_recording_ns)

   -- here begins the pruning of the table
   for i = #M.extmarks_table, 1, -1 do -- iterates in all extmarks collected since now
      local e = M.extmarks_table[i]
      if not e or not e.id then
         table.remove(M.extmarks_table, i)
      else
         local info = existing_ext_table[e.id]
         if not info then
            table.remove(M.extmarks_table, i)
         else
            local expected_word = e.metadata and e.metadata.word -- if e.metadata exists, it accesses e.metadata.word
            -- here checks if the extmark "e" in the extmarks_table is the same as the extmark in the namespace by comparing the word, if not it is deleted
            if expected_word and expected_word ~= "" then
               local actual = get_text_range(bufnr, info.start_row, info.start_col, info.end_row, info.end_col) or ""
               if actual ~= expected_word then
                  table.remove(M.extmarks_table, i)
                  -- print("Table removed")
               else -- update location
                  e.row = info.start_row
                  e.col = info.start_col
                  e.end_row = info.end_row
                  e.end_col = info.end_col
               end
            else
               -- if metadata.word doesn't exist, update the location -- I don't understand why.. if the word doesn't exist then the extmark should be deleted...
               e.row = info.start_row
               e.col = info.start_col
               e.end_row = info.end_row
               e.end_col = info.end_col
            end
         end
      end
   end
end


function M:play_current_mark()
   local bufnr = vim.api.nvim_get_current_buf()
   local row, col = unpack(vim.api.nvim_win_get_cursor(0))
   row = row - 1

   -- ottieni extmarks nel buffer in tutti i namespace (manual e automatic)
   local ranges = {
      -- { ns = self.audio_recording_ns,         raw = vim.api.nvim_buf_get_extmarks(bufnr, self.audio_recording_ns, { row, 0 }, { row, -1 }, { details = true }) or {} },
      { ns = self.audio_recording_ns, raw = vim.api.nvim_buf_get_extmarks(bufnr, self.audio_recording_ns, { row, 0 }, { row, -1 }, { details = true }) or {} },
   }

   local found = nil
   for _, r in ipairs(ranges) do
      for _, e in ipairs(r.raw) do
         local id = e[1]
         local start_row = e[2]
         local start_col = e[3]
         local details = e[4] or {}
         local end_row = details.end_row or start_row
         local end_col = details.end_col or start_col

         -- check if cursor is within the extmark range
         local in_range = false
         if row > start_row and row < end_row then
            in_range = true
         elseif row == start_row and row == end_row then
            if col >= start_col and col <= end_col then in_range = true end
         elseif row == start_row then
            if col >= start_col then in_range = true end
         elseif row == end_row then
            if col <= end_col then in_range = true end
         end

         if in_range then
            found = { id = id, details = details }
            break
         end
      end
      if found then break end
   end

   if not found then
      vim.notify("audio-recording: no extmark under cursor", vim.log.levels.WARN)
      return
   end

   -- trova la entry nella extmarks_table usando l'id
   local entry = nil
   for _, e in ipairs(self.extmarks_table) do
      if e.id == found.id then
         entry = e
         break
      end
   end

   if not entry or not entry.metadata then
      vim.notify("audio-recording: extmark has no recording metadata", vim.log.levels.WARN)
      return
   end

   local recording = entry.metadata.recording
   local timestamp = entry.metadata.timestamp

   if not recording or recording == '' then
      vim.notify("audio-recording: no recording file associated with this mark", vim.log.levels.WARN)
      return
   end

   -- costruisci comando: mpv <recording> --start=<HH:MM:SS>
   local cmd = { "mpv", recording }
   if timestamp and timestamp ~= '' then
      table.insert(cmd, "--start=" .. tostring(timestamp))
   end

   -- avvia mpv in background (non bloccante) e salva il pid
   local ok, jid = pcall(function()
      return vim.fn.jobstart(cmd, { detach = true })
   end)

   if not ok or not jid or jid == 0 then
      vim.notify("audio-recording: failed to start mpv: " .. tostring(jid), vim.log.levels.ERROR)
      return
   end

   -- salva pid per poterlo killare dopo; jobstart ritorna il job id (jid),
   -- ma vim.fn.jobstart in Neovim può essere usato con vim.loop to get pid:
   local ok2, pid = pcall(function() return vim.fn.jobpid(jid) end)
   if ok2 and pid and pid > 0 then
      self.state.player_pid = pid
   else
      -- fallback: salva jid comunque (potrebbe essere utile su alcune versioni)
      self.state.player_pid = jid
   end

   vim.notify(
      "audio-recording: playing " .. recording .. (timestamp and timestamp ~= '' and (" from " .. timestamp) or ""),
      vim.log.levels.INFO)
end

function M:kill_player()
   local pid = self.state.player_pid
   if not pid or pid == 0 then
      vim.notify("audio-recording: no player pid known to kill", vim.log.levels.ERROR)
      return
   end

   -- prova a uccidere il processo
   local cmd = string.format("kill %d 2>/dev/null", tonumber(pid))
   local res = os.execute(cmd)

   -- pulizia stato
   self.state.player_pid = nil

   if res == 0 or res == true then
      vim.notify("audio-recording: killed player (pid=" .. tostring(pid) .. ")", vim.log.levels.INFO)
   else
      vim.notify("audio-recording: failed to kill player (pid=" .. tostring(pid) .. ")", vim.log.levels.WARN)
   end
end

local function create_extmark(bufnr, srow, scol, erow, ecol)
   local diff = os.difftime(os.time(), M.state.start_timestamp)
   local timestamp = os.date('!%T', diff)

   local opts = {
      end_row = erow,
      end_col = ecol,
   }
   if M.config.debug_mode then
      utils.ensure_highlight()
      opts.hl_group = "WordExtmarkDebug"
      opts.hl_eol = false
   end

   local id = vim.api.nvim_buf_set_extmark(bufnr, M.audio_recording_ns, srow, scol, opts)

   local details = {
      erow = erow,
      ecol = ecol,
      hl_group = opts.hl_group,
      hl_eol = opts.hl_eol,
   }
   local entry = M:make_extmark_entry(id, srow, scol, details)
   entry.metadata.timestamp = timestamp

   -- estrai il testo effettivo nell'intervallo e salvalo in metadata.word
   local function get_range_text(buf, sr, sc, er, ec)
      local line_count = vim.api.nvim_buf_line_count(buf)
      sr = math.max(0, math.min(sr or 0, line_count - 1))
      er = math.max(0, math.min(er or sr, line_count - 1))
      if sr == er then
         local line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, true)[1] or ""
         local start_col = math.max(0, math.min(sc or 0, #line))
         local end_col = math.max(0, math.min(ec or start_col, #line))
         return string.sub(line, start_col + 1, end_col)
      end
      local lines = vim.api.nvim_buf_get_lines(buf, sr, er + 1, true)
      if #lines == 0 then return "" end
      lines[1] = string.sub(lines[1], (sc or 0) + 1)
      lines[#lines] = string.sub(lines[#lines], 1, ec or #lines[#lines])
      return table.concat(lines, "\n")
   end

   local word = get_range_text(bufnr, srow, scol, erow, ecol)
   entry.metadata.word = word or ""

   table.insert(M.extmarks_table, entry)

   return id
end

local function close_current_word(final_row, final_col)
   local bufnr = vim.api.nvim_get_current_buf()
   create_extmark(bufnr, M.automatic_word_mode_state.start_row, M.automatic_word_mode_state.start_col, final_row,
      final_col)
   M.automatic_word_mode_state.in_word = false
   M.automatic_word_mode_state.start_row = nil
   M.automatic_word_mode_state.start_col = nil
end

function M.remove_extmark_by_id(bufnr, id)
   if not id then return false end
   vim.api.nvim_buf_del_extmark(bufnr, M.audio_recording_ns, id)
   for i, e in ipairs(M.extmarks_table) do
      if e.id == id then
         table.remove(M.extmarks_table, i)
         return true
      end
   end
   return false
end

function M.del_extmarks_on_cursor()
   local api = vim.api
   local bufnr = api.nvim_get_current_buf()
   local win = api.nvim_get_current_win()
   local pos = api.nvim_win_get_cursor(win) -- {row, col}, 1-based row
   local row0 = pos[1] - 1                 -- 0-based

   local marks = api.nvim_buf_get_extmarks(bufnr, M.audio_recording_ns, { row0, 0 }, { row0, -1 }, { details = false })

   for _, m in ipairs(marks) do
      local id = m[1]
      pcall(function() M.remove_extmark_by_id(bufnr, id) end)
      -- pcall(api.nvim_buf_del_extmark, bufnr, M.audio_recording_ns, id)
   end
end

function M.on_text_changed_i()
   local bufnr = vim.api.nvim_get_current_buf()
   local cursor = vim.api.nvim_win_get_cursor(0)
   local row, col = cursor[1], cursor[2]
   row = row - 1

   local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1] or ""

   local prev_char = nil
   -- This section is meant do define which is the character before the cursor
   if col > 0 and col <= #line + 1 then
      prev_char = string.sub(line, col, col)
      -- elseif col > #line then
      --    prev_char = "\n"
   else
      prev_char = "\n"
   end

   if M.automatic_word_mode_state.in_word and utils.is_separator(prev_char) then
      local final_row, final_col = row, math.max(0, col - 1)
      -- the function handles the state of M.automatic_word_mode_state.in_word
      close_current_word(final_row, final_col)
      return
   end

   if (not M.automatic_word_mode_state.in_word) and (not utils.is_separator(prev_char)) then
      M.automatic_word_mode_state.in_word = true
      M.automatic_word_mode_state.start_row = row
      M.automatic_word_mode_state.start_col = math.max(0, col - 1)
      return
   end
end

function M.on_insert_leave()
   if not M.automatic_word_mode_state.in_word then
      if M.config.debug_mode then
         vim.notify("audio_recording: function core.on_insert_leave: not in a word", vim.log.levels.WARN)
      end
      return
   end
   cursor = vim.api.nvim_win_get_cursor(0)
   local row, col = cursor[1], cursor[2]
   row = row - 1
   local final_row, final_col = row, math.max(0, col + 1)
   close_current_word(final_row, final_col)
   if M.config.debug_mode then
      vim.notify("audio_recording: exiting insert mode on row " .. final_row .. " and column " .. final_col,
         vim.log.levels.WARN)
   end
end

function M.get_extmarks_table()
   return M.extmarks_table
end

function M:make_extmark_entry(id, srow, scol, details) -- s stands for starting (e.g. srow = starting row)
   details = details or {}
   local entry = {
      id = id,
      row = srow,
      col = scol,
      end_row = details.erow,
      end_col = details.ecol,
      virt_text = details.virt_text,
      virt_text_pos = details.virt_text_pos,
      hl_mode = details.hl_mode,
      right_gravity = details.right_gravity,
      hl_group = details.hl_group,
      hl_eol = details.hl_eol,
      metadata = {
         recording = self.state.audio_filename,
         timestamp = nil,
         word = nil,
      }
   }
   return entry
end

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

   local raw = vim.api.nvim_buf_get_extmarks(bufnr, self.audio_recording_ns, 0, -1, { details = true })
   local id_map = {}
   for _, m in ipairs(raw) do
      id_map[m[1]] = {
         row = m[2],
         col = m[3],
         details = m[4] or {}
      }
   end

   for _, entry in ipairs(self.extmarks_table) do
      local info = id_map[entry.id]
      if info then
         entry.row = info.row
         entry.col = info.col
         local d = info.details
         entry.virt_text = d.virt_text or entry.virt_text
         entry.virt_text_pos = d.virt_text_pos or entry.virt_text_pos
         entry.hl_mode = d.hl_mode or entry.hl_mode
         entry.right_gravity = d.right_gravity or entry.right_gravity
      end
   end

   -- DOPO l'aggiornamento delle posizioni e PRIMA della scrittura su file.
   pcall(function() prune_extmarks_by_word_match(bufnr) end)

   local ok, err = utils.safe_write_file(self.state.extmarks_path, "return " .. vim.inspect(self.extmarks_table))
   if not ok then
      vim.notify("audio-recording: cannot write annotation marks: " .. tostring(err), vim.log.levels.WARN)
   end
end

function M:load_marks_for_buf(bufnr)
   bufnr = bufnr or vim.api.nvim_get_current_buf()
   if not self.state.extmarks_path or vim.fn.filereadable(self.state.extmarks_path) == 0 then
      vim.notify("audio-recording: extmarks file doesn't exist or isn't readable", vim.log.levels.WARN)
      return
   end
   local ok, marks = pcall(dofile, self.state.extmarks_path)
   if not ok or type(marks) ~= 'table' then
      vim.notify("audio-recording: failed to load extmarks for buffer", vim.log.levels.WARN)
      return
   end

   self.extmarks_table = marks

   pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.audio_recording_ns, 0, -1)
   local line_count = vim.api.nvim_buf_line_count(bufnr)
   for _, m in ipairs(marks) do
      local row = math.max(0, math.min(m.row or 0, line_count - 1))
      local col = math.max(0, (m.col or 0))
      local opts = {}

      if m.virt_text then
         opts.virt_text = m.virt_text
         opts.virt_text_pos = m.virt_text_pos or "eol"
         if m.hl_mode then opts.hl_mode = m.hl_mode end
         if m.right_gravity ~= nil then opts.right_gravity = m.right_gravity end
      else
         if m.hl_group then
            utils.ensure_highlight()
            opts.hl_group = m.hl_group
            if m.hl_eol ~= nil then opts.hl_eol = m.hl_eol end
         end
         if m.right_gravity ~= nil then opts.right_gravity = m.right_gravity end
         if m.end_row ~= nil then opts.end_row = m.end_row end
         if m.end_col ~= nil then opts.end_col = m.end_col end
      end

      local ok2, new_id, err = pcall(function()
         return vim.api.nvim_buf_set_extmark(bufnr, self.audio_recording_ns, row, col, opts)
      end)
      if not ok2 or not new_id then
         vim.notify("audio-recording: failed to set extmark: " .. tostring(new_id or err), vim.log.levels.WARN)
      else
         m.id = new_id
      end
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
      vim.notify("audio-recording: Already recording!", vim.log.levels.WARN)
      return
   end

   source = source or PWSource.new()
   encoder = encoder or OpusEncoder.new(source.opts)

   self.state.start_timestamp = os.time()
   local fname = self.state.filename or self:get_filename()
   self.state.audio_filename = self.config.recording_dir ..
       fname .. "_" .. utils.format_timestamp(self.state.start_timestamp) .. '.ogg'

   utils.mkdir_p(self.config.recording_dir)

   self:new_job(source, encoder, self.state.audio_filename)

   if self.jobs.shell then
      self.jobs.shell:start()
      self.state.is_recording_ongoing = true
      if self.config.automatic_annotation_word_mode then
         pcall(function() self:enable_word_autocmds() end)
         self.state.has_the_user_added_extmarks = true
      end
      print("audio-recording: recording started!")
   else
      vim.notify("audio-recording: failed to create job", vim.log.levels.ERROR)
   end

   if self.config.debug_mode then
      debug_buf.create()
      debug_buf.write(function()
         local lines = {
            'File name: ' .. tostring(fname),
            'Recording to: ' .. tostring(self.state.audio_filename),
            'Source: ' .. source.name(),
            'Encoder: ' .. encoder.name(),
            'Encoder opts:',
         }
         local opts_str = vim.split(vim.inspect(encoder.opts), '\n', { trimempty = true })
         for _, v in ipairs(opts_str) do table.insert(lines, v) end
         return lines
      end)
   end
end

function M:stop_recording()
   if not self.state.is_recording_ongoing then
      vim.notify("audio-recording: no recording started yet.", vim.log.levels.WARN)
      return
   end
   if self.jobs.shell then
      pcall(function() self.jobs.shell:shutdown() end)
   end
   self.state.is_recording_ongoing = false
   if self.config.automatic_annotation_word_mode then
      pcall(function() self:disable_word_autocmds() end)
   end
   print("audio-recording: recording finished!")
end

function M:annotate(opts)
   if not self.config.manual_annotation_mode then
      vim.notify("audio-recording: cannot annotate, manual_annotation_mode set to false in configuration file.",
         vim.log.levels.ERROR)
      return
   end
   if not self.state.is_recording_ongoing then
      vim.notify("audio-recording: cannot annotate, no recording ongoing.", vim.log.levels.ERROR)
      return
   end

   opts = opts or {}
   local default_opts = { format = ' [%s] ', insert_text = true }
   opts = vim.tbl_extend('force', default_opts, opts)

   local diff = os.difftime(os.time(), self.state.start_timestamp)
   local timestamp = os.date('!%T', diff)

   if opts.insert_text then
      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = 0
      local line_text = string.format(opts.format,
         timestamp .. " - Rec " .. utils.format_timestamp(self.state.start_timestamp))

      local ok, mark_id = pcall(function()
         return vim.api.nvim_buf_set_extmark(0, self.audio_recording_ns, row, col, {
            virt_text = { { line_text, "Comment" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
         })
      end)

      if ok and mark_id then
         local details = {
            virt_text = { { line_text, "Comment" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
            right_gravity = false,
         }
         local entry = self:make_extmark_entry(mark_id, row, col, details)
         entry.metadata.timestamp = timestamp
         table.insert(self.extmarks_table, entry)
         self.state.has_the_user_added_extmarks = true
      else
         vim.notify("audio-recording: failed to set extmark", vim.log.levels.WARN)
      end
   end
end

local function get_buf_text()
   -- returns current row, column and the line
   local r, c = unpack(vim.api.nvim_win_get_cursor(0))
   local line = vim.api.nvim_get_current_line()
   return { row = r, col = c, line = line }
end

function M.enable_word_autocmds()
   vim.cmd([[
    augroup audio_recording_word
    autocmd!
    autocmd TextChangedI * lua require('audio-recording.core').select_insertions_and_discard_deletions() -- this autocommand is triggered everytime the text changes... This caused the program to crash when deleting text with backslash, because on_text_changed_i was called
    autocmd InsertLeave * lua require('audio-recording.core').on_insert_leave()
    augroup END
  ]])
end

local state = {}
function M.select_insertions_and_discard_deletions()
   local bufnr = M.state.current_bufnr or vim.api.nvim_get_current_buf()
   local s = state[bufnr]
   if not s then
      s = { last = get_buf_text(), last_was_insert = false }
      state[bufnr] = s
      return
   end

   local cur = get_buf_text()
   local prev = s.last

   local inserted = false
   if cur.line == prev.line then
      if #cur.line > #prev.line then
         inserted = true
      elseif #cur.line < #prev.line then
         inserted = false
      else
         if cur.col > prev.col then inserted = true end
      end
   else
      if #cur.line > #prev.line then inserted = true end
   end

   s.last = cur
   s.last_was_insert = inserted

   if inserted then
      pcall(function() require('audio-recording.core').on_text_changed_i() end)
   end
end

--

function M.disable_word_autocmds()
   vim.cmd([[
    augroup WordExtmarkPlugin
    autocmd!
    augroup END
   ]])
end

function M.setup(cfg)
   M.config = cfg or M.config or {}

   pcall(function() M:get_filename() end)
   pcall(function() M:get_extmarks_path() end)
   pcall(function() M:get_current_bufnr() end)

   require('audio-recording.nvim_integration').setup(M)
end

return M

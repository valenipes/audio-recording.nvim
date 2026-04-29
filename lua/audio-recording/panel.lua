local M = {}

M.popup_win = nil
M.popup_buf = nil
M.active = false
M.paused = false

function M:send_mpv_command(command)
   local socket = "/tmp/audio_recording_mpv_socket"
   local cmd = string.format(
      "echo '%s' | socat - UNIX-CONNECT:%s 2>/dev/null",
      command,
      socket
   )
   -- vim.notify(cmd, vim.log.levels.WARN)
   vim.fn.system(cmd)
end

local function go_back()
   -- vim.notify("Back pressed", vim.log.levels.WARN)
   M:send_mpv_command('{"command": ["seek", "-5", "relative"]}')
end

local function pause_or_play()
   M:send_mpv_command('cycle pause')
   -- vim.notify("Stop/play pressed", vim.log.levels.WARN)
end

local function go_forward()
   -- vim.notify("Forward pressed", vim.log.levels.WARN)
   M:send_mpv_command('{"command": ["seek", "+5", "relative"]}')
end

local function kill_player()
   -- vim.notify("audio-recording: Player killed from panel", vim.log.levels.WARN)
   M:send_mpv_command('{ "command": ["quit"] }')
   M:close_panel()
end

function M.close_panel()
   if M.active and M.popup_win then
      if vim.api.nvim_win_is_valid(M.popup_win) then
         vim.api.nvim_win_close(M.popup_win, true)
      end

      pcall(function()
         vim.keymap.del({ "i", "n" }, "<C-6>")
         vim.keymap.del({ "i", "n" }, "<C-7>")
         vim.keymap.del({ "i", "n" }, "<C-8>")
         vim.keymap.del({ "i", "n" }, "<C-9>")
      end)

      M.popup_buf = nil
      M.popup_win = nil
      M.active = false
      -- vim.notify("Panel is closed!", vim.log.levels.WARN)
   end
end

function M.open_panel()
   if M.active then
      -- vim.notify("Panel is active!", vim.log.levels.WARN)
      return
   end

   M.popup_buf = vim.api.nvim_create_buf(false, true)

   vim.api.nvim_buf_set_lines(M.popup_buf, 0, -1, false, {
      "CTRL + (6)  (7)  (8)  (9)",
      "            ⏮    ▶    ⏭"
   })

   local width = 25
   local height = 2
   local col = vim.o.columns - width - 1
   local row = vim.o.lines - height - 4

   -- vim.notify("Popup win created!", vim.log.levels.WARN)
   M.popup_win = vim.api.nvim_open_win(M.popup_buf, false, {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
   })
   vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE', fg = 'white' })
   vim.api.nvim_set_option_value("winhl", "Normal:NormalFloat,FloatBorder:NormalFloat", { win = M.popup_win })
   M.active = true

   vim.api.nvim_set_option_value("modifiable", false, { buf = M.popup_buf })
   vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.popup_buf })

   vim.keymap.set({ "i", "n" }, "<C-7>", function()
      go_back()
   end, { noremap = true })

   vim.keymap.set({ "i", "n" }, "<C-8>", function()
      pause_or_play()
   end, { noremap = true })

   vim.keymap.set({ "i", "n" }, "<C-9>", function()
      go_forward()
   end, { noremap = true })

   vim.keymap.set({ "i", "n" }, "<C-6>", function()
      kill_player()
   end, { noremap = true })
end

return M

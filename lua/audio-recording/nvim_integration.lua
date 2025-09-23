local M = {}

function M.setup(core_module)
   local cfg = core_module.config or {}


   vim.api.nvim_create_user_command('Rec', function(opt)
      local cmd = opt.fargs[1]
      if cmd == 'start' then
         core_module:start_recording()
      elseif cmd == 'stop' then
         core_module:stop_recording()
      elseif cmd == 'annotate' then
         core_module:annotate()
      elseif cmd == 'play' then
         core_module:play_current_mark()
      elseif cmd == 'killplayer' then
         core_module:kill_player()
      else
         vim.notify('Uso: :Rec start|stop|annotate|play|killplayer', vim.log.levels.INFO)
      end
   end, {
      nargs = '*',
      force = true,
      complete = function()
         return { 'start', 'stop', 'annotate', 'play', 'killplayer' }
      end,
   })


   vim.keymap.set('n', 'dd', function()
      pcall(function() core_module:del_extmarks_on_cursor() end)
      vim.api.nvim_command('normal! dd')
   end, { silent = true })

   vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
      callback = function()
         -- pcall(function() core_module:get_filename() end)
         -- pcall(function() core_module:get_extmarks_path() end)
         -- pcall(function() core_module:get_current_bufnr() end)
         if cfg.auto_load_extmarks and core_module.state.extmarks_path and vim.fn.filereadable(core_module.state.extmarks_path) == 1 then
            pcall(function() core_module:load_marks_for_buf(core_module.state.current_bufnr) end)
         end
      end,
   })

   vim.api.nvim_create_autocmd('BufWritePost', {
      pattern = '*',
      callback = function(args)
         if vim.fn.filereadable(vim.fn.expand(core_module.state.extmarks_path)) == 1 or core_module.state.has_the_user_added_extmarks then
            local bufnr = args.buf
            pcall(function() core_module:save_marks_for_buf(bufnr) end)
         end
      end
   })
end

return M

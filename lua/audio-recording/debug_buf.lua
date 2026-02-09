local M = {}
M.bufnr = nil

-- creates a new buffer to debug or return its value if the buffer already exists
function M.create()
   if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
      return M.bufnr
   end
   M.bufnr = vim.api.nvim_create_buf(true, true)
   vim.api.nvim_buf_set_name(M.bufnr, 'audio_recording://debug_buffer')
   vim.api.nvim_buf_set_option(M.bufnr, 'bufhidden', 'wipe')
   vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
   return M.bufnr
end

-- writes in the buffer if it exists, returns otherwise
function M.write(item)
  if not (M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr)) then
    vim.notify("Cannot write in debug buffer because it wasn't assigned", vim.log.levels.WARN) -- this should'nt happen
    return
  end
  vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', true)
  local lines
  if type(item) == 'function' then -- if a function can call the function "write", it will pass the bufnr if that function must write in the buffer in a particular way
    lines = item(M.bufnr)
  else
    lines = item
  end
  if type(lines) == 'string' then
    lines = { lines }
  end
  if type(lines) == 'table' then
    vim.api.nvim_buf_set_lines(M.bufnr, -1, -1, true, lines)
  end
  vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
end

return M

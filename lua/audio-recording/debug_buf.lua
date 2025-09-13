local M = {}
M.bufnr = nil

function M.create(filename)
  if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
    vim.api.nvim_buf_set_name(M.bufnr, 'rec://' .. filename)
    return M.bufnr
  end
  M.bufnr = vim.api.nvim_create_buf(true, true) -- buffer listed, scratch (no swapfile)
  vim.api.nvim_buf_set_name(M.bufnr, 'rec://' .. filename)
  vim.api.nvim_buf_set_option(M.bufnr, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
  return M.bufnr
end

function M.write(fn)
  if not (M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr)) then return end
  vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', true)
  fn(M.bufnr)
  vim.api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
end

return M

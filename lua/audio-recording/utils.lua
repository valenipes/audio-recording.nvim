local M = {}

function M.format_timestamp(timestamp)
  return os.date('%Y-%m-%d_%H:%M:%S', timestamp)
end

function M.safe_write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(content)
  f:close()
  return true
end

function M.mkdir_p(path)
  vim.fn.mkdir(path, 'p')
end

return M

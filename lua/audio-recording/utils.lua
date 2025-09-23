local M = {}

M.sep_pattern = "[%s%p]"

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

function M.is_separator(char)
  if not char or char == "" then return true end
  return string.match(char, M.sep_pattern) ~= nil
end

function M.ensure_highlight()
  if vim.fn.hlexists("WordExtmarkDebug") == 0 then
    vim.cmd("hi default WordExtmarkDebug guibg=#1133aa guifg=#ffffff")
  end
end


return M

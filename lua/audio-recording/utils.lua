local M = {}

M.sep_pattern = "[%s%p]"

-- needed to create recording files
function M.format_timestamp(timestamp)
  return os.date('%Y-%m-%d_%H:%M:%S', timestamp)
end

-- needed to write in extmarks file
function M.safe_write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(content)
  f:close()
  return true
end

-- needed to create any directory
function M.mkdir_p(path)
  vim.fn.mkdir(path, 'p')
end

-- checks if a character is a separator, or anything except a character
function M.is_separator(char, col)
  if not char or char == "" then return true end
  return string.match(char, M.sep_pattern) ~= nil
end

-- needed in debug mode to highligh extmarks
function M.ensure_highlight()
  if vim.fn.hlexists("WordExtmarkDebug") == 0 then
    vim.cmd("hi default WordExtmarkDebug guibg=#1133aa guifg=#ffffff")
  end
end


return M

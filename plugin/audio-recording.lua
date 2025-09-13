local ok, ar = pcall(require, 'audio-recording')

if not ok then
  vim.notify('audio-recording: failed to load the main module.', vim.log.levels.WARN)
  return
end

vim.notify("audio-recording: running setup", vim.log.levels.INFO);ar.setup() -- pcall(function() ar.setup() end)


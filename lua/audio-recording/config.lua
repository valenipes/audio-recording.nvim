local defaults = {
  recording_dir = '.recordings/',
  debug_mode = true,
  auto_load_extmarks = true,
}

local M = {
  cfg = vim.deepcopy(defaults)
}

local function normalize_config(cfg)
  cfg.recording_dir = vim.fn.expand(cfg.recording_dir or defaults.recording_dir)
  if cfg.recording_dir:sub(-1) ~= '/' then
    cfg.recording_dir = cfg.recording_dir .. '/'
  end
  if type(cfg.debug_mode) ~= 'boolean' then
    cfg.debug_mode = defaults.debug_mode
  end
  if type(cfg.auto_load_extmarks) ~= 'boolean' then
    cfg.auto_load_extmarks = defaults.auto_load_extmarks
  end
  return cfg
end

function M.setup(user_cfg)
  M.cfg = vim.tbl_deep_extend('force', {}, defaults, user_cfg or {})
  M.cfg = normalize_config(M.cfg)
end

function M.get()
  return M.cfg
end

return M

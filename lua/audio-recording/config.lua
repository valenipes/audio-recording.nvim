local defaults = {
  recording_dir = '.recordings/',
  debug_mode = false,
  auto_load_extmarks = true,
  manual_annotation_mode = true,
  automatic_annotation_word_mode = true, -- not extensively tested
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
  if type(cfg.manual_annotation_mode) ~= 'boolean' then
    cfg.manual_annotation_mode = defaults.manual_annotation_mode
  end
  if type(cfg.automatic_annotation_word_mode) ~= 'boolean' then
    cfg.automatic_annotation_word_mode = defaults.automatic_annotation_word_mode
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

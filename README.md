# 🎤 audio-recording.nvim

Based on [kyouko.nvim](https://github.com/andry-dev/kyouko.nvim/blob/master/README.md) by [@andry-dev](https://github.com/andry-dev).

Alpha plugin to record lectures from within Neovim.

This plugin allows you to record audio from your microphone from within Neovim and also insert the current timestamp as an [extmark](https://neovim.io/doc/user/api.html#extmarks).

A typical use-case is for taking notes for a lecture: maybe you want to record the lecture but you don't want to guess where a passage is in the audio file.

With audio-recording.nvim you can annotate - manually or automatically - where exactly a phrase in the lecture was said, so it's easier to find later on.

## Requirements

Right now, the plugin only works with Linux (Pipewire) and with `opus-tools` installed (needs `opusenc`).

This plugin uses Plenary's Job API, so you need [plenary.nvim](nvim-lua/plenary.nvim) installed.

## Installation and configuration

For [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
   'valenipes/audio-recording.nvim',
   lazy = false,
   dependencies = {
      'nvim-lua/plenary.nvim'
   },
   opts = {
      recording_dir = '.recordings/', -- directory path for recordings and extmarks
      debug_mode = false,             -- if true, it will generate a buffer with some info on current recording
      auto_load_extmarks = true,      -- if true, it will load extmarks from previous 
   },
   -- Uncomment and customize if needed.
   -- keys = {
   --    { "<leader>r", "<cmd>Rec start<cr>", desc = "Start a recording." },
   --    { "<leader>a", "<cmd>Rec annotate<cr>", desc = "Insert timestamp as an extmark at the end of the line." },
   --    { "<leader>s", "<cmd>Rec stop<cr>", desc = "Stop a recording." },
   -- }
}
```

For [Packer](https://github.com/wbthomason/packer.nvim) (not tested):

```lua
use {
  'valenipes/audio-recording.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('audio-recording').setup({
      recording_dir = '.recordings/', -- directory path for recordings and extmarks
      debug_mode = false,             -- if true, it will generate a buffer with some info on current recording
      auto_load_extmarks = true,      -- if true, it will load extmarks from previous 
    })
    -- { "<leader>r", "<cmd>Rec start<cr>", desc = "Start a recording." },
    -- { "<leader>a", "<cmd>Rec annotate<cr>", desc = "Insert timestamp as an extmark at the end of the line." },
    -- { "<leader>s", "<cmd>Rec stop<cr>", desc = "Stop a recording." },
  end
}
```

And you're done! Just use one of the subcommands of `:Rec`:

 - `:Rec start` starts recording from your main microphone.
   The recording is saved inside a `.recordings/` directory in the current working directory. The name of the file is generated from the current ISO date and time and its extension is OGG (Opus/Vorbis).

   <!-- Only in debug mode, FIXME -->
   <!-- A buffer will be created with URI `rec://` where you can see some  -->
   <!-- info about the recording.  -->



https://github.com/user-attachments/assets/5e68e388-83c0-41bf-acb6-6174ea58261f


 - `:Rec annotate` adds the current timestamp as an extmark at the end of the line. This is useful when taking lecture notes to know where in the recording a passage was said. Extmarks are saved on a file generated inside `.recordings/`.


https://github.com/user-attachments/assets/6570367f-f36d-42c2-8f2b-a77a1f19cb36


 - `:Rec stop` stops the current recording.

   <!-- This does not close the `rec://` buffer. -->

## WIP
 
 - [ ] Add an option to insert a timestamp on each <CR> in insert mode.
 - [ ] Associate a word to a timestamp and play the audio from there.

## TODO

 - [ ] Support other sound servers.
 - [ ] Keybindings.


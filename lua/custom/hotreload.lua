-- hotreload.lua
--
-- Source: Adapted from Richard Gill's dotfiles
-- https://github.com/richardgill/nix/blob/bdd30a0/modules/home-manager/dot-files/nvim/lua/custom/hotreload.lua
-- Licensed under MIT License
-- Original inspiration: https://github.com/diogo464/hotreload.nvim
--
-- Auto-reload buffers when files change externally (e.g., Claude Code edits).
--
-- Problem:
-- Neovim's `autoread` option only checks files on specific events (like switching
-- windows or focusing the terminal). When Claude Code or other tools write files
-- in the background while you're in Neovim, nothing triggers a reload.
--
-- Solution:
-- 1. Watch the filesystem for changes (via directory-watcher.lua)
-- 2. Set up autocmds for FocusGained, CursorHold, etc. as fallbacks
-- 3. Run `checktime` to reload changed buffers
--
-- Safety features:
-- - Only reloads visible buffers (not hidden ones)
-- - Never overwrites unsaved changes (skips modified buffers)
-- - Skips special buffers (terminals, quickfix, plugin URIs like diffview://)
-- - Skips reload during certain modes (command-line, replace) to avoid disruption
--
-- Performance: Negligible. checktime just compares file timestamps.

local M = {}

-- Check if we're in a mode where reloading is safe
-- Skips command-line, replace, ex, and select modes to avoid disrupting user input
local function should_check()
  local mode = vim.api.nvim_get_mode().mode
  return not (
    mode:match '[cR!s]' -- Skip: command-line, replace, ex, select modes
    or vim.fn.getcmdwintype() ~= '' -- Skip: command-line window is open
  )
end

-- Determine if a buffer should be reloaded
-- Only reload buffers that are:
-- - Real files (not plugin URIs like diffview://, fugitive://, oil://)
-- - Normal buffers (not terminal, quickfix, help, etc.)
-- - Not modified (never overwrite unsaved changes)
local function should_reload_buffer(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
  local modified = vim.api.nvim_get_option_value('modified', { buf = buf })
  local is_real_file = name ~= '' and not name:match '^%w+://' -- Skip URIs

  return is_real_file and buftype == '' and not modified
end

-- Get buffers that are currently visible in any window
-- We only reload visible buffers to avoid unexpected changes to hidden buffers
local function get_visible_buffers()
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    visible[vim.api.nvim_win_get_buf(win)] = true
  end
  return visible
end

-- Find a buffer by its full filepath (only among visible buffers)
local find_buffer_by_filepath = function(filepath)
  local visible_buffers = get_visible_buffers()
  for buf, _ in pairs(visible_buffers) do
    if vim.api.nvim_buf_get_name(buf) == filepath then
      return buf
    end
  end
  return nil
end

-- Register handler for file changes detected by directory-watcher
-- This is called whenever a file changes in the watched directory
require('custom.directory-watcher').registerOnChangeHandler('hotreload', function(filepath, events)
  if not should_check() then
    return
  end

  local buf = find_buffer_by_filepath(filepath)
  if buf and should_reload_buffer(buf) then
    vim.cmd('checktime ' .. buf)
  end
end)

-- Set up autocmds as fallback triggers for checktime
-- These handle cases like alt-tabbing back to Neovim, or when the cursor is idle
M.setup = function(opts)
  vim.api.nvim_create_autocmd({ 'FocusGained', 'TermLeave', 'BufEnter', 'WinEnter', 'CursorHold', 'CursorHoldI' }, {
    group = vim.api.nvim_create_augroup('hotreload', { clear = true }),
    callback = function()
      if should_check() then
        vim.cmd 'checktime'
      end
    end,
  })
end

return M

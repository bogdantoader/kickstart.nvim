-- directory-watcher.lua
--
-- Source: Adapted from Richard Gill's dotfiles
-- https://github.com/richardgill/nix/blob/bdd30a0/modules/home-manager/dot-files/nvim/lua/custom/directory-watcher.lua
-- Licensed under MIT License
--
-- A low-level filesystem watcher using Neovim's built-in vim.uv (libuv bindings).
--
-- Purpose:
-- Neovim has no built-in way to watch arbitrary directories for changes.
-- This module provides that capability using the native libuv API.
--
-- How it works:
-- - uv.new_fs_event() creates a native OS filesystem watcher
-- - fs_event:start(path, ...) watches a directory for changes (create, modify, delete)
-- - The OS notifies us of changes (event-driven, not polling) - very lightweight
-- - Debouncing (100ms default) prevents callback storms during rapid saves
-- - Named handlers allow other modules to register callbacks without duplicates
--
-- Performance: Negligible. The watcher is passive - it just listens for OS
-- notifications about file changes, no active scanning or polling.

local M = {}

local uv = vim.uv
local watcher = nil
local debounce_timer = nil
local on_change_handlers = {}

-- Debounce helper to prevent callback storms
-- When a file changes rapidly (e.g., editor saves multiple times),
-- this waits for the specified delay before firing the callback
local debounce = function(fn, delay)
  return function(...)
    local args = { ... }
    if debounce_timer then
      debounce_timer:close()
    end
    debounce_timer = vim.defer_fn(function()
      debounce_timer = nil
      fn(unpack(args))
    end, delay)
  end
end

-- Register a named handler to be called when files change
-- If a handler with the same name exists, it will be replaced.
-- Named handlers are required to support Lua hotreload - when a file is reloaded,
-- it re-registers its handler with the same name, replacing the old one instead of
-- creating duplicates.
M.registerOnChangeHandler = function(name, handler)
  on_change_handlers[name] = handler
end

-- Start watching a directory for file changes
-- opts.path: directory to watch (required)
-- opts.debounce: debounce delay in ms (default: 100)
M.setup = function(opts)
  opts = opts or {}
  local path = opts.path
  local debounce_delay = opts.debounce or 100 -- ms

  if not path then
    return false
  end

  -- Stop existing watcher if any
  if watcher then
    M.stop()
  end

  -- Create fs_event handle using libuv
  local fs_event = uv.new_fs_event()
  if not fs_event then
    return false
  end

  -- Debounced callback for file changes
  local on_change = debounce(function(err, filename, events)
    if err then
      M.stop()
      return
    end

    if filename then
      local full_path = path .. '/' .. filename

      -- Call all registered handlers
      for _, handler in pairs(on_change_handlers) do
        pcall(handler, full_path, events)
      end
    end
  end, debounce_delay)

  -- Start watching (recursive = false, only watches immediate directory)
  -- vim.schedule_wrap ensures callbacks run in the main Neovim thread
  local ok, err = fs_event:start(path, { recursive = true }, vim.schedule_wrap(on_change))

  if ok ~= 0 then
    return false
  end

  watcher = fs_event
  return true
end

-- Stop the watcher and clean up resources
M.stop = function()
  if watcher then
    watcher:stop()
    watcher = nil
  end

  if debounce_timer then
    debounce_timer:close()
    debounce_timer = nil
  end
end

return M

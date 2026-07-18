-- Tiny dependency-free test runner for headless Neovim.
-- Usage:
--   tests/scripts/setup-notmuch-db.sh
--   nvim --headless -u tests/test-init.lua -l tests/run.lua

local spec_files = {
  -- Phase 1: pure/unit-style coverage.
  "tests/specs/base64_spec.lua",
  "tests/specs/util_spec.lua",
  "tests/specs/mime_spec.lua",
  "tests/specs/completion_spec.lua",
  "tests/specs/handlers_spec.lua",
  "tests/specs/attach_commands_spec.lua",
  "tests/specs/attach_state_spec.lua",
  "tests/specs/attach_scratch_spec.lua",
  "tests/specs/attach_parts_spec.lua",
  "tests/specs/config_spec.lua",
  "tests/specs/draft_spec.lua",
  "tests/specs/sync_spec.lua",
  "tests/specs/async_spec.lua",
  "tests/specs/send_spec.lua",
  "tests/specs/thread_spec.lua",
  "tests/specs/tag_spec.lua",
  "tests/specs/refresh_spec.lua",
  "tests/specs/delete_spec.lua",
  "tests/specs/attach_incoming_modules_spec.lua",
  "tests/specs/attach_incoming_attachment_spec.lua",
  "tests/specs/attach_incoming_rules_spec.lua",
  "tests/specs/attach_incoming_extractor_spec.lua",
  "tests/specs/attach_incoming_defaults_spec.lua",
  "tests/specs/attach_incoming_opener_spec.lua",
  "tests/specs/attach_incoming_viewer_spec.lua",
  "tests/specs/attach_incoming_renderer_spec.lua",
  "tests/specs/attach_incoming_spec.lua",

  -- Buffer/UI and integration coverage.
  "tests/specs/init_spec.lua",
  "tests/specs/ftplugin_spec.lua",

  -- Existing smoke/integration coverage.
  "tests/specs/smoke_spec.lua",
  "tests/specs/cnotmuch_spec.lua",
  "tests/specs/ui_spec.lua",
}

local tests = {}
for _, file in ipairs(spec_files) do
  local loaded = dofile(file)
  for _, test in ipairs(loaded) do
    test.file = file
    table.insert(tests, test)
  end
end

local failures = {}
local started = vim.uv.hrtime()

print(string.format("Running %d notmuch.nvim tests", #tests))

for i, test in ipairs(tests) do
  local ok, err = xpcall(test.run, debug.traceback)
  if ok then
    print(string.format("ok %02d - %s", i, test.name))
  else
    print(string.format("not ok %02d - %s", i, test.name))
    table.insert(failures, {
      name = test.name,
      file = test.file,
      err = err,
    })
  end
end

local elapsed_ms = (vim.uv.hrtime() - started) / 1e6

if #failures > 0 then
  print(string.format("\n%d failure(s):", #failures))
  for i, failure in ipairs(failures) do
    print(string.format("\n%d) %s (%s)\n%s", i, failure.name, failure.file, failure.err))
  end
  print(string.format("\nFAILED in %.1fms", elapsed_ms))
  vim.cmd("cquit 1")
else
  print(string.format("\nPASS in %.1fms", elapsed_ms))
  vim.cmd("quitall!")
end

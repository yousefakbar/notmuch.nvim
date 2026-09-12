# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added StyLua formatter configuration, Makefile format/lint targets, and a GitHub Actions formatting check.
- Added configurable `send.send_mode` with `terminal` and `background` modes for sending mail through `msmtp`.
- Rule-based received attachment configuration for cache-backed open/view behavior:
  - `attachments.open`, `attachments.view`, `attachments.window`, and `attachments.cache_dir` provide the primary user-facing shorthand
  - `attach.incoming.open.rules` and `attach.incoming.view.rules` remain available as the advanced rule patch API
- New `thread_auto_expand` config option for opening no message folds, the first fold, or all folds when entering a thread

### Changed

- Thread buffers now place the cursor on the first message when opened or reused
- Replaced deprecated `vim.loop` usage with `vim.uv` for Neovim libuv APIs.
- Received attachment open/view actions now use deterministic cache extraction and rule registries instead of top-level handler callbacks.
- Received attachment open, view, and save extraction now streams through temporary files and atomically publishes completed files.
- The default received attachment opener now prefers `vim.ui.open()` when available and falls back to the OS opener command.

### Removed

- Removed the unused `:FollowPatch` command and `U` URL-extraction mapping, including the optional `:YTerm`/`urlextract` integration.
- Removed the unused internal `notmuch.float` module. Floating attachment viewing is handled directly by the attachment viewer.
- Removed top-level received attachment `open_handler` and `view_handler` configuration callbacks in favor of `attachments.open`/`attachments.view` rules, with `attach.incoming.*` available for advanced patching.
- Removed the legacy `lua/notmuch/handlers.lua` callback implementation.

## [0.4.0] - 2026-07-12

### Added

- Saved/pinned queries for the `:Notmuch` dashboard via the new `queries` setup option
  - Saved queries are displayed above tags, can be opened with `<CR>`, and can be counted with `c`
  - Invalid query entries are skipped with a warning during setup
  - Dashboard syntax highlighting and documentation now cover the Saved/Pinned section
- `notmuch.open_hello_line()` and `notmuch.count_hello_line()` helpers for resolving dashboard actions across saved queries and tag lines
- Full headless Neovim test suite covering core modules, ftplugins, UI flows, and end-to-end notmuch workflows
- Disposable notmuch fixture database setup using bundled mail corpora under `tests/fixtures/corpora`
- Dependency-free Lua test runner and shared test helpers under `tests/`
- Test setup and cleanup scripts for generated notmuch state under `tests/tmp`
- `Makefile` targets for dependency checks, test database setup, test execution, cleanup, and CI entrypoint (`make check`)
- GitHub Actions workflow to run the test suite on pull requests, pushes to `main`/`master`, and manual dispatches
- New `thread_view_mode` config option for controlling message display in thread view:
  - `"threaded"` preserves the original notmuch thread tree structure with reply nesting and indentation
  - `"newest-first"` flattens messages and sorts them chronologically newest to oldest
  - `"oldest-first"` flattens messages and sorts them chronologically oldest to newest
- Persistent compose and reply draft storage under configurable `drafts.folder`
  - Draft content is stored as `.eml` files with JSON sidecars for metadata and outgoing attachment paths
  - Sent drafts are hidden from pickers by default and can be deleted after successful send with `drafts.delete_sent`
- `:NotmuchDrafts` command and dashboard `D` mapping for a global compose/reply draft picker
- Buffer-local draft attachment commands for both compose and reply drafts:
  - `:Attach {path}`
  - `:AttachRemove {path}`
  - `:AttachList`
  - `:AttachOpen`
- New `drafts.auto_open_attachment_window` option to control whether draft attachment scratch windows open automatically

### Changed

- `notmuch-hello` mappings now route through dashboard-aware helpers so header/separator lines are ignored and saved queries use their configured search terms
- `notmuch-hello` count results now use `vim.notify()` instead of `print()`
- Buffer-local commands created by Lua ftplugins now use `force = true` so re-sourcing ftplugins can replace existing commands cleanly
- Migrated ftplugin files from Vimscript to Lua (`mail`, `notmuch-attach`, `notmuch-hello`, and `notmuch-threads`)
- Deleting threads from the thread list now removes them from the buffer immediately
- Generated test state is now ignored by git
- Compose/reply sending now builds temporary outbound send artifacts so persistent draft `.eml` files are not mutated into MIME send output
- Outgoing draft attachment handling now uses one shared state model backed by the draft JSON sidecar and mirrored in `vim.b.notmuch_attachments`
- Attachment-related Lua modules are now namespaced under `notmuch.attach`:
  - `notmuch.attach` is the outgoing draft attachment facade
  - `notmuch.attach.commands` owns draft attachment commands
  - `notmuch.attach.state` owns canonical draft attachment state
  - `notmuch.attach.scratch` owns the draft attachment scratch window
  - `notmuch.attach.parts` owns received-message MIME part listing/opening/saving

### Fixed

- Attachment filenames with `/` characters are now sanitized to prevent directory path errors when saving
- Async notmuch search now reports stderr output instead of silently ignoring it
- Attachment part lookup now handles buffers without `mime_parts_list` gracefully
- `:AttachRemove` now normalizes expanded paths before matching attachments
- Failed maildir syncs now use error-level notifications
- Message tag operations now return before opening a writable database when no current message is available
- Thread tag operations now skip non-thread lines safely and parse thread IDs more robustly
- Empty or missing message headers now use fallback header values instead of rendering blank values
- Draft attachment scratch buffers and attachment commands now stay synchronized through shared sidecar-backed state

## [0.3.0] - 2026-02-11

### Added

- HTML body rendering via `w3m` for `multipart/alternative` emails
  - New `render_html_body` config option (default: `false`)
  - Graceful fallback when `w3m` is not installed
- New `thread.lua` module for JSON-based thread display parsing
- Per-message tag display in thread view header
- Attachment count indicator (📎) in message headers
- MIME part markers in message body for attachments and HTML content
- Buffer-local variables for thread metadata (enables statusline integration and user extensibility)
  - `vim.b.notmuch_thread` - Thread-level metadata (ID, subject, tags, authors, message count)
  - `vim.b.notmuch_messages` - Array of all messages in thread with metadata
  - `vim.b.notmuch_current` - Cursor-tracked current message data with position info
  - `vim.b.notmuch_status` - Formatted statusline string showing message position and sender
- FFI bindings for `notmuch_database_open_with_config` (notmuch 5.4+/API 0.32+)
- Automatic notmuch version detection at module load with result caching
- Warning notification when using deprecated API (notmuch < 0.32)
- Configuration option `suppress_deprecation_warning` to suppress API deprecation warnings
- Optional email address argument for `:Inbox` command to filter by recipient (`to:` field)
  - Includes autocomplete for email addresses from notmuch database
- New `"terminal"` sync mode for `sync.sync_mode` — real PTY terminal with stdin support for GPG passphrase prompts and OAuth flows

### Changed

- Thread display now uses `notmuch show --format=json` instead of raw text parsing
  - More robust parsing immune to text format changes
  - Proper handling of complex MIME structures (multipart/mixed, multipart/alternative)
  - Concatenates multiple inline text parts (body, signatures, mailing list footers)
  - Now fetches HTML content (`--include-html`) for optional rendering
- Message ID lookup now uses buffer-local variables instead of regex parsing
  - Replaces `util.find_cursor_msg_id()` with `thread.get_current_message_id()`
  - Cursor position automatically tracked via `CursorMoved` autocmd
  - Eliminates redundant buffer scans for message operations
- Database opening now uses `notmuch_database_open_with_config` when available, with fallback to deprecated `notmuch_database_open`
- Version detection runs once at module load for improved performance
- **Major refactoring**: Completed migration from Vimscript to pure Lua implementation
  - Deleted `plugin/notmuch.vim` and `autoload/notmuch.vim` (Vimscript plugin files)
  - Ported all command definitions to Lua using `vim.api.nvim_create_user_command`
  - Ported command-line completion functions from Vimscript to Lua module (`completion.lua`)
  - Completion functions now filter results based on user input for better UX
  - Removed dependency on Vimscript autoload functions and global Vim command registration
- Attachment view handler now uses `vim.system()` for table-format commands (more secure and modern)
- MIME type pattern matching in attachment handlers now uses anchored patterns for more precise matching and better performance

### Deprecated

- `util.process_msgs_in_thread()` - replaced by `thread.show_thread()` with JSON parsing

### Fixed

- Correct notmuch version number detection (checks API version 0.32 instead of library version 5.4)
- Attachment view handler now correctly detects command success using exit codes instead of relying solely on `vim.v.shell_error`
- Buffer validity checks before write operations to prevent errors when buffer is deleted during async operations
- Exact buffer name matching using escaped regex patterns to prevent partial matches when switching to existing search buffers
- Corrected thread count upon search completion
- Terminal window positioning for sync (bottom-right)

### Performance

- Kill notmuch search process when the buffer is deleted (avoids orphaned processes)
- Anchored patterns in attachment handlers for more precise MIME type matching

### Documentation

- Installation instructions for Neovim v0.12+ builtin package manager (`vim.pack.add`)
- Buffer-local variables reference in README and help docs (`:help notmuch-buffer-variables`)
- `render_html_body` configuration option with w3m dependency note
- `w3m` listed as optional dependency for HTML rendering

## [0.2.0] - 2026-01-09

### Added

- Sort toggle (`o` keymap) in thread results buffer to reverse search order (newest-first ↔ oldest-first)
- Exit code detection and auto-close terminal on successful email send
- In-buffer attachment viewer for text-based files (text, markdown, PDFs)
- Dedicated `handlers.lua` module with comprehensive file type support for attachments
  - OS-aware external opening (macOS, Linux, Windows)
  - Graceful fallbacks for HTML, PDF, images, Office documents, markdown, and archives
- Interactive save prompt for attachments with validation
  - Directory validation and writability checks
  - Overwrite confirmation
  - Path expansion support (~, environment variables)
- Hints line in `notmuch-attach` buffers with syntax highlighting
- Attachment support for composing mail via `<C-g><C-a>` keymap
- Attachment support for replies using command-based interface
  - `:Attach`, `:AttachList`, `:AttachRemove` commands with tab completion
- MIME message builder for multipart emails with attachments
- Improved msmtp logging and multi-account support
  - `logfile` config option for msmtp
  - `--read-envelope-from` flag for multiple sending accounts
- Delete functionality for threads
  - `:DelThread` command (bound to `dd` in normal mode, `d` in visual mode)
  - `D` key to preview deletion, `DD` to confirm purge
- Enhanced search term autocompletion
  - Added `is:`, `to:`, `from:`, `body:`, and logical expressions (`and`, `or`, `not`)
  - Autocomplete for `mimetype:`, `to:`, `from:`, `path:`, and `folder:` search
- `:ComposeMail` now accepts optional recipient with autocomplete
- Visual mode support for tag operations (`+`, `-`, `=`, `a`, `A`, `x`) in threads view
- `f` key binding to toggle `flagged` tag in threads view (normal and visual mode)
- Fail-fast validation for notmuch configuration on plugin load
- Hint in compose message body showing attachment window keymap

### Changed

- **BREAKING**: Renamed `open_cmd` config option to `open_handler` (now a callback function)
- Send email now uses terminal buffer instead of background process
- Path expansion for user-override `notmuch_db_path` config (handles `~` and relative paths)
- Attachment listing now uses JSON parsing instead of grep for reliability
  - Recursive MIME tree parsing
  - Accurate part IDs, filenames, sizes, and disposition indicators
- Sync operation improvements
  - Now runs asynchronously
  - Displays sync command and user-friendly status text
  - Statusline notifications on success/failure
  - `<C-c>` cancellation only works when sync is running
- Tag command mappings now include trailing space for better UX
- Single-part MIME for plaintext emails without attachments
- Optimized bulk thread tagging by reusing database connection (reduces N connections to 1)
- Sync mode configuration now uses `sync.sync_mode` structure

### Fixed

- Buffer write notifications silenced during email composition
- Removed duplicate `s` keymap for saving attachment parts
- Visual mode mappings reverted to `:` prefix instead of `<Cmd>`
- Keymap definitions now use `<Cmd>` for better reliability
- Cross-platform tempfile creation using `vim.fn.tempname()` instead of `mktemp`
- Message ID sanitization for reply filenames (prevents invalid file paths)
- View attachment floating buffer now properly unlisted
- Last-ditch fallback added when filetype not supported in view handler
- Attachment handling now uses `vim.split` instead of custom string splitting
- Shell-escaped naming for attachment paths
- Sync cancellation keymap race condition
- UI sync export issue
- Tag operations now use `nnoremap` instead of `nmap` to prevent conflicts
- Compose buffer content retained if attachment validation fails
- Attachment validation now checks for existence and accessibility
- Body content no longer parsed as email headers (RFC 5322 compliance)
  - Added support for header continuation (folded headers)
- Empty lines in attachment buffer no longer cause errors
- MIME module function naming issues
- Cross-platform folder/path autocomplete with special character support
  - Removed BSD-incompatible `sed -z`
  - Added shell injection protection
  - Auto-quotes paths with spaces or brackets

### Security

- Fixed command injection vulnerability in `sendmail()` function
  - Replaced string concatenation with proper argument escaping
  - Now uses `vim.fn.system()` with array arguments

## [0.1.0] - 2025-01-18

Initial (informal) baseline release.

[Unreleased]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yousefakbar/notmuch.nvim/commit/e4b0a6cbbe5e5281f7a6a8fa43c3e776d3eaec64

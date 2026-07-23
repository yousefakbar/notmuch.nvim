--- notmuch.thread -- Thread display module for notmuch.nvim
---
--- Fetches thread data via `notmuch show --format=json` and transforms it into
--- buffer lines with fold markers, formatted headers, and rendered body
--- content.
---
--- Handles MIME tree walking for multipart messages, with optional HTML
--- rendering via w3m when `config.options.render_html_body` is enabled.
---
--- Anatomy of a thread object from `notmuch show --format=json` output:
---
--- [                    -- Array of threads
---   [                  -- Thread (single element for `notmuch show thread:X`)
---     [                -- Message tree (array of messages at same depth)
---       {              -- Message object (root message)
---         "id": "...",
---         "headers": {...},
---         "body": [...],
---       },
---       [...]          -- Replies array (recursive nodes)
---     ]
---   ]
--- ]
---
--- TL;DR:
--- json[1][1] is the root *node* -> [message_object, [replies_array]]
---
--- During the fetching and parsing of thread JSON data, some useful information
--- is stored in buffer-local variables for user extensibility (e.g. statusline
--- integration and so on):
---
--- `vim.b.notmuch_thread`          : Current thread metadata
--- `vim.b.notmuch_messages`        : Array of message objects inside thread
--- `vim.b.notmuch_current`         : Cursor-tracked current message data
--- `vim.b.notmuch_status`          : Formatted string for quick statusline

local T = {}
local config = require("notmuch.config")

--------------------------------------------------------------------------------
-- PRIVATE: Thread parsing helpers
--------------------------------------------------------------------------------

--- Recursively checks MIME tree for parts with filenames (attachments)
--- @param body table Array of body part objects from notmuch JSON output
--- @return boolean, integer
local function has_attachments(body)
  if not body or #body == 0 then
    return false, 0
  end

  local count = 0

  -- Recursively walk the MIME tree and check for `filename` for attachments
  local function walk(parts)
    for _, part in ipairs(parts) do
      if part.filename then
        count = count + 1
      end
      if type(part.content) == "table" then
        walk(part.content)
      end
    end
  end

  walk(body)
  return count > 0, count
end

--- Indents a summary line based on depth in thread reply chain
--- @param line string Line to indent
--- @param depth number Reply depth (0 for root)
--- @return string indented Indented line with depth prefix
local function indent_line(line, depth)
  if depth == 0 then
    return line
  end
  return string.rep("────", depth) .. line
end

--- Formats message headers into buffer lines
--- Creates the summary line and detailed headers
--- @param msg table Message object from notmuch JSON output
--- @param depth number Message depth in thread chain for indentation
--- @return table Array of formatted header lines
local function format_headers(msg, depth)
  local lines = {}
  local headers = msg.headers or {}

  -- Helper to remove folded lines (RFC 2822)
  local function unfold(s)
    if not s or s == "" then
      return nil
    end
    return s:gsub("\r?\n%S*", " ")
  end

  -- Extract header values with fallbacks
  local from = unfold(headers.From) or "[Unknown sender]"
  local subject = unfold(headers.Subject) or "[No subject]"
  local to = unfold(headers.To) or ""
  local cc = unfold(headers.Cc)
  local date_full = unfold(headers.Date) or ""
  local date_relative = unfold(msg.date_relative) or ""

  -- Get tags and attachment info
  local tags = msg.tags or {}
  local tags_str = table.concat(tags, " ")
  local has_attach, attach_count = has_attachments(msg.body)

  -- Format summary line with indendation depth indicator
  local summary = string.format("%s (%s) (%s)", from, date_relative, tags_str)
  table.insert(lines, indent_line(summary, depth))

  -- Fold start marker with message ID
  table.insert(lines, string.format("id:%s {{{", msg.id))

  -- Add detailed headers
  table.insert(lines, "Subject: " .. subject)
  table.insert(lines, "From: " .. from)
  if to ~= "" then
    table.insert(lines, "To: " .. to)
  end
  if cc then
    table.insert(lines, "Cc: " .. cc)
  end
  table.insert(lines, "Date: " .. date_full)

  -- Add attachment indicator if applicable
  if has_attach then
    table.insert(
      lines,
      string.format("📎 %d attachment%s", attach_count, attach_count > 1 and "s" or "")
    )
  end

  -- Blank link after headers
  table.insert(lines, "")

  return lines
end

--- Renders HTML body content and returns as lines
--- @param raw string Raw HTML content from email body part
--- @return table rendered Rendered HTML ready for buffer display
local function render_html(raw)
  -- Check if `w3m` is installed and in $PATH for user (otherwise render fails)
  if vim.fn.executable("w3m") ~= 1 then
    return { "[ w3m not installed - press 'a' to view attachments ]" }
  end

  -- Run w3m to render the `raw` HTML content
  local ok, res = pcall(function()
    return vim
      .system({ "w3m", "-T", "text/html", "-dump" }, {
        text = true,
        stdin = raw,
      })
      :wait()
  end)

  -- Check for error. Return UX hint rather than vim error
  if not ok or res.code ~= 0 then
    return { "[ Failed to render HTML - press 'a' to view attachments ]" }
  end

  -- Return table of rendered HTML with trimmed empty lines at start/end
  return vim.split(res.stdout or "", "\n", { plain = true, trimempty = true })
end

--- Processes the MIME body parts and adds them to buffer lines
---
--- Walks the MIME tree and handles each part type appropriately:
--- - multipart/*: Recurses into child parts
--- - text/* (inline): Adds content directly
--- - attachments (with filename): Adds marker with filename and hint
--- - other inline (images, etc): Adds type marker
---
--- @param body table MIME part objects from notmuch JSON output
--- @return table lines Array of buffer lines for the message body
local function process_body_parts(body)
  local lines = {}

  local function walk(parts, parent_type)
    for _, part in ipairs(parts) do
      local content_type = part["content-type"] or ""

      if content_type:match("^multipart/") then
        -- Multipart envelope -> recurse through child parts
        walk(part.content, content_type)
      elseif part.filename then
        -- Definitely an attachment -> display to user and hint for viewing
        table.insert(
          lines,
          string.format(
            "[ 📎 %s (%s) - press 'a' to view attachments ]",
            part.filename,
            content_type
          )
        )
        table.insert(lines, "")
      elseif content_type == "text/plain" and part.content then
        if parent_type ~= "multipart/alternative" or not config.options.render_html_body then
          -- Always show inline plain text (including signatures, etc.)
          for _, line in ipairs(vim.split(part.content, "\n", { plain = true })) do
            table.insert(lines, line)
          end
          table.insert(lines, "")
        end
      elseif content_type == "text/html" and part.content then
        if not config.options.render_html_body then
          -- User prefers plain text output. Hide HTML content with hint marker
          if parent_type == "multipart/alternative" then
            table.insert(lines, "[ text/html (alternative) - press 'a' to view ]")
            table.insert(lines, "")
          else
            table.insert(lines, "[ text/html (hidden) - press 'a' to view ]")
            table.insert(lines, "")
          end
        else -- config.options.render_html_body == true
          local html_content = render_html(part.content)
          vim.list_extend(lines, html_content)
          table.insert(lines, "")
        end
      elseif part.content then
        table.insert(
          lines,
          string.format("[ %s (inline) - press 'a' to view attachments ]", content_type)
        )
        table.insert(lines, "")
      end
    end
  end

  walk(body, nil)
  return lines
end

--- Recursively processes a message and its replies into buffer lines
--- @param msg_node table Message node from notmuch JSON: [msg, [replies]]
--- @param depth number Message depth in the thread chain (0 for root message)
--- @param lines table Accumulator array for buffer lines (modified in place)
--- @param metadata table Accumulator array for thread metadata for buffer var
--- @param skip_replies boolean If true, don't process replies recursively (for flattened view)
local function build_message_lines(msg_node, depth, lines, metadata, skip_replies)
  -- Unpack msg_node into message and list of replies
  local msg = msg_node[1]
  local replies = msg_node[2] or {}

  -- Keep an offset of the header at the top of the buffer (hints + blank line)
  local HEADER_OFFSET = 2

  -- Update thread metadata with this message metadata
  metadata.thread.message_count = metadata.thread.message_count + 1

  -- Track the message's starting line number (where summary is shown)
  local start_line = #lines + 1 + HEADER_OFFSET

  -- Update tags seen in the thread
  for _, tag in ipairs(msg.tags) do
    metadata.thread._tags_set[tag] = true
  end

  -- Add author into metadata list
  local from = (msg.headers or {}).From
  if from and from ~= "" then
    metadata.thread._authors_seen[from] = true
  end

  -- Parse and prepare header lines
  local headers = format_headers(msg, depth)
  vim.list_extend(lines, headers)

  -- Track message fold starting line (line with '{{{' fold opening marker)
  local fold_line = start_line + 1

  -- Extract body and content
  local body = process_body_parts(msg.body)
  vim.list_extend(lines, body)

  -- Add fold end marker
  table.insert(lines, "}}}")

  -- Track message's last line (line with fold closing marker '}}}'
  local end_line = #lines + HEADER_OFFSET

  -- Add blank line separator after message
  table.insert(lines, "")

  -- Add message entry into the metadata list of messages
  table.insert(metadata.messages, {
    id = msg.id,
    start_line = start_line,
    fold_line = fold_line,
    end_line = end_line,
    depth = depth,
    from = (msg.headers or {}).From or "",
    date_relative = msg.date_relative or "",
    subject = (msg.headers or {}).Subject or "",
    tags = msg.tags or {},
    attachment_count = select(2, has_attachments(msg.body)),
  })

  -- Process replies recursively (only if not skipping)
  if not skip_replies and replies and #replies > 0 then
    -- Process replies in original order (maintaining hierarchy)
    for _, reply_node in ipairs(replies) do
      build_message_lines(reply_node, depth + 1, lines, metadata, false)
    end
  end
end

--------------------------------------------------------------------------------
-- PRIVATE: Buffer variable builders
--------------------------------------------------------------------------------

--- Get message in the thread from the given line number
--- @param line? number Line number in the buffer. 0 refers to cursor line)
--- @return table|nil message Message object or nil if none is found
--- @return number|nil index 1-based index of the message in the thread or nil
local function get_message_at_line(line)
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local messages = vim.b.notmuch_messages
  if not messages then
    return nil, nil
  end

  -- Find corresponding message (`line` is within message start/end bounds)
  for i, msg in ipairs(messages) do
    if line >= msg.start_line and line <= msg.end_line then
      return msg, i
    end
  end

  -- Not found
  return nil, nil
end

--- Update current message tracker variable based on cursor line position
--- Updates vim.b.notmuch_current and vim.b.notmuch_status
--- If cursor is out of bounds (at the top or between messages) it will display
--- the *next* message as the current message
local function update_current_message()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local current = vim.b.notmuch_current

  -- Fast check: cursor is still in same message
  if current and line >= current.start_line and line <= current.end_line then
    return
  end

  -- Find message at cursor
  local msg, index = get_message_at_line(line)

  -- If cursor is not in a message, find next message after cursor
  if not msg then
    local messages = vim.b.notmuch_messages
    if messages then
      for i, m in ipairs(messages) do
        if m.start_line > line then
          msg, index = m, i
          break
        end
      end
    end
  end

  -- Still no message found (shouldn't happen but need nil check)
  if not msg then
    vim.b.notmuch_current = nil
    vim.b.notmuch_status = ""
    return
  end

  -- Update current message buffer variable
  local total = #vim.b.notmuch_messages
  vim.b.notmuch_current = vim.tbl_extend("force", msg, {
    index = index,
    total = total,
  })

  -- Format status string
  local from_name = msg.from:match("^([^<]+)") or msg.from
  from_name = vim.trim(from_name)
  local status = string.format("%d/%d %s", index, total, from_name)
  if msg.attachment_count > 0 then
    status = status .. " 📎" .. msg.attachment_count
  end
  vim.b.notmuch_status = status
end

--------------------------------------------------------------------------------
-- PUBLIC: Buffer-local variables interface
--------------------------------------------------------------------------------

--- Returns current message object from buffer local variable
--- @return table|nil message Current message object with all fields
function T.get_current_message()
  return vim.b.notmuch_current
end

--- Returns current message ID from buffer local variable
--- @return string|nil id Message ID of the current message or nil
function T.get_current_message_id()
  local current = vim.b.notmuch_current
  return current and current.id
end

--------------------------------------------------------------------------------
-- PUBLIC: Show thread main entry point
--------------------------------------------------------------------------------

--- Set up autocmd for updating current message tracker on CursorMove
--- @param bufnr number Buffer number
function T.setup_cursor_tracking(bufnr)
  -- Updates the current message in buffer local variable with each CursorMoved
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = update_current_message,
  })

  -- Initial current message variable
  update_current_message()
end

--- Fetches and renders a thread as buffer lines
---
--- Runs `notmuch show --format=json` to fetch the thread, parses the JSON
--- output, and transforms it into formatted buffer lines with fold markers.
---
--- @param threadid string Thread ID (without 'thread:' prefix)
--- @return table lines Array of strings ready for buffer display
--- @return table thread_metadata Thread metadata to be exported to buffer var
T.show_thread = function(threadid)
  -- Run `notmuch show` with JSON format
  local res = vim
    .system({
      "notmuch",
      "show",
      "--format=json",
      "--exclude=false",
      "--include-html",
      "thread:" .. threadid,
    })
    :wait()

  -- Check for `notmuch show` execution error
  if res.code ~= 0 then
    vim.notify(
      "Error running notmuch show: " .. (res.stderr or "unknown error"),
      vim.log.levels.ERROR
    )
    return { "Error: Could not fetch thread data" }, {}
  end

  -- Check for empty result output
  if res.stdout == "[]\n" or res.stdout == "" then
    return { "Thread not found or empty" }, {}
  end

  -- Parse/decode JSON output
  local ok, json = pcall(vim.json.decode, res.stdout)
  if not ok then
    vim.notify("Failed to parse thread JSON: " .. tostring(json), vim.log.levels.ERROR)
    return { "Error: Could not parse thread data" }, {}
  end

  -- Validate JSON structure
  if not json or #json == 0 or not json[1] or #json[1] == 0 or not json[1][1] then
    return { "Thread data is malformed or empty" }, {}
  end

  local thread = json[1]
  local root_msg = thread[1][1]

  -- Initialize `vim.b.notmuch_thread` accumulator
  local metadata = {
    thread = {
      id = threadid,
      subject = (root_msg.headers or {}).Subject or "[No subject]",
      date_relative = root_msg.date_relative or "",
      message_count = 0,
      tags = {},
      _tags_set = {}, -- temporary: set for deduplication
      authors = {},
      _authors_seen = {}, -- temporary: set for deduplication
    },
    messages = {},
  }

  -- Build buffer lines (also builds accumulated thread metadata)
  local lines = {}

  local thread_view_mode = config.options.thread_view_mode or "threaded"

  if thread_view_mode == "newest-first" or thread_view_mode == "oldest-first" then
    -- Flatten all messages in the thread tree with their timestamps.
    local function flatten_messages(nodes, flat_list)
      for _, node in ipairs(nodes) do
        local msg = node[1]
        local replies = node[2] or {}
        table.insert(flat_list, {
          node = node,
          timestamp = msg.timestamp or 0,
        })
        if #replies > 0 then
          flatten_messages(replies, flat_list)
        end
      end
    end

    local flat_messages = {}
    flatten_messages(thread, flat_messages)

    -- Sort flattened messages chronologically.
    table.sort(flat_messages, function(a, b)
      if thread_view_mode == "newest-first" then
        return a.timestamp > b.timestamp
      end
      return a.timestamp < b.timestamp
    end)

    -- Build lines for sorted messages with depth set to 0 to remove indentation.
    for _, item in ipairs(flat_messages) do
      build_message_lines(item.node, 0, lines, metadata, true)
    end
  else
    -- Process messages in original notmuch thread tree order, maintaining hierarchy.
    for _, node in ipairs(thread) do
      build_message_lines(node, 0, lines, metadata, false)
    end
  end

  -- Set metadata tags based on ordered list of seen tags during recursion
  metadata.thread.tags = vim.tbl_keys(metadata.thread._tags_set)
  table.sort(metadata.thread.tags)
  metadata.thread._tags_set = nil

  -- Set metadata authors for this thread
  metadata.thread.authors = vim.tbl_keys(metadata.thread._authors_seen)
  metadata.thread._authors_seen = nil

  return lines, metadata
end

return T

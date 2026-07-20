# 📨 Notmuch.nvim

A powerful and flexible mail reader interface for NeoVim. This plugin bridges
your email and text editing experiences directly within NeoVim by interfacing
with the [Notmuch mail indexer](https://notmuchmail.org).

1. [Introduction](#introduction)
2. [Feature Overview](#feature-overview)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Usage](#usage)
6. [Configuration Options](#configuration-options)
7. [License](#license)

## Introduction

**Notmuch.nvim** is a NeoVim plugin that serves as a front-end for the Notmuch
mail indexer, enabling users to read, compose, and manage their emails from
within NeoVim. It facilitates a streamlined workflow for handling emails using
the familiar Vim interface and motions.

<!--
> [!IMPORTANT]
> This plugin requires NeoVim 0.5 or later to leverage its LuaJIT capabilities.
> You also need to have `telescope.nvim` for this plugin to work.
-->

## Feature Overview

- 📧 **Email Browsing**: Navigate emails with Vim-like movements.
- 🔍 **Search Your Email**: Leverage `notmuch` to search your email interactively.
- 🔗 **Thread Viewing**: Messages are loaded with folding and threading intact.
- 📎 **Attachment Management**: View/open/save received attachments, and manage outgoing draft attachments with both commands and an editable scratch window.
- 🌐 **Inline HTML Rendering**: Render HTML email bodies as text via `w3m`.
- ⬇️ **Offline Mail Sync**: Supports `mbsync` for efficient sync processes, with buffer, background, and interactive terminal modes.
- 🔓 **Async Search**: Large mailboxes with thousands of email? No problem.
- 🏷️ **Tag Management**: Conveniently add, remove, or toggle email tags.
- 💻 **Pure Lua**: Fully implemented in Lua for performance and maintainability.
- 🔭 (WIP) ~~**Telescope.nvim Integration**: Search interactively, extract URL's, jump
  efficiently, with the powerful file picker of choice.~~

## Requirements

- **[NeoVim](https://github.com/neovim/neovim)**: Version 0.10 or later is
  required (uses `vim.system()`, `vim.b` buffer variables, and other modern APIs).
- **[Notmuch](https://notmuchmail.org)**: Ensure Notmuch and libnotmuch library
  are installed
- **[w3m](http://w3m.sourceforge.net/)** (optional): Required for inline HTML
  email rendering when `render_html_body = true`
- (WIP) ~~**[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)**: File
  picker of choice for many use cases.~~

## Installation

You can install Notmuch.nvim using your favorite NeoVim plugin manager.

### Using `lazy.nvim`:
```lua
{
    'yousefakbar/notmuch.nvim',
    config = function()
        -- Configuration goes here
        local opts = {}
        require('notmuch').setup(opts)
    end,
}
```

### Using `vim.pack`:

If you are using `nvim` v0.12, or above, you can install using the builtin
package manager:

```lua
vim.pack.add({
    'https://github.com/yousefakbar/notmuch.nvim',
})

-- Or to pin to a specific tag/version:

vim.pack.add({
  {
    src = 'https://github.com/yousefakbar/notmuch.nvim',
    version = 'v0.3.0', -- Or git commit, etc.
  },
})
```

### Manual Installation:
Clone the repository and add the directory to your `runtimepath`:
```bash
git clone https://github.com/yousefakbar/notmuch.nvim.git
```

## Usage

Here are the core commands within Notmuch.nvim:

- **`:Notmuch`**: Lists available tags in your Notmuch database in a buffer.
  Setup key bindings for easy access. Example: 

  ```lua
  -- Define a keymap to run `:Notmuch` and launch the plugin landing page
  vim.keymap.set("n", "<leader>n", "<CMD>Notmuch<CR>")
  ```

- **`:NmSearch <query>`**: Executes an asynchronous search based on provided
  Notmuch query terms.

  ```vim
  " Loads the threads in your inbox received today
  :NmSearch tag:inbox and date:today
  ```

- **`:Inbox [email]`**: Quick access to your inbox. Optionally filter by
  recipient email address (Useful for multi-account setups.)

  ```vim
  " Open all inbox messages
  :Inbox

  " Open inbox for a specific account
  :Inbox work@example.com
  ```

- **`:ComposeMail [address...]`**: Opens a persistent compose draft. Drafts are
  saved under `drafts.folder` and can be reopened later.

- **`:NotmuchDrafts`**: Opens a global draft picker for compose and reply drafts.

## Configuration Options

You can configure several global options to tailor the plugin's behavior:

| Option             | Description                                                                     | Default                         |
| :----------------- | :-----------------------------------------------------------------------------: | :------------------------------ |
| `notmuch_db_path`  | Directory containing the `.notmuch/` dir                                        | From `notmuch config`           |
| `maildir_sync_cmd` | Bash command to run for syncing maildir                                         | `mbsync -a`                     |
| `sync.sync_mode`   | Sync display mode: `"buffer"`, `"background"`, or `"terminal"` (PTY with stdin) | `buffer`                        |
| `send.send_mode`   | Send mode: `"terminal"` (PTY with stdin) or `"background"`                       | `terminal`                      |
| `queries`          | Saved/pinned queries shown at top of `:Notmuch` dashboard; hidden when empty    | `{}`                            |
| `keymaps`          | Configure any (WIP) command's keymap                                            | See `config.lua`[1]             |
| `attachments.cache_dir` | Shorthand for received attachment open/view cache directory | `stdpath("cache")/notmuch.nvim/attachments` |
| `attachments.open` | List of received attachment open rules tried before defaults | `{}` |
| `attachments.view` | List of received attachment view rules tried before defaults | `{}` |
| `attachments.window` | Shorthand for floating attachment preview window options | `{ type = "float", width = 0.8, height = 0.8, border = "rounded" }` |
| `attach.incoming.*` | Advanced received attachment rule patch API | See below |
| `render_html_body` | Render HTML email bodies inline using `w3m` (requires `w3m` installed)          | `false`                         |
| `thread_view_mode` | Thread view mode: `"threaded"`, `"newest-first"`, or `"oldest-first"`        | `"threaded"`                   |
| `drafts.folder` | Directory used for persistent compose/reply draft `.eml` files and JSON metadata | `stdpath("data")/notmuch.nvim/drafts` |
| `drafts.delete_sent` | Delete the persistent draft after a successful send instead of marking it sent | `false` |
| `drafts.show_sent_drafts` | Include sent drafts in draft pickers | `false` |
| `drafts.auto_open_attachment_window` | Automatically open the draft attachment scratch window when a draft opens | `false` |
| `suppress_deprecation_warning` | Suppress the warning shown when using deprecated notmuch API (< 0.32) | `false`                         |

[1]: https://github.com/yousefakbar/notmuch.nvim/blob/main/lua/notmuch/config.lua

Example configuration in plugin manager (lazy.nvim):

```lua
{
    "yousefakbar/notmuch.nvim",
    opts = {
        notmuch_db_path = "/home/xxx/Documents/Mail",
        maildir_sync_cmd = "mbsync personal",
        sync = {
            sync_mode = "buffer" -- OR "background" OR "terminal"
        },
        send = {
            send_mode = "terminal" -- OR "background"
        },
        keymaps = {
            sendmail = "<C-g><C-g>",
        },
        drafts = {
            folder = vim.fn.stdpath("data") .. "/notmuch.nvim/drafts",
            delete_sent = false,
            show_sent_drafts = false,
            auto_open_attachment_window = false,
        },
        render_html_body = true, -- Render HTML emails inline (requires w3m)
        queries = {
            { name = "📤 Sent today",    query = "tag:sent and date:today" },
            { name = "⚠️ IMPORTANT",     query = "tag:flagged or tag:pr or tag:urgent" },
            { name = "⌛ Overdue (+3d)", query = "tag:inbox and date:..3d" },
        },
        thread_view_mode = "threaded", -- OR "newest-first" OR "oldest-first"
    },
},
```

### Drafts and Outgoing Attachments

Compose and reply buffers are backed by persistent drafts. Each draft stores the
editable message in an `.eml` file and metadata, including outgoing attachment
paths, in a JSON sidecar. The JSON sidecar is the persistent source of truth for
draft attachments, mirrored while the draft is open in `vim.b.notmuch_attachments`.

Outgoing attachments can be managed in either of two synchronized ways:

- Edit the attachment scratch window, opened with the configured
  `keymaps.attachment_window` mapping or `:AttachOpen`.
- Use buffer-local commands in compose/reply draft buffers:
  - `:Attach {path}` adds a validated attachment path.
  - `:AttachRemove {path}` removes an attachment, with completion from the
    current attachment list.
  - `:AttachList` prints the current attachment list.
  - `:AttachOpen` opens the editable attachment scratch window.

The scratch window and commands update the same draft attachment state. Set
`drafts.auto_open_attachment_window = true` if you want the scratch window to
open automatically whenever a draft opens.

### Customizing Received Attachment Rules

Received-message attachments use rule registries instead of monolithic handler
callbacks. Open/view actions extract the selected MIME part to
`attach.incoming.cache_dir`, build a structured attachment object, then resolve
open or view rules. Save actions still write directly to the user-selected path.

For everyday customization, use the `attachments` shorthand. Rules listed in
`attachments.open` and `attachments.view` are tried before the defaults. The old
received attachment `open_handler` and `view_handler` setup callbacks have been
removed; use open/view rules instead.

```lua
require('notmuch').setup({
    attachments = {
        open = {
            {
                name = 'pdf-zathura',
                match = { ext = 'pdf' },
                command = { 'zathura', '$path' },
                detach = true,
                fallback = 'Could not open PDF with zathura.',
            },
        },
        view = {
            {
                name = 'pdf',
                match = { content_type = 'application/pdf' },
                commands = {
                    { 'pdftotext', '-raw', '$path', '-' },
                },
                filetype = 'text',
                fallback = 'Install pdftotext to preview PDFs.',
            },
        },
        window = {
            width = 0.9,
            height = 0.9,
            border = 'rounded',
        },
    },
})
```

Advanced users can still use `attach.incoming.open.rules` and
`attach.incoming.view.rules` directly as patch tables:

- `prepend`: try rules before defaults;
- `append`: try rules after defaults;
- `replace`: replace a default rule by name;
- `disable`: disable default rules by name.

Example: replace the default PDF preview rule:

```lua
require('notmuch').setup({
    attach = {
        incoming = {
            view = {
                rules = {
                    replace = {
                        pdf = {
                            name = 'pdf',
                            match = { content_type = 'application/pdf' },
                            commands = {
                                { 'pdftotext', '-raw', '$path', '-' },
                            },
                            filetype = 'text',
                            fallback = 'Install pdftotext to preview PDFs.',
                        },
                    },
                },
            },
        },
    },
})
```

The default open rule prefers `vim.ui.open()` when available and falls back to
the OS opener command. Default view rules cover HTML, PDF, images, Office
documents, Markdown, archives, text, and binary fallbacks.

### Statusline Integration

When viewing a thread, the plugin exposes buffer-local variables that can be
used for statusline integration or other extensibility purposes:

| Variable | Description |
| :------- | :---------- |
| `vim.b.notmuch_thread` | Thread metadata (ID, subject, tags, authors, message count) |
| `vim.b.notmuch_messages` | Array of all messages with line positions and metadata |
| `vim.b.notmuch_current` | Cursor-tracked current message (updates on `CursorMoved`) |
| `vim.b.notmuch_status` | Pre-formatted statusline string (e.g., "2/5 John Doe 📎1") |

Example statusline integration with lualine:

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      {
        function() return vim.b.notmuch_status or '' end,
        cond = function() return vim.bo.filetype == 'mail' end,
      },
    },
  },
})
```

## License

This project is licensed under the MIT License, granting you the freedom to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies. The
MIT License's full text can be found in the `LICENSE` section of the project's
documentation.

For more details on usage and advanced configuration options, please refer to
the in-depth plugin help within NeoVim: `:help notmuch`.

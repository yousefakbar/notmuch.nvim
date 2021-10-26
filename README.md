*notmuch.txt*	Notmuch of an email interface

Author:  Yousef H. Akbar <yousef@yhakbar.com>

==============================================================================
CONTENTS                                                     *notmuch-contents*

  Introduction                          |notmuch-introduction|
    Feature Overview                    |notmuch-features|
    Requirements                        |notmuch-requirements|
    Installation                        |notmuch-installation|
    Other Notmuch Plugins               |notmuch-other-plugins|
  Usage                                 |notmuch-usage|
    Commands                            |notmuch-commands|
    Options                             |notmuch-options|
    Completion                          |notmuch-completion|
  Behavior
    Buffers
    Highlighting
    Attachments
  Lua Structure
    Library Bindings
    Asynchronous Searching
  Credit
  License                               |notmuch-license|

==============================================================================
INTRODUCTION                                             *notmuch-introduction*

Notmuch is a command line program that indexes your local mail from a Maildir
structure into a database wherein each message or thread can be tagged,
searched, and manipulated in flexible and powerful ways. To learn more about
the email program, check out the project website:

    `Notmuch`: https://notmuchmail.org

Notmuch.nvim interfaces the notmuch mail indexer to provide a convenient mail
reader as a NeoVim plugin. The main goal of Notmuch.nvim is to bring closer
the workflow of reading mail and editing text. In a sense, this plugin acts as
a front-end for notmuch's command line interface.

Note: This plugin is written almost entirely in Lua, and hence requires NeoVim
version 0.5 to make use of the embedded LuaJIT compiler.

------------------------------------------------------------------------------
FEATURE OVERVIEW                                             *notmuch-features*

The Notmuch plugin ships with two main vim commands. These can be extended
using your own commands, functions, or mappings.

The first command, |:Notmuch| , serves as an entry point into notmuch by
displaying a list of all available tags in your database. The second command,
|:NmSearch| , performs a query on your notmuch database using given arguments
and returns a list of matched threads. These commands are explained in more
depth in |notmuch-commands|

Here is a non-comprehensive list of features of notmuch.nvim:

- Browse your email(s)
  - Traverse through threads with familiar Vim movements
  - Manipulate text with visual selections and registers
- Read threads in thread view
  - Each message in the thread is loaded into buffer
  - Folding enabled for each message
  - Messages indented based on reply level
- Inspect the attachments of messages
  - Save to current directory
  - View attachment with `open(1)`-like command
  - Plain text message is automatically displayed
- Sync your mail with simple mappings
  - Native support for `isync(1)`/`mbsync(1)`
  - Sync command can be extended and modified
- Search your notmuch database asynchronously
  - Non-blocking: do your thing while results pour in
  - Any search term accepted by `notmuch-search-terms(1)`
    - Completion provided with the `:NmSearch` command
  - Returns a list of threads
- Tagging threads/messages
  - Add, remove, or toggle one or more tags at once
  - Inspect all tags pertinent to thread/msg
- GitHub compatibility features
  - Follow pull request patches
- Extract URLs with a script

------------------------------------------------------------------------------
REQUIREMENTS                                             *notmuch-requirements*

The following is a list of specific requirements for running Notmuch.nvim. The
plugin depends on bare minimum requirements in terms of installation and
doesn't depend on any external plugins.

NeoVim version~

  Notmuch.nvim requires NeoVim (>=0.5) to make use of its embedded LuaJIT
  compiler, since the plugin is written mostly in Lua. The plugin is currently
  tested on as late as version (v0.5.0-dev+991-g74b343a6f).

  If your operating system or distribution only contains an older version, you
  can build the source code from HEAD or from the nightly branch (recommended)
  from the following GitHub page:

      `NeoVim`: https://github.com/neovim/neovim

  Keep in mind this plugin is not compatible with Vim. It is designed
  specifically for NeoVim and will not work for the former.

Notmuch~

  The plugin interfaces with Notmuch and requires the executable to be
  installed, which you will probably have anyway provided that you plan to use
  the plugin to manipulate mail.

  More specifically the plugin contains bindings that call on functions from
  the libnotmuch library. Ensure that you have these installed.

  Both the mentioned items can be installed through your operating system's
  native package manager, or you can build it from source:

      `Notmuch`: https://notmuchmail.org

------------------------------------------------------------------------------
INSTALLATION                                             *notmuch-installation*

Notmuch.nvim, like other (Neo)Vim plugins, can be installed using a plugin
manager. Use your preferred plugin manager to download and install this
plugin.

Alternatively, you can download the source code from the repository manually
to your filesystem, and add that directory to your 'runtimepath': >

    git clone git://git.yousef.sh/notmuch.nvim.git
<
------------------------------------------------------------------------------
OTHER NOTMUCH PLUGINS                                   *notmuch-other-plugins*

Notmuch.nvim acts as a front-end for the Notmuch command line interface. There
are other plugins and front-ends from which Notmuch.nvim draws inspiration.
For a list of more -- not necessarily plugin -- front-ends for Notmuch, check
their webpage [1].

The first is the Notmuch Emacs package [2], which behaves and looks really
similar to this plugin. The index view, thread-centric view and behavior, and
message folding is mostly inspired by the Emacs package.

The second front-end worth a look is the notmuch-vim plugin [3]. This is
another plugin, written in Ruby, for Vim. It supports a similar index view and
is also thread-based. Notmuch.nvim draws inspiration from its tagging
capabilities and buffer-specific highlighting. For a more complete overview of
notmuch-vim's features, see the demo video [4] made by its author, Felipe
Contreras.

What's the difference between Notmuch.nvim and notmuch-vim? Well for starters,
Notmuch.nvim works in NeoVim (not Vim). Notmuch.nvim is written in Lua and,
with LuaJIT, runs a bit faster. Notmuch.nvim supports asynchronous searching:
you can continue in the main event loop while results pour in (especially
useful for large tags/results). Notmuch.nvim also supports extraction of
non-text attachments on top of the plain text view. These are features I think
enhance the quality of life while browsing mail from a text editor.

              {1} https://notmuchmail.org/frontends/
              {2} https://notmuchmail.org/notmuch-emacs/
              {3} https://git.notmuchmail.org/git/notmuch/blob/HEAD:/vim/README
              {4} https://youtu.be/JGD7IbZmnIs

==============================================================================
USAGE                                                           *notmuch-usage*

As mentioned before there are two main commands that serve as an entry point
to the Notmuch interface. To see a list of features covered by this plugin,
check the |notmuch-features| section. In this section we cover the commands,
discuss how to use them and extend them, and provide some defaults and global
variables that can be customized.

Notmuch.nvim is a thread-based mail reader. The main workflow and usage of the
plugin is to browse/search through threads, open and read them in plain text,
extract their attachments and open them in external programs, and manipulate
the tags associated with threads or individual messages within the notmuch
database.

	*Todo	move the below section to Behavior->Buffers

Notmuch Buffers~

In general, buffers created with Notmuch.nvim use the |scratch-buffer| utility
in NeoVim. All the notmuch buffers are read-only and can be closed by simply
pressing 'q'. They will usually be named verbosely based on the thread you're
browsing or whatever search term you have performed.

------------------------------------------------------------------------------
COMMANDS                                                     *notmuch-commands*

Let's showcase the two main commands that give the user a window into the
Notmuch.nvim plugin and the local mail system to search and browse.

                                                    *:Notmuch*
:Notmuch             Shows a list of tags from the notmuch database in a new
                     buffer. Pressing <CR> on any tag will search the buffer
		     for all threads with that tag.

		     Note: I recommend setting up a key mapping that invokes
		     this command. That way you can access your notmuch mail
		     with ease. For example: >

		       nmap <silent> <leader>n :Notmuch<CR>
<
                                                    *:NmSearch*
:NmSearch            Search and return a list of threads based on a notmuch
                     query. The arguments of this command match the format of
		     Notmuch's accepted search terms and supports generic
		     completion (see `notmuch_search_terms(7)`). For example: >

		       :NmSearch tag:inbox and date:today and subject:Urgent
<
                     Note: This command can be extended to quickly perform
		     frequently used searches. For example: >

		       command Inbox :NmSearch tag:inbox
<
                     Now your inbox is one word away at all times. This can
		     even be generalized as a shell alias such that you can
		     jump from the shell straight to your or any other handy
		     search term you want.

                                                    *:NmNew*
:NmNew               Invoke `notmuch new` in the external shell to refresh
                     your Notmuch database. This is a modular command to be
		     used when you have new mail or would like to refresh your
		     tags for whatever reason.

                                                    *:NmSync*
:NmSync              Refresh and synchronize your local Maildir directories
                     with the remote server to keep them on track with each
		     other. Typically this (1) invokes a remote synchronizing
		     command in the shell (`mbsync(1)` by default) and then
		     (2) refreshes your notmuch database with `notmuch new` .

		     Note: By default, the sync command is set to: >

		       mbsync -c $XDG_CONFIG_HOME/isync/mbsyncrc -a
<
                     But this command can be customized by setting
		     |g:NotmuchMaildirSyncCmd| to a valid command.

------------------------------------------------------------------------------
OPTIONS                                                       *notmuch-options*

This is a list of global options associated with the Notmuch.nvim plugin. They
can be modified to alter the granular behavior of some notmuch commands. Each
option will be listed with its default value.

*g:NotmuchDBPath*
  Path to your notmuch database. More precisely, set this to the directory
  that contains the `.notmuch` directory.

  Default value:
    `'$HOME/Mail'`

*g:NotmuchMaildirSyncCmd*
  Program to run when synchronizing your local maildir mail to the remote
  (IMAP or otherwise) server. Do not include the `notmuch new` refresh command
  in this option. See |:NmSync| to see how this is used.

  Default value:
    `mbsync -c $XDG_CONFIG_HOME/isync/mbsyncrc -a`

*g:NotmuchOpenCmd*
  Catch-all program to invoke when opening attachments from messages. This is
  initially based on operating system, but can be customized to something
  else.

  Default value:
    `open(1)`        if MacOS.
    `xdg_open(1)`    otherwise

------------------------------------------------------------------------------
COMPLETION                                                 *notmuch-completion*

Notmuch.nvim provides a handy autoload function that returns completion items
for commands. Specifcially this is used for |:NmSearch| as it helps quickly
type search terms. The function in question is called
`notmuch#CompSearchTerms()` and matches the format for generic completion
functons (|command-completion-custom|).

Although this is used for |:NmSearch|, you can actually use this as a
completion function for any custom commands you may want to define. The
completion function returns two types of results:

  * If the word under the cursor says 'tags:', returns a list of all the tags
    available in the notmuch database.
  * Otherwise returns a list of all the valid search terms (see
    `notmuch-search-terms(1)`)

Note: Interestingly enough, this is the only bit of Vimscript used in the
entire plugin (at least as of right now).

==============================================================================
LICENSE                                                       *notmuch-license*

License: MIT License

Copyright (c) 2021 Yousef Akbar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

vim:tw=78:isk=!-~,^*,^\|,^\":ts=8:noet:ft=help:norl:

-- Notmuch LuaJIT<-->C Bindings (Wrapper)
--
-- Author:
-- Yousef H. Akbar <yousef@yhakbar.com> (https://yousef.sh)
--
-- Description:
-- A LuaJIT wrapper library that interfaces with the libnotmuch C header.  Its
-- ultimate goal is to provide an API into a user's notmuch database from within
-- NeoVim. It builds upon a gist made by Elv13 [1] and fixes some deprecated
-- functions and cleans up code a little.
--
-- Dependencies:
-- * Notmuch (https://notmuchmail.org)
-- * NeoVim (>= 0.5.0) (https://github.com/neovim/neovim)
-- * Lua (https://lua.org)
-- * LuaJIT with FFI module (https://luajit.org/)
--
-- References:
-- [1]: https://gist.github.com/Elv13/1691174c1f6d784ce6fef6d0a1bb0908

local c = {}
local ffi = require("ffi")
local nm = ffi.load("notmuch")

local c_head = [[
  typedef struct _notmuch_database notmuch_database_t;
  typedef struct {} notmuch_query_t;
  typedef struct {} notmuch_messages_t;
  typedef struct {} notmuch_message_t;
  typedef struct {} notmuch_threads_t;
  typedef struct {} notmuch_thread_t;
  typedef struct {} notmuch_tags_t;
  typedef int notmuch_bool_t;
  typedef int notmuch_status_t;
  typedef int notmuch_database_mode_t;

  notmuch_status_t
  notmuch_database_open (const char *path,
              notmuch_database_mode_t mode,
              notmuch_database_t **database);

  notmuch_tags_t *
  notmuch_database_get_all_tags (notmuch_database_t *db);

  notmuch_query_t *
  notmuch_query_create (notmuch_database_t *database,
              const char *query_string);

  notmuch_status_t
      notmuch_query_search_messages_st (notmuch_query_t *query,
                      notmuch_messages_t **out);

  notmuch_status_t
  notmuch_query_count_threads (notmuch_query_t *query, unsigned *count);

  notmuch_status_t
  notmuch_query_search_threads (notmuch_query_t *query,
  			      notmuch_threads_t **out);

  notmuch_bool_t
  notmuch_messages_valid (notmuch_messages_t *messages);

  void
  notmuch_messages_move_to_next (notmuch_messages_t *messages);

  notmuch_message_t *
  notmuch_messages_get (notmuch_messages_t *messages);

  const char *
  notmuch_message_get_filename (notmuch_message_t *message);

  const char *
  notmuch_message_get_thread_id (notmuch_message_t *message);

  notmuch_messages_t *
  notmuch_message_get_replies (notmuch_message_t *message);

  const char *
  notmuch_message_get_message_id (notmuch_message_t *message);

  notmuch_status_t
  notmuch_database_close (notmuch_database_t *database);

  notmuch_status_t
  notmuch_query_search_threads_st (notmuch_query_t *query,
                  notmuch_threads_t **out);

  notmuch_bool_t
  notmuch_threads_valid (notmuch_threads_t *threads);

  void
  notmuch_threads_move_to_next (notmuch_threads_t *threads);

  notmuch_thread_t *
  notmuch_threads_get (notmuch_threads_t *threads);

  const char *
  notmuch_thread_get_thread_id (notmuch_thread_t *thread);

  void
  notmuch_query_destroy (notmuch_query_t *query);

  void
  notmuch_messages_destroy (notmuch_messages_t *messages);

  notmuch_tags_t *
  notmuch_message_get_tags (notmuch_message_t *message);

  void
  notmuch_tags_move_to_next (notmuch_tags_t *tags);

  notmuch_bool_t
  notmuch_tags_valid (notmuch_tags_t *tags);

  const char *
  notmuch_tags_get (notmuch_tags_t *tags);

  void
  notmuch_tags_destroy (notmuch_tags_t *tags);

  notmuch_status_t
  notmuch_message_add_tag (notmuch_message_t *message, const char *tag);

  notmuch_status_t
  notmuch_message_remove_tag (notmuch_message_t *message, const char *tag);

  notmuch_status_t
  notmuch_message_remove_all_tags (notmuch_message_t *message);
]]

ffi.cdef(c_head)

-- Opens a Notmuch database. Entry point into the api.
--
-- @path: Directory where the Notmuch database is stored.
-- @mode: Read/write mode. Either 0 for read or 1 for read/write.
local function open_database(path, mode)
  local db = ffi.new('notmuch_database_t*[1]')
  local res = nm.notmuch_database_open(path, mode, db)
  assert(res == 0, 'Error opening database with err=' .. res)
  return {
    _db = db[0],
    create_query = function(query) return create_query(query, db[0]) end,
    get_all_tags = function() return get_all_tags(db[0]) end,
    close = function() nm.notmuch_database_close(db[0]) end
  }
end

-- Creates a query object given a search string.
--
-- @query_string: String given by user to search the database.
-- @db: User's Notmuch database object
function create_query(query_string, db)
  local query = nm.notmuch_query_create(db, query_string)
  return {
    _query = query,
    count_threads = function() return count_threads(query) end,
  }
end

-- Returns a table of all tags found in the given database
--
-- @db: User's Notmuch database object.
function get_all_tags(db)
  local out = {}
  local tags = nm.notmuch_database_get_all_tags(db)
  while nm.notmuch_tags_valid(tags) == 1 do
    table.insert(out, ffi.string(nm.notmuch_tags_get(tags)))
    nm.notmuch_tags_move_to_next(tags)
  end
  return out
end

-- Counts the number of unique threads that matched a given query.
--
-- @query: Query object from `create_query()`
function count_threads(query)
  local count = ffi.new("unsigned int[1]")
  local res = nm.notmuch_query_count_threads(query, count)
  assert(res == 0, 'Error counting threads. err=' .. res)
  return count[0]
end

return open_database

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent

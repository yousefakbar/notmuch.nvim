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

ffi.cdef[[
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

  notmuch_status_t
  notmuch_database_find_message (notmuch_database_t *database,
              const char *message_id,
              notmuch_message_t **message);

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

  const char *
  notmuch_thread_get_subject (notmuch_thread_t *thread);

  notmuch_messages_t *
  notmuch_thread_get_messages (notmuch_thread_t *thread);

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
    get_message = function(id) return get_message(id, db[0]) end,
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
    get_threads = function() return get_threads(query) end,
    get_messages = function() return get_messages(query) end,
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

local thread_obj = {}

-- Returns subject line string of a thread.
function thread_obj:get_subject()
  return ffi.string(nm.notmuch_thread_get_subject(self._thread))
end

-- Returns a table of tags attached to a thread.
function thread_obj:get_tags()
  self.tags = {}
  local tags = nm.notmuch_thread_get_tags(self._thread)
  while nm.notmuch_tags_valid(tags) == 1 do
    self.tags[ffi.string(nm.notmuch_tags_get(tags))] = true
    nm.notmuch_tags_move_to_next(tags)
  end
  return self.tags
end

-- Adds tag to all messages inside a thread.
function thread_obj:add_tag(tag)
  local messages = nm.notmuch_thread_get_messages(self._thread)
  local message = ffi.new('notmuch_message_t[1]')
  while nm.notmuch_messages_valid(messages) == 1 do
    message = nm.notmuch_messages_get(messages)
    local res = nm.notmuch_message_add_tag(message, tag)
    assert(res == 0, 'Error adding tag:' .. tag .. '. err=' .. res)
    nm.notmuch_messages_move_to_next(messages)
  end
end

-- Removes tag to all messages inside a thread.
function thread_obj:rm_tag(tag)
  local messages = nm.notmuch_thread_get_messages(self._thread)
  local message = ffi.new('notmuch_message_t[1]')
  while nm.notmuch_messages_valid(messages) == 1 do
    message = nm.notmuch_messages_get(messages)
    local res = nm.notmuch_message_rm_tag(message, tag)
    assert(res == 0, 'Error removing tag:' .. tag .. '. err=' .. res)
    nm.notmuch_messages_move_to_next(messages)
  end
end

-- Toggle tag to all messages inside a thread.
function thread_obj:toggle_tag(tag)
  self:get_tags()
  if self.tags[tag] then
    self:rm_tag(tag)
  else
    self:add_tag(tag)
  end
end

-- Return a list of thread objects from a given query.
--
-- @query: Query object to get threads from
function get_threads(query)
  local out = {}
  local threads = ffi.new('notmuch_threads_t*[1]')
  local res = nm.notmuch_query_search_threads(query, threads)
  assert(res == 0, 'Error retrieving threads, err=' .. res)
  while nm.notmuch_threads_valid(threads[0]) == 1 do
    local thread = setmetatable({
      _thread = nm.notmuch_threads_get(threads[0]),
    }, {
      __index = function(self, key)
        if thread_obj[key] then
          return thread_obj[key]
        end
      end
    })
    table.insert(out, thread)
    nm.notmuch_threads_move_to_next(threads[0])
  end
  return out
end

local message_obj = {}

-- Return a table of tags attached to a message.
function message_obj:get_tags()
  self.tags = {}
  local tags = nm.notmuch_message_get_tags(self._msg)
  while nm.notmuch_tags_valid(tags) == 1 do
    self.tags[ffi.string(nm.notmuch_tags_get(tags))] = true
    nm.notmuch_tags_move_to_next(tags)
  end
  return self.tags
end

-- Add a tag to a message.
function message_obj:add_tag(tag)
  local res = nm.notmuch_message_add_tag(self._msg, tag)
  assert(res == 0, 'Error adding tag:' .. tag .. '. err=' .. res)
end

-- Remove a tag to a message.
function message_obj:rm_tag(tag)
  local res = nm.notmuch_message_remove_tag(self._msg, tag)
  assert(res == 0, 'Error removing tag:' .. tag .. '. err=' .. res)
end

-- Toggle a tag to a message.
function message_obj:toggle_tag(tag)
  self:get_tags()
  if self.tags[tag] then
    self:rm_tag(tag)
  else
    self:add_tag(tag)
  end
end

-- Get a message object from an id: straight from the database.
function get_message(id, db)
  local msg = ffi.new('notmuch_message_t*[1]')
  local res = nm.notmuch_database_find_message(db, id, msg)
  assert(res == 0, 'Error finding message from id. err=' .. res)
  local message = setmetatable({
    _msg = msg[0],
  }, {
    __index = function(self, key)
      if message_obj[key] then
        return message_obj[key]
      end
    end
  })
  return message
end

-- Get a list of message objects from a given query.
function get_messages(query)
  local out = {}
  local messages = ffi.new('notmuch_messages_t*[1]')
  local res = nm.notmuch_query_search_messages(query, threads)
  assert(res == 0, 'Error retrieving threads, err=' .. res)
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

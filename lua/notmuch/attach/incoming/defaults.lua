local D = {}

-- -----------------------------------------------------------------------------
-- PRIVATE HELPERS
-- -----------------------------------------------------------------------------

local function system_open_command()
  local sysname = vim.uv.os_uname().sysname

  if sysname == 'Darwin' then
    return { 'open', '$path' }
  elseif sysname == 'Linux' then
    return { 'xdg-open', '$path' }
  elseif sysname:match('Windows') then
    return { 'start', '$path' }
  end

  return { 'xdg-open', '$path' }
end

local function vim_ui_open(att)
  if vim.ui and vim.ui.open then
    local _, err = vim.ui.open(att.path)
    if err then
      return nil, err
    end
    return true, nil
  end

  return nil, 'vim.ui.open is unavailable'
end

local function content_type(att)
  return (att.part and att.part.content_type) or ''
end

local function ext(att)
  return (att.part and att.part.ext) or ''
end

local function filename(att)
  return (att.part and att.part.filename) or ''
end

local function is_html(att)
  return content_type(att) == 'text/html' or ext(att):match('^html?$') ~= nil
end

local function is_pdf(att)
  return content_type(att) == 'application/pdf' or ext(att) == 'pdf'
end

local function is_image(att)
  return content_type(att):match('^image/') ~= nil
end

local function is_office(att)
  local extension = ext(att)
  return content_type(att):match('officedocument') ~= nil
    or extension == 'doc'
    or extension == 'docx'
    or extension == 'xls'
    or extension == 'xlsx'
    or extension == 'ppt'
    or extension == 'pptx'
end

local function is_markdown(att)
  return content_type(att) == 'text/markdown' or ext(att) == 'md'
end

local function is_zip(att)
  return content_type(att):match('zip') ~= nil or ext(att) == 'zip'
end

local function is_tar(att)
  local name = filename(att)
  return content_type(att):match('tar') ~= nil
    or ext(att) == 'tar'
    or name:match('%.tar$') ~= nil
    or name:match('%.tar%.') ~= nil
end

local function is_text(att)
  return content_type(att):match('^text/') ~= nil
end

local function binary_fallback(att)
  return string.format(
    'Unable to view binary file\nType: %s\nPath: %s',
    content_type(att) ~= '' and content_type(att) or 'unknown',
    att.path or ''
  )
end

-- -----------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-- -----------------------------------------------------------------------------

---Return default incoming attachment open rules.
---@return NotmuchIncomingRule[]
function D.open_rules()
  return {
    {
      name = 'system',
      match = '*',
      handler = vim_ui_open,
      command = system_open_command(),
      detach = true,
      fallback = 'Could not open attachment with the system opener',
    },
  }
end

---Return default incoming attachment view rules.
---@return NotmuchIncomingRule[]
function D.view_rules()
  return {
    {
      name = 'html',
      match = is_html,
      commands = {
        { 'w3m', '-T', 'text/html', '-dump', '$path' },
        { 'lynx', '-dump', '-nolist', '$path' },
        { 'elinks', '-dump', '-no-references', '$path' },
      },
      filetype = 'text',
      fallback = 'HTML file (install w3m, lynx, or elinks to view)',
    },

    {
      name = 'pdf',
      match = is_pdf,
      commands = {
        { 'pdftotext', '-layout', '$path', '-' },
        { 'mutool', 'draw', '-F', 'txt', '$path' },
      },
      filetype = 'text',
      fallback = 'PDF file (install pdftotext or mutool to view)',
    },

    {
      name = 'image',
      match = is_image,
      commands = {
        { 'chafa', '--size', '80x40', '$path' },
        { 'catimg', '-w', '80', '$path' },
        { 'viu', '-w', '80', '$path' },
        { 'exiftool', '$path' },
        { 'identify', '-verbose', '$path' },
      },
      filetype = 'text',
      fallback = 'Image file (install chafa, viu, or exiftool to view)',
    },

    {
      name = 'office',
      match = is_office,
      commands = {
        { 'pandoc', '-t', 'plain', '$path' },
        { 'docx2txt', '$path', '-' },
      },
      filetype = 'text',
      fallback = 'Office document (install pandoc or docx2txt to view)',
    },

    {
      name = 'markdown',
      match = is_markdown,
      commands = {
        { 'pandoc', '-t', 'plain', '$path' },
        { 'mdcat', '$path' },
        { 'cat', '$path' },
      },
      filetype = 'markdown',
      fallback = 'Markdown file (install pandoc or mdcat to preview with formatting)',
    },

    {
      name = 'zip',
      match = is_zip,
      commands = {
        { 'unzip', '-l', '$path' },
      },
      filetype = 'text',
      fallback = 'ZIP archive (install unzip to list contents)',
    },

    {
      name = 'tar',
      match = is_tar,
      commands = {
        { 'tar', '-tvf', '$path' },
      },
      filetype = 'text',
      fallback = 'TAR archive (install tar to list contents)',
    },

    {
      name = 'text',
      match = is_text,
      commands = {
        { 'cat', '$path' },
      },
      filetype = 'text',
      fallback = 'Unable to read text attachment',
    },

    {
      name = 'binary',
      match = '*',
      commands = {
        { 'strings', '$path' },
      },
      filetype = 'text',
      fallback = binary_fallback,
    },
  }
end

return D

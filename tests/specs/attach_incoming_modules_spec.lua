local H = dofile("tests/helpers.lua")

return {
  {
    name = "attach.incoming modules load and expose planned APIs",
    run = function()
      local incoming = require("notmuch.attach.incoming")
      local attachment = require("notmuch.attach.incoming.attachment")
      local extractor = require("notmuch.attach.incoming.extractor")
      local rules = require("notmuch.attach.incoming.rules")
      local defaults = require("notmuch.attach.incoming.defaults")
      local viewer = require("notmuch.attach.incoming.viewer")
      local opener = require("notmuch.attach.incoming.opener")
      local renderer = require("notmuch.attach.incoming.renderer")

      H.eq("function", type(incoming.open_part))
      H.eq("function", type(incoming.view_part))

      H.eq("function", type(attachment.from_part))

      H.eq("function", type(extractor.cache_path))
      H.eq("function", type(extractor.extract_to_cache))
      H.eq("function", type(extractor.extract_to_path))

      H.eq("function", type(rules.matches))
      H.eq("function", type(rules.apply_patches))
      H.eq("function", type(rules.expand_command))
      H.eq("function", type(rules.first_match))

      H.eq("function", type(defaults.open_rules))
      H.eq("function", type(defaults.view_rules))
      H.eq("table", type(defaults.open_rules()))
      H.eq("table", type(defaults.view_rules()))

      H.eq("function", type(viewer.view))
      H.eq("function", type(opener.open))
      H.eq("function", type(renderer.render))
    end,
  },
}

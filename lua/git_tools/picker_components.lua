local M = {}

function M.for_kind(kind)
  local C = require("selection_tools.components")
  if kind == "changes" then
    return {
      C.icon(),
      C.text({ field = "kind" }),
      C.text({ field = "status" }),
      C.path({ field = "path", path_format = false }),
      C.text({
        get = function(item)
          return item.body and item.body[1] or item.text:match("(%[binary/metadata%])$")
        end,
      }),
    }
  elseif kind == "log" then
    return {
      C.icon(),
      C.text({
        get = function(item)
          return item.sha:sub(1, 10)
        end,
      }),
      C.time({
        get = function(item)
          return item.date:sub(1, 10)
        end,
        searchable = true,
      }),
      C.text({ field = "author" }),
      C.text({ field = "subject", grow = 1, truncate = "match" }),
    }
  elseif kind == "blame" then
    return {
      C.icon(),
      C.text({ field = "lnum" }),
      C.text({
        get = function(item)
          return item.sha:sub(1, 10)
        end,
      }),
      C.text({ field = "author" }),
      C.text({ field = "summary", grow = 1, truncate = "match" }),
    }
  elseif kind == "branches" then
    return {
      C.icon(),
      C.text({
        get = function(item)
          return item.current and "*" or nil
        end,
      }),
      C.text({
        get = function(item)
          return item.remote and "remote" or "local"
        end,
      }),
      C.text({ field = "name", grow = 1, truncate = "match" }),
      C.text({
        get = function(item)
          return item.sha:sub(1, 10)
        end,
      }),
    }
  elseif kind == "stash" then
    return { C.icon(), C.text({ field = "ref" }), C.text({ field = "subject", grow = 1, truncate = "match" }) }
  end
  return { C.icon(), C.text({ grow = 1, truncate = "match" }) }
end

return M

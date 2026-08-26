local Json = require("src.support.json")

local Publisher = {}
local ENDPOINT = "http://127.0.0.1:8765/api/events"

local function event_text(event)
  return tostring(event.text or event.system_text or event.header_text or event.sub_text or "")
end

function Publisher.payload(panel, event)
  if type(panel) ~= "string" or panel == "" or type(event) ~= "table" then return nil end
  local badges = {}
  for _, badge in ipairs(type(event.badges) == "table" and event.badges or {}) do
    if type(badge) == "string" then badges[#badges + 1] = badge end
  end
  return {
    panel = panel:lower(), platform = "kick", kind = tostring(event.kind or "event"),
    id = event.id and tostring(event.id) or nil, author = event.author and tostring(event.author) or nil,
    text = event_text(event), color = event.author_color, badges = badges
  }
end

function Publisher.publish(panel, event)
  local payload = Publisher.payload(panel, event)
  local c2 = rawget(_G, "c2")
  if not payload or not (c2 and c2.HTTPRequest and c2.HTTPMethod and c2.HTTPMethod.Post) then return false end
  local ok = pcall(function()
    local request = c2.HTTPRequest.create(c2.HTTPMethod.Post, ENDPOINT)
    request:set_header("Content-Type", "application/json")
    request:set_timeout(750)
    request:set_payload(Json.encode(payload))
    request:on_success(function() end)
    request:on_error(function() end)
    request:finally(function() end)
    request:execute()
  end)
  return ok
end

return Publisher

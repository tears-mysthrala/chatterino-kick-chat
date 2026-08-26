local Url = {}

local function valid_slug(slug)
  return type(slug) == "string" and #slug >= 1 and #slug <= 80 and slug:match("^[%w_%-]+$") ~= nil
end

function Url.normalize(input)
  if type(input) ~= "string" then return nil, "missing" end
  local value = input:match("^%s*(.-)%s*$"):lower()
  local slug = value:gsub("^@", "")
  if value:match("^https://") then
    local host, path = value:match("^https://([^/]+)/([^?#]+)")
    if host ~= "kick.com" and host ~= "www.kick.com" then return nil, "host" end
    slug = path and path:match("^([^/]+)") or nil
  elseif value:match("^https?://") then return nil, "scheme" end
  if not valid_slug(slug) then return nil, "slug" end
  return { slug = slug, canonical = "https://kick.com/api/v2/channels/" .. slug }
end

return Url

local Json = require("src.support.json")
local State = { FILE = "KICK_CHAT.json" }

function State.default() return { schema_version = 1, channels = {} } end

local function valid_slug(value) return type(value) == "string" and value:match("^[%w_%-]+$") and #value <= 80 end

function State.validate(value)
  local out = State.default()
  for slug, entry in pairs(type(value) == "table" and type(value.channels) == "table" and value.channels or {}) do
    if valid_slug(slug) and type(entry) == "table" then
      local splits = {}
      for _, split in ipairs(type(entry.splits) == "table" and entry.splits or {}) do
        if type(split) == "string" and split ~= "" and #split <= 256 and #splits < 64 then splits[#splits + 1] = split end
      end
      out.channels[slug] = { slug = slug, chatroom_id = tonumber(entry.chatroom_id), splits = splits, paused = entry.paused == true }
    end
  end
  return out
end

function State.read()
  local file = io.open(State.FILE, "r"); if not file then return State.default() end
  local raw = file:read("a"); file:close(); local ok, value = pcall(Json.decode, raw)
  return ok and State.validate(value) or State.default()
end

function State.write(state)
  local encoded = Json.encode(State.validate(state)); local tmp = State.FILE .. ".tmp"
  local file = io.open(tmp, "w"); if not file then return false end
  file:write(encoded); file:flush(); file:close()
  local target = io.open(State.FILE, "w"); if not target then return false end
  target:write(encoded); target:flush(); target:close(); return true
end

function State.bind(state, slug, chatroom_id, split)
  local entry = state.channels[slug] or { slug = slug, splits = {}, paused = false }
  entry.chatroom_id = tonumber(chatroom_id)
  for _, value in ipairs(entry.splits) do if value == split then state.channels[slug] = entry; return entry end end
  entry.splits[#entry.splits + 1] = split; state.channels[slug] = entry; return entry
end

return State

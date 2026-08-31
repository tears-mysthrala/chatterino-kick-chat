local Json = require("src.support.json")
local Url = require("src.kick.url")
local State = require("src.state")
local Adapter = require("src.c2_adapter")
local Connection = require("src.kick.connection")
local Commands = {}

local function sys(ctx, text) Adapter.system(ctx.channel:get_name(), text) end
local function add(state, ctx, target)
  local normalized, err = Url.normalize(target); if not normalized then sys(ctx, "Invalid Kick channel: " .. tostring(err)); return end
  local req = Adapter.http_get(normalized.canonical)
  req:on_success(function(response)
    if response:status() ~= 200 then sys(ctx, "Kick returned HTTP " .. tostring(response:status())); return end
    local ok, data = pcall(Json.decode, response:data())
    local chatroom = ok and type(data) == "table" and data.chatroom or nil
    if type(chatroom) ~= "table" or not tonumber(chatroom.id) then sys(ctx, "Kick did not return a chatroom id"); return end
    local livestream = type(data.livestream) == "table" and data.livestream or {}
    local stream_value = livestream.id or livestream.slug or livestream.created_at
    local stream_id = stream_value and tostring(stream_value) or nil
    local entry = State.bind(state, normalized.slug, chatroom.id, ctx.channel:get_name(), stream_id); State.write(state)
    local started = Connection.start(entry)
    sys(ctx, started and ("Connection requested for " .. normalized.slug) or
      ("Could not open " .. normalized.slug .. "; retry scheduled"))
  end)
  req:on_error(function() sys(ctx, "Network error while resolving the Kick channel") end); req:execute()
end

function Commands.register(state)
  local c2 = rawget(_G, "c2")
  c2.register_command("/kick-chat", function(ctx)
    local arg = tostring(ctx.words[2] or "")
    if arg == "" or arg == "help" then sys(ctx, "Usage: /kick-chat <channel|URL> · auto [channel] · list · status · pause <channel> · resume <channel> · remove <channel>"); return end
    if arg == "list" then for slug, entry in pairs(state.channels) do sys(ctx, slug .. " · " .. (entry.paused and "paused" or "active") .. " · " .. #entry.splits .. " split(s)") end; return end
    if arg == "status" then
      local items = Connection.status()
      if #items == 0 then sys(ctx, "No active Kick connections"); return end
      for _, item in ipairs(items) do
        local detail = item.last_error and (" · " .. item.last_error) or ""
        sys(ctx, item.slug .. " · " .. item.phase .. " · errors " .. item.errors .. detail)
      end
      return
    end
    if arg == "pause" or arg == "resume" or arg == "remove" then
      local slug = tostring(ctx.words[3] or ""):lower():gsub("^@", ""); local entry = state.channels[slug]
      if not entry then sys(ctx, "Unknown channel: " .. slug); return end
      if arg == "remove" then Connection.stop(slug); state.channels[slug] = nil; sys(ctx, "Removed " .. slug)
      else entry.paused = arg == "pause"; if entry.paused then Connection.stop(slug) else Connection.start(entry) end; sys(ctx, (entry.paused and "Paused " or "Resumed ") .. slug) end
      State.write(state); return
    end
    if arg:lower() == "auto" then
      local override = tostring(ctx.words[3] or "")
      arg = override ~= "" and override or tostring(ctx.channel:get_name() or "")
    end
    add(state, ctx, arg)
  end)
end
return Commands

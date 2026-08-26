local Adapter = {}
local function api() return rawget(_G, "c2") end

function Adapter.channel(name)
  local c = api(); if not (c and c.Channel and c.Channel.by_name) then return nil end
  local ok, channel = pcall(c.Channel.by_name, name); return ok and channel or nil
end

function Adapter.system(split, text)
  local channel = Adapter.channel(split); if channel then channel:add_system_message("🟢 KICK " .. tostring(text)) end
end

function Adapter.deliver(spec, splits)
  for _, split in ipairs(splits or {}) do
    local channel = Adapter.channel(split)
    if channel then
      if spec.system then channel:add_system_message(spec.message_text)
      else
        local c = api(); local ok, msg = pcall(c.Message.new, spec)
        if ok and msg then channel:add_message(msg) else channel:add_system_message(spec.message_text) end
      end
    end
  end
end

function Adapter.http_get(url)
  local c = api(); local req = c.HTTPRequest.create(c.HTTPMethod.Get, url)
  req:set_header("Accept", "application/json"); req:set_header("User-Agent", "Chatterino Kick Chat/0.1.0"); req:set_timeout(15000)
  return req
end

function Adapter.websocket(url, options) return api().WebSocket.new(url, options) end
function Adapter.later(fn, ms) local c = api(); if c and c.later then c.later(fn, ms) end end
return Adapter

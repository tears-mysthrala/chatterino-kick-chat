local Protocol = require("src.kick.protocol")
local Events = require("src.kick.events")
local Builder = require("src.messages.builder")
local Adapter = require("src.c2_adapter")
local OverlayPublisher = require("src.overlay.publisher")
local Json = require("src.support.json")

local Connection = {}
local active = {}
local generation = 0

local function live_splits(entry)
  local out = {}
  for _, split in ipairs(entry.splits or {}) do if Adapter.channel(split) then out[#out + 1] = split end end
  return out
end

local function connect(entry)
  if not entry.chatroom_id or entry.paused then return false end
  local existing = active[entry.slug]
  if existing and existing.socket then existing.entry = entry; return true end
  generation = generation + 1; local token = generation
  local current = { entry = entry, errors = existing and existing.errors or 0, token = token }; active[entry.slug] = current
  local socket

  local function refresh_live_session()
    if active[entry.slug] ~= current or current.stopped then return end
    local request = Adapter.http_get("https://kick.com/api/v2/channels/" .. current.entry.slug)
    request:on_success(function(response)
      if active[entry.slug] ~= current or current.stopped or response:status() ~= 200 then return end
      local ok, data = pcall(Json.decode, response:data())
      local livestream = ok and type(data) == "table" and type(data.livestream) == "table" and data.livestream or nil
      local value = livestream and (livestream.id or livestream.slug or livestream.created_at) or nil
      if value then
        local stream_id = tostring(value)
        current.entry.stream_id = stream_id
        for _, split in ipairs(live_splits(current.entry)) do
          OverlayPublisher.session(split, stream_id, current.entry.slug)
        end
	  else
		current.entry.stream_id = nil
      end
    end)
    request:on_error(function() end)
    request:finally(function() Adapter.later(refresh_live_session, 60000) end)
    request:execute()
  end

  socket = Adapter.websocket(Protocol.websocket_url(), {
    on_open = function()
      current.errors = 0
      socket:send_text(Protocol.subscription(entry.chatroom_id))
      socket:send_text(Protocol.legacy_subscription(entry.chatroom_id))
	  refresh_live_session()
    end,
    on_text = function(raw)
      local frame = Protocol.decode_frame(raw); if not frame then return end
      if frame.event == "pusher:ping" then socket:send_text(Protocol.pong()); return end
      local event = Events.normalize(frame.event, frame.data); if not event then return end
	  event.channel, event.stream_id = current.entry.slug, current.entry.stream_id
      local splits = live_splits(current.entry); if #splits == 0 then socket:close(); active[entry.slug] = nil; return end
      for _, split in ipairs(splits) do OverlayPublisher.publish(split, event) end
      Adapter.deliver(Builder.build(event, entry.slug), splits)
    end,
    on_close = function()
      if active[entry.slug] ~= current or current.token ~= token or current.stopped then return end
      current.socket = nil; current.errors = current.errors + 1
      local delay = math.min(30000, 1000 * (2 ^ math.min(5, current.errors - 1)))
      Adapter.later(function() if active[entry.slug] == current and not current.stopped then active[entry.slug] = nil; connect(current.entry) end end, delay)
    end
  })
  current.socket = socket; return true
end

function Connection.start(entry) return connect(entry) end
function Connection.stop(slug)
  local item = active[slug]; if not item then return false end
  item.stopped = true; if item.socket then item.socket:close() end; active[slug] = nil; return true
end
function Connection.status() local out = {}; for slug, item in pairs(active) do out[#out + 1] = { slug=slug, connected=item.socket~=nil, errors=item.errors } end; table.sort(out,function(a,b)return a.slug<b.slug end); return out end
function Connection._reset() for slug in pairs(active) do Connection.stop(slug) end; active = {}; generation = 0 end
return Connection

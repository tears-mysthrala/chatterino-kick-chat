local Protocol = require("src.kick.protocol")
local Events = require("src.kick.events")
local Builder = require("src.messages.builder")
local Adapter = require("src.c2_adapter")
local OverlayPublisher = require("src.overlay.publisher")
local Json = require("src.support.json")

local Connection = {}
local active = {}

local DEFAULT_ACTIVITY_TIMEOUT_MS = 120000
local MIN_ACTIVITY_TIMEOUT_MS = 15000
local PONG_TIMEOUT_MS = 30000
local WATCHDOG_TICK_MS = 5000
local SUBSCRIPTION_TIMEOUT_MS = 30000
local STABLE_CONNECTION_MS = 10000
local MAX_RECONNECT_DELAY_MS = 30000

local function live_splits(entry)
  local out = {}
  for _, split in ipairs(entry.splits or {}) do if Adapter.channel(split) then out[#out + 1] = split end end
  return out
end

local function reconnect_delay(errors)
  return math.min(MAX_RECONNECT_DELAY_MS, 1000 * (2 ^ math.min(5, math.max(0, errors - 1))))
end

local function refresh_live_session(current)
  if active[current.entry.slug] ~= current or current.stopped or not current.connected then return end
  local request = Adapter.http_get("https://kick.com/api/v2/channels/" .. current.entry.slug)
  request:on_success(function(response)
    if active[current.entry.slug] ~= current or current.stopped or response:status() ~= 200 then return end
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
  request:finally(function()
    Adapter.later(function() refresh_live_session(current) end, 60000)
  end)
  request:execute()
end

local function activity_timeout_ms(frame)
  local seconds = frame and type(frame.data) == "table" and tonumber(frame.data.activity_timeout) or nil
  if not seconds then return DEFAULT_ACTIVITY_TIMEOUT_MS end
  return math.max(MIN_ACTIVITY_TIMEOUT_MS, math.min(DEFAULT_ACTIVITY_TIMEOUT_MS, seconds * 1000))
end

local function start_activity_watch(current)
  current.watchdog_generation = current.watchdog_generation + 1
  local watchdog_generation = current.watchdog_generation
  local seen_activity = current.activity_generation
  local idle_ms = 0
  local pong_wait_ms = 0

  local function tick()
    if active[current.entry.slug] ~= current or current.stopped or not current.transport_open or
        current.watchdog_generation ~= watchdog_generation then return end

    if current.activity_generation ~= seen_activity then
      seen_activity = current.activity_generation
      idle_ms = 0
      pong_wait_ms = 0
      current.awaiting_pong = false
    elseif current.awaiting_pong then
      pong_wait_ms = pong_wait_ms + WATCHDOG_TICK_MS
      if pong_wait_ms >= PONG_TIMEOUT_MS then
        local socket = current.socket
        if socket then socket:close() end
        return
      end
    else
      idle_ms = idle_ms + WATCHDOG_TICK_MS
      if idle_ms >= current.activity_timeout_ms then
        local socket = current.socket
        if not socket then return end
        socket:send_text(Protocol.ping())
        current.awaiting_pong = true
        pong_wait_ms = 0
      end
    end
    Adapter.later(tick, WATCHDOG_TICK_MS)
  end

  Adapter.later(tick, WATCHDOG_TICK_MS)
end

local connect

local function schedule_reconnect(current)
  if active[current.entry.slug] ~= current or current.stopped or current.close_handled then return end
  current.close_handled = true
  current.socket = nil
  current.transport_open = false
  current.connected = false
  current.subscribed = false
  current.awaiting_pong = false
  current.watchdog_generation = current.watchdog_generation + 1
  if current.permanent_error then return end
  current.errors = current.errors + 1
  current.retry_scheduled = true
  local delay = current.retry_delay_override
  if delay == nil then delay = reconnect_delay(current.errors) end
  Adapter.later(function()
    if active[current.entry.slug] ~= current or current.stopped then return end
    current.retry_scheduled = false
    connect(current.entry)
  end, delay)
end

connect = function(entry)
  if not entry.chatroom_id or entry.paused then return false end
  local existing = active[entry.slug]
  if existing and existing.socket then
    existing.entry = entry
    return true
  end

  local current = {
    entry = entry,
    errors = existing and existing.errors or 0,
    transport_open = false,
    connected = false,
    retry_scheduled = false,
    close_handled = false,
    subscribed = false,
    activity_generation = 0,
    activity_timeout_ms = DEFAULT_ACTIVITY_TIMEOUT_MS,
    watchdog_generation = 0,
    awaiting_pong = false
  }
  active[entry.slug] = current

  local function opened()
    if not current.socket then
      current.open_pending = true
      return
    end
    if active[entry.slug] ~= current or current.stopped then return end
    current.transport_open = true
    start_activity_watch(current)
  end

  local socket
  local ok
  ok, socket = pcall(Adapter.websocket, Protocol.websocket_url(), {
    on_open = opened,
    on_text = function(raw)
      if active[entry.slug] ~= current or current.stopped or not current.transport_open or
          current.socket ~= socket then return end
      current.activity_generation = current.activity_generation + 1
      local frame = Protocol.decode_frame(raw)
      if not frame then return end
      if frame.event == "pusher:connection_established" then
        current.activity_timeout_ms = activity_timeout_ms(frame)
        current.socket:send_text(Protocol.subscription(current.entry.chatroom_id))
        current.socket:send_text(Protocol.legacy_subscription(current.entry.chatroom_id))
        Adapter.later(function()
          if active[entry.slug] == current and not current.stopped and current.transport_open and
              not current.subscribed and current.socket then
            current.last_error = "subscription_timeout"
            current.socket:close()
          end
        end, SUBSCRIPTION_TIMEOUT_MS)
        return
      end
      if frame.event == "pusher_internal:subscription_succeeded" then
        local primary = "chatrooms." .. tostring(current.entry.chatroom_id) .. ".v2"
        if frame.channel == primary and not current.subscribed then
          current.subscribed = true
          current.connected = true
          current.last_error = nil
          refresh_live_session(current)
          Adapter.later(function()
            if active[entry.slug] == current and current.connected and current.subscribed then
              current.errors = 0
            end
          end, STABLE_CONNECTION_MS)
        end
        return
      end
      if frame.event == "pusher:error" then
        local code = type(frame.data) == "table" and tonumber(frame.data.code) or nil
        current.last_error = code and ("pusher_" .. tostring(code)) or "pusher_error"
        if code and code >= 4000 and code <= 4099 then current.permanent_error = current.last_error end
        if code and code >= 4200 and code <= 4299 then current.retry_delay_override = 0 end
        if code and code >= 4000 and code <= 4299 and current.socket then current.socket:close() end
        return
      end
      if frame.event == "pusher:subscription_error" then
        current.last_error = "subscription_error"
        if current.socket then current.socket:close() end
        return
      end
      if frame.event == "pusher:ping" then current.socket:send_text(Protocol.pong()); return end
      if frame.event == "pusher:pong" then return end
      if not current.connected then return end
      local event = Events.normalize(frame.event, frame.data)
      if not event then return end
      event.channel, event.stream_id = current.entry.slug, current.entry.stream_id
      local splits = live_splits(current.entry)
      if #splits == 0 then
        current.stopped = true
        active[entry.slug] = nil
        current.socket:close()
        return
      end
      for _, split in ipairs(splits) do OverlayPublisher.publish(split, event) end
      Adapter.deliver(Builder.build(event, entry.slug), splits)
    end,
    on_close = function()
      schedule_reconnect(current)
    end
  })

  if not ok or not socket then
    schedule_reconnect(current)
    return false
  end
  if current.retry_scheduled or active[entry.slug] ~= current then return false end
  current.socket = socket
  if current.open_pending then
    current.open_pending = false
    opened()
  end
  return true
end

function Connection.start(entry) return connect(entry) end
function Connection.stop(slug)
  local item = active[slug]
  if not item then return false end
  item.stopped = true
  item.watchdog_generation = item.watchdog_generation + 1
  active[slug] = nil
  if item.socket then item.socket:close() end
  return true
end
function Connection.status()
  local out = {}
  for slug, item in pairs(active) do
    local phase = item.permanent_error and "failed" or
        (item.connected and "connected" or (item.retry_scheduled and "reconnecting" or "connecting"))
    out[#out + 1] = {
      slug = slug,
      connected = item.connected,
      phase = phase,
      errors = item.errors,
      last_error = item.last_error
    }
  end
  table.sort(out, function(a, b) return a.slug < b.slug end)
  return out
end
function Connection._reset()
  local slugs = {}
  for slug in pairs(active) do slugs[#slugs + 1] = slug end
  for _, slug in ipairs(slugs) do Connection.stop(slug) end
  active = {}
end
return Connection

package.path = "./?.lua;./?/init.lua;" .. package.path

local assertions = 0
local function eq(actual, expected, label)
  assertions = assertions + 1
  if actual ~= expected then error((label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end
local function ok(value, label) assertions = assertions + 1; if not value then error(label or "expected truthy") end end

local Json = require("src.support.json")
local Url = require("src.kick.url")
local Protocol = require("src.kick.protocol")
local Events = require("src.kick.events")
local Builder = require("src.messages.builder")
local State = require("src.state")

eq(Json.decode('{"a":1,"b":[true,"x"]}').b[2], "x", "JSON decode")
eq(Json.decode(Json.encode({ z = 2, a = "ñ" })).a, "ñ", "JSON roundtrip")
eq(Url.normalize("https://kick.com/XQC?x=1").slug, "xqc", "Kick URL")
eq(Url.normalize("@some_channel").slug, "some_channel", "Kick handle")
eq(select(2, Url.normalize("http://kick.com/xqc")), "scheme", "reject HTTP")
eq(select(2, Url.normalize("https://evil.example/xqc")), "host", "reject foreign host")
ok(Protocol.websocket_url():match("^wss://ws%-us2%.pusher%.com/"), "Pusher URL")
local frame = Protocol.decode_frame('{"event":"App\\\\Events\\\\ChatMessageEvent","data":"{\\"id\\":\\"m1\\",\\"content\\":\\"hola\\",\\"sender\\":{\\"id\\":42,\\"username\\":\\"ana\\",\\"identity\\":{\\"badges\\":[{\\"type\\":\\"moderator\\"}]}}}"}')
local event = Events.normalize(frame.event, frame.data)
eq(event.author, "ana", "author")
eq(event.author_id, "42", "stable author id")
eq(event.badges[1], "moderator", "badge")
local spec = Builder.build(event, "xqc")
eq(spec.id, "kick-chat-m1", "message id")
ok(spec.message_text:find("hola", 1, true), "message body")
eq(State.validate({ channels = { xqc = { chatroom_id = 1, splits = {}, stream_id = "obsolete" } } }).channels.xqc.stream_id,
  nil, "persisted stream id is transient")

-- Integration harness: command -> discovery HTTP -> websocket subscription -> delivered message.
local channels, commands, requests, sockets, later_callbacks = {}, {}, {}, {}, {}
local kick_live = true
local target = { messages = {}, systems = {} }
function target:get_name() return "gilraennr" end
function target:add_message(message) self.messages[#self.messages + 1] = message end
function target:add_system_message(message) self.systems[#self.systems + 1] = message end
channels["gilraennr"] = target

_G.c2 = {
  HTTPMethod = { Get = "GET", Post = "POST" },
  Channel = { by_name = function(name) return channels[name] end },
  Message = { new = function(specification) return specification end },
  register_command = function(name, callback) commands[name] = callback end,
  later = function(callback, ms) later_callbacks[#later_callbacks + 1] = { callback=callback, ms=ms } end
}
_G.c2.HTTPRequest = { create = function(method, url)
  local request = { method=method, url=url, headers={} }; requests[#requests + 1] = request
  function request:set_header(name,value) self.headers[name]=value end
  function request:set_timeout(value) self.timeout=value end
  function request:set_payload(value) self.payload=value end
  function request:on_success(callback) self.success=callback end
  function request:on_error(callback) self.failure=callback end
  function request:finally(callback) self.finally_callback=callback end
  function request:execute()
    if method == "POST" then
      self.success({ status=function() return 202 end, data=function() return '' end })
    else
      local body = kick_live and '{"chatroom":{"id":668},"livestream":{"id":991}}' or '{"chatroom":{"id":668},"livestream":null}'
      self.success({ status=function() return 200 end, data=function() return body end })
    end
    if self.finally_callback then self.finally_callback() end
  end
  return request
end }
local function websocket_new(url, options)
  local socket = { url=url, sent={}, options=options, closed=false }; sockets[#sockets + 1] = socket
  function socket:send_text(text) self.sent[#self.sent + 1] = text end
  function socket:close()
    if self.closed then return end
    self.closed = true
    self.options.on_close()
  end
  return socket
end
_G.c2.WebSocket = { new = websocket_new }

local function take_timer(ms)
  for index, timer in ipairs(later_callbacks) do
    if timer.ms == ms then
      table.remove(later_callbacks, index)
      return timer.callback
    end
  end
  error("missing timer " .. tostring(ms))
end

local function run_until(ms, predicate, max_steps)
  for _ = 1, max_steps or 20 do
    take_timer(ms)()
    if predicate() then return end
  end
  error("condition not reached for timer " .. tostring(ms))
end

local function sent_count(socket, needle)
  local count = 0
  for _, value in ipairs(socket.sent) do
    if value:find(needle, 1, true) then count = count + 1 end
  end
  return count
end

local state = { schema_version=1, channels={} }
require("src.commands").register(state)
commands["/kick-chat"]({ words={"/kick-chat", "auto"}, channel=target })
eq(#requests, 1, "one discovery request")
ok(requests[1].url:find("/gilraennr", 1, true), "auto uses current Twitch channel name")
eq(#sockets, 1, "one shared socket")
ok(target.systems[#target.systems]:find("Connection requested", 1, true), "command does not claim premature connection")
sockets[1].options.on_open()
sockets[1].options.on_text('{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"1.1\\",\\"activity_timeout\\":120}"}')
ok(sockets[1].sent[1]:find("chatrooms.668.v2", 1, true), "subscription channel")
ok(sockets[1].sent[2]:find("chatroom_668", 1, true), "legacy event channel")
eq(require("src.kick.connection").status()[1].phase, "connecting", "Pusher handshake alone is not connected")
sockets[1].options.on_text('{"event":"pusher_internal:subscription_succeeded","channel":"chatrooms.668.v2","data":"{}"}')
local legacy_sent_before = #sockets[1].sent
sockets[1].options.on_text('{"event":"pusher:subscription_error","channel":"chatroom_668","data":"{}"}')
ok(not sockets[1].closed, "legacy subscription error leaves primary connection alive")
eq(#sockets[1].sent, legacy_sent_before, "legacy subscription error needs no transport response")
local session_published = false
for _, request in ipairs(requests) do
  if request.payload and request.payload:find('"kind":"stream_session"', 1, true) and
      request.payload:find('"stream_id":"991"', 1, true) then session_published = true end
end
ok(session_published, "live Kick session published")
kick_live = false
take_timer(60000)()
sockets[1].options.on_text('{"event":"App\\\\Events\\\\ChatMessageEvent","data":"{\\"id\\":\\"m2\\",\\"content\\":\\"live\\",\\"sender\\":{\\"username\\":\\"bob\\",\\"identity\\":{\\"badges\\":[]}}}"}')
eq(#target.messages, 1, "delivered chat message")
eq(target.messages[1].id, "kick-chat-m2", "delivered id")
eq(requests[#requests].method, "POST", "overlay event posted")
ok(requests[#requests].payload:find('"panel":"gilraennr"', 1, true), "overlay panel")
ok(not requests[#requests].payload:find('"stream_id"', 1, true), "offline chat omits stale stream id")

local Connection = require("src.kick.connection")
eq(Connection.status()[1].phase, "connected", "status distinguishes an open socket")
sockets[1].options.on_close()
eq(Connection.status()[1].phase, "reconnecting", "closed socket enters reconnecting state")
eq(Connection.status()[1].errors, 1, "first connection failure recorded")
local sent_before_stale = #sockets[1].sent
local stale_ok = pcall(sockets[1].options.on_text, '{"event":"pusher:ping","data":"{}"}')
ok(stale_ok, "late frame after close is ignored safely")
eq(#sockets[1].sent, sent_before_stale, "late frame after close cannot send or publish")
sockets[1].options.on_close()
eq(Connection.status()[1].errors, 1, "duplicate close callback does not double-count failure")
take_timer(1000)()
eq(#sockets, 2, "first reconnect creates a new socket")
eq(Connection.status()[1].phase, "connecting", "new socket starts in connecting state")
sockets[2].options.on_close()
eq(Connection.status()[1].errors, 2, "consecutive failure count survives socket replacement")
take_timer(2000)()
eq(#sockets, 3, "second reconnect creates a new socket")
sockets[3].options.on_open()
sockets[3].options.on_text('{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"1.2\\",\\"activity_timeout\\":15}"}')
eq(Connection.status()[1].errors, 2, "Pusher handshake does not reset failure count")
sockets[3].options.on_text('{"event":"pusher_internal:subscription_succeeded","channel":"chatrooms.668.v2","data":"{}"}')
eq(Connection.status()[1].phase, "connected", "primary subscription confirms connection")
eq(Connection.status()[1].errors, 2, "subscription must remain stable before resetting backoff")
run_until(10000, function() return Connection.status()[1].errors == 0 end, 10)
eq(Connection.status()[1].errors, 0, "stable subscription resets failure count")

local ping_count = sent_count(sockets[3], '"event":"pusher:ping"')
run_until(5000, function() return sent_count(sockets[3], '"event":"pusher:ping"') > ping_count end, 10)
ok(not sockets[3].closed, "inactive socket sends Pusher ping before closing")
sockets[3].options.on_text('{"event":"pusher:pong","data":"{}"}')
ping_count = sent_count(sockets[3], '"event":"pusher:ping"')
run_until(5000, function() return sent_count(sockets[3], '"event":"pusher:ping"') > ping_count end, 10)
ok(not sockets[3].closed, "Pusher pong keeps the socket open")

run_until(5000, function() return sockets[3].closed end, 10)
ok(sockets[3].closed, "missing Pusher pong closes a stale socket")
eq(Connection.status()[1].phase, "reconnecting", "watchdog closure schedules reconnect")
eq(Connection.status()[1].errors, 1, "watchdog closure uses normal failure accounting")

Connection._reset()
_G.c2.WebSocket.new = function() error("synthetic constructor failure") end
commands["/kick-chat"]({ words={"/kick-chat", "constructor-failure"}, channel=target })
ok(target.systems[#target.systems]:find("retry scheduled", 1, true), "constructor failure is reported as retrying")
eq(Connection.status()[1].phase, "reconnecting", "constructor failure schedules reconnect")
eq(Connection.status()[1].errors, 1, "constructor failure uses normal failure accounting")

Connection._reset()
_G.c2.WebSocket.new = websocket_new
ok(Connection.start({ slug="subscription-timeout", chatroom_id=77, splits={"gilraennr"} }),
  "subscription-timeout socket starts")
local timeout_socket = sockets[#sockets]
timeout_socket.options.on_open()
timeout_socket.options.on_text('{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"2.1\\"}"}')
run_until(30000, function() return timeout_socket.closed end, 10)
eq(Connection.status()[1].phase, "reconnecting", "missing subscription confirmation reconnects")
eq(Connection.status()[1].last_error, "subscription_timeout", "subscription timeout is observable")
local sockets_before_timeout_retry = #sockets
run_until(1000, function() return #sockets > sockets_before_timeout_retry end, 10)
eq(Connection.status()[1].last_error, "subscription_timeout", "replacement socket preserves last error")

Connection._reset()
ok(Connection.start({ slug="permanent-error", chatroom_id=88, splits={"gilraennr"} }),
  "permanent-error socket starts")
local permanent_socket = sockets[#sockets]
permanent_socket.options.on_open()
permanent_socket.options.on_text('{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"3.1\\"}"}')
permanent_socket.options.on_text('{"event":"pusher:error","data":"{\\"code\\":4001,\\"message\\":\\"Application does not exist\\"}"}')
ok(permanent_socket.closed, "explicit permanent Pusher error closes socket")
eq(Connection.status()[1].phase, "failed", "explicit permanent Pusher error is not retried unchanged")
eq(Connection.status()[1].last_error, "pusher_4001", "explicit permanent Pusher code is observable")
commands["/kick-chat"]({ words={"/kick-chat", "status"}, channel=target })
ok(target.systems[#target.systems]:find("pusher_4001", 1, true), "status shows the last Pusher error")

Connection._reset()
ok(Connection.start({ slug="immediate-error", chatroom_id=89, splits={"gilraennr"} }),
  "immediate-error socket starts")
local immediate_socket = sockets[#sockets]
immediate_socket.options.on_open()
immediate_socket.options.on_text('{"event":"pusher:connection_established","data":"{\\"socket_id\\":\\"4.1\\"}"}')
local sockets_before_immediate = #sockets
immediate_socket.options.on_text('{"event":"pusher:error","data":"{\\"code\\":4201,\\"message\\":\\"Pong reply not received\\"}"}')
take_timer(0)()
eq(#sockets, sockets_before_immediate + 1, "explicit 4200-range error reconnects immediately")

Connection._reset()
commands["/kick-chat"]({ words={"/kick-chat", "status"}, channel=target })
ok(target.systems[#target.systems]:find("No active Kick connections", 1, true), "empty status is explicit")

local abandoned_socket
_G.c2.WebSocket.new = function(_, options)
  abandoned_socket = { closed=false, options=options }
  function abandoned_socket:close()
    if self.closed then return end
    self.closed = true
    self.options.on_close()
  end
  function abandoned_socket:send_text() end
  Connection.stop("abandoned")
  return abandoned_socket
end
ok(not Connection.start({ slug="abandoned", chatroom_id=90, splits={"gilraennr"} }),
  "connection that loses ownership does not start")
ok(abandoned_socket.closed, "connection that loses ownership closes its socket")
eq(#Connection.status(), 0, "abandoned connection leaves no active state")

print("Assertions: " .. assertions .. ", Failures: 0")

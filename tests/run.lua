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

eq(Json.decode('{"a":1,"b":[true,"x"]}').b[2], "x", "JSON decode")
eq(Json.decode(Json.encode({ z = 2, a = "ñ" })).a, "ñ", "JSON roundtrip")
eq(Url.normalize("https://kick.com/XQC?x=1").slug, "xqc", "Kick URL")
eq(Url.normalize("@some_channel").slug, "some_channel", "Kick handle")
eq(select(2, Url.normalize("http://kick.com/xqc")), "scheme", "reject HTTP")
eq(select(2, Url.normalize("https://evil.example/xqc")), "host", "reject foreign host")
ok(Protocol.websocket_url():match("^wss://ws%-us2%.pusher%.com/"), "Pusher URL")
local frame = Protocol.decode_frame('{"event":"App\\\\Events\\\\ChatMessageEvent","data":"{\\"id\\":\\"m1\\",\\"content\\":\\"hola\\",\\"sender\\":{\\"username\\":\\"ana\\",\\"identity\\":{\\"badges\\":[{\\"type\\":\\"moderator\\"}]}}}"}')
local event = Events.normalize(frame.event, frame.data)
eq(event.author, "ana", "author")
eq(event.badges[1], "moderator", "badge")
local spec = Builder.build(event, "xqc")
eq(spec.id, "kick-chat-m1", "message id")
ok(spec.message_text:find("hola", 1, true), "message body")

-- Integration harness: command -> discovery HTTP -> websocket subscription -> delivered message.
local channels, commands, requests, sockets = {}, {}, {}, {}
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
  later = function() end
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
      self.success({ status=function() return 200 end, data=function() return '{"chatroom":{"id":668}}' end })
    end
    if self.finally_callback then self.finally_callback() end
  end
  return request
end }
_G.c2.WebSocket = { new = function(url, options)
  local socket = { url=url, sent={}, options=options }; sockets[#sockets + 1] = socket
  function socket:send_text(text) self.sent[#self.sent + 1] = text end
  function socket:close() end
  return socket
end }

local state = { schema_version=1, channels={} }
require("src.commands").register(state)
commands["/kick-chat"]({ words={"/kick-chat", "auto"}, channel=target })
eq(#requests, 1, "one discovery request")
ok(requests[1].url:find("/gilraennr", 1, true), "auto uses current Twitch channel name")
eq(#sockets, 1, "one shared socket")
sockets[1].options.on_open()
ok(sockets[1].sent[1]:find("chatrooms.668.v2", 1, true), "subscription channel")
ok(sockets[1].sent[2]:find("chatroom_668", 1, true), "legacy event channel")
sockets[1].options.on_text('{"event":"App\\\\Events\\\\ChatMessageEvent","data":"{\\"id\\":\\"m2\\",\\"content\\":\\"live\\",\\"sender\\":{\\"username\\":\\"bob\\",\\"identity\\":{\\"badges\\":[]}}}"}')
eq(#target.messages, 1, "delivered chat message")
eq(target.messages[1].id, "kick-chat-m2", "delivered id")
eq(requests[#requests].method, "POST", "overlay event posted")
ok(requests[#requests].payload:find('"panel":"gilraennr"', 1, true), "overlay panel")

print("Assertions: " .. assertions .. ", Failures: 0")

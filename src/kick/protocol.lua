local Json = require("src.support.json")
local Protocol = {}

Protocol.APP_KEY = "32cbd69e4b950bf97679"
Protocol.HOST = "ws-us2.pusher.com"

function Protocol.websocket_url()
  return "wss://" .. Protocol.HOST .. "/app/" .. Protocol.APP_KEY ..
      "?protocol=7&client=js&version=8.5.0&flash=false"
end

function Protocol.subscription(chatroom_id)
  return Json.encode({ event = "pusher:subscribe", data = { auth = "", channel = "chatrooms." .. tostring(chatroom_id) .. ".v2" } })
end

function Protocol.legacy_subscription(chatroom_id)
  return Json.encode({ event = "pusher:subscribe", data = { auth = "", channel = "chatroom_" .. tostring(chatroom_id) } })
end

function Protocol.decode_frame(raw)
  if type(raw) ~= "string" or #raw > 1024 * 1024 then return nil, "size" end
  local ok, frame = pcall(Json.decode, raw)
  if not ok or type(frame) ~= "table" or type(frame.event) ~= "string" then return nil, "frame" end
  local data = frame.data
  if type(data) == "string" then
    local decoded_ok, decoded = pcall(Json.decode, data)
    if decoded_ok then data = decoded end
  end
  return { event = frame.event, channel = frame.channel, data = data }
end

function Protocol.pong()
  return Json.encode({ event = "pusher:pong", data = {} })
end

function Protocol.ping()
  return Json.encode({ event = "pusher:ping", data = {} })
end

return Protocol

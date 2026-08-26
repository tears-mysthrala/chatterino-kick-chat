local State = require("src.state")
local Commands = require("src.commands")
local Connection = require("src.kick.connection")
local Plugin = {}
local state = State.read()

function Plugin.bootstrap()
  local c2 = rawget(_G, "c2")
  assert(c2 and c2.WebSocket and c2.WebSocket.new, "chatterino-kick-chat requires Chatterino 2.5.4 or newer with WebSocket plugin support")
  Commands.register(state)
  for _, entry in pairs(state.channels) do if not entry.paused and #entry.splits > 0 then Connection.start(entry) end end
end
function Plugin._state() return state end
return Plugin

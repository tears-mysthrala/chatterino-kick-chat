# Architecture

```text
Kick channel discovery HTTP
  -> kick/url.lua
  -> commands.lua
  -> kick/connection.lua
  -> Pusher WebSocket
  -> kick/protocol.lua
  -> kick/events.lua
  -> messages/builder.lua
  -> c2_adapter.lua
  -> Chatterino splits
```

`src/c2_adapter.lua` is the only module that creates HTTP requests, WebSockets
or Chatterino messages. One connection is kept per persisted channel slug and
fans out normalized events to every live split. Closed sockets reconnect with
bounded exponential backoff.

The Pusher application key, host, public channel name and event names are
website implementation details, not a supported Kick Public API contract.
They live only in `src/kick/protocol.lua` and `src/kick/events.lua` so a future
transport change does not leak into state or rendering.

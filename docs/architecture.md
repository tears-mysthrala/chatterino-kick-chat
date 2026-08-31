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
bounded exponential backoff. A Pusher activity watchdog sends an application
ping after the server-advertised idle timeout and closes the socket when no pong
arrives, allowing half-open connections to enter the same reconnect path.

Chatterino's current Lua `on_close()` callback exposes neither the WebSocket
close code nor its reason. When Pusher v7 supplies a policy only through that
close code, the plugin cannot distinguish permanent `4000-4099` closures from
immediate `4200-4299` closures and applies bounded generic backoff. If an
explicit `pusher:error` frame is available, the plugin stops unchanged retries
for `4000-4099` and reconnects immediately for `4200-4299`.

The Pusher application key, host, public channel name and event names are
website implementation details, not a supported Kick Public API contract.
They live only in `src/kick/protocol.lua` and `src/kick/events.lua` so a future
transport change does not leak into state or rendering.

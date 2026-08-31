# Unreleased

- Detects silent or half-open Pusher connections with the server-provided
  activity timeout and an application-level ping/pong watchdog.
- Preserves consecutive failure counts across replacement sockets so reconnect
  delays back off from 1 second to a maximum of 30 seconds.
- Reports `connecting`, `connected` and `reconnecting` accurately through
  `/kick-chat status`; a WebSocket object is no longer treated as connected
  before the Pusher handshake completes.
- Shows the last Pusher or subscription error in `/kick-chat status`. Explicit
  permanent Pusher errors stop unchanged retries, while explicit immediate
  reconnect errors bypass backoff. Generic closes remain bounded by backoff
  because Chatterino's Lua callback does not expose the WebSocket close code.

# chatterino-kick-chat 0.3.0

Adds broadcast-session metadata for viewing streaks in the multichat overlay.

- The overlay receives the active Kick livestream ID and channel slug.
- Livestream state is refreshed while connected and cleared when the channel
  goes offline, preventing a later broadcast from reusing an ended session.
- Existing chat rendering, persistent bindings and automatic reconnection are
  unchanged.

Download the ZIP, verify its SHA-256 file and extract it into Chatterino's
`Plugins` directory as `chatterino-kick-chat`.

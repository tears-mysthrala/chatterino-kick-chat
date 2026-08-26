# chatterino-kick-chat 0.3.0

Adds broadcast-session metadata for viewing streaks in the multichat overlay.

- The overlay receives the active Kick livestream ID and channel slug.
- Livestream state is refreshed while connected and cleared when the channel
  goes offline, preventing a later broadcast from reusing an ended session.
- Existing chat rendering, persistent bindings and automatic reconnection are
  unchanged.

Download the ZIP, verify its SHA-256 file and extract it into Chatterino's
`Plugins` directory as `chatterino-kick-chat`.

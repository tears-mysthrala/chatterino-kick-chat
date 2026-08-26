# Contributing

`chatterino-kick-chat` is the Kick adapter in the platform-neutral Chatterino
multichat ecosystem. Keep Kick discovery and WebSocket behavior separate from
the normalized overlay publisher.

## Architecture

```text
Twitch panel mapping -> Kick discovery -> Kick chat transport -> event normalizer
                                                            -> overlay publisher
```

- `src/kick/` owns Kick endpoints, channel identity and event semantics.
- `src/transport/` owns connection state, retry and frame handling.
- `src/overlay/publisher.lua` only translates normalized events into the common
  loopback contract.
- The overlay must remain optional. Kick chat inside Chatterino must continue to
  work when no overlay agent is installed.

The canonical event contract and cross-platform compatibility rules live in the
[overlay contribution guide](https://github.com/tears-mysthrala/chatterino-multichat-overlay/blob/main/CONTRIBUTING.md).

## Kick adapter rules

- Keep the plugin anonymous and read-only unless a separately reviewed feature
  explicitly requires credentials or chat writes.
- Restrict discovery to HTTPS on `kick.com` and validate every redirect.
- Treat discovery JSON and WebSocket frames as hostile and size-bound them.
- Preserve stable upstream message IDs using the `kick-chat-` prefix.
- Normalize messages, deletions, chat clears, bans, subscriptions and gifts when
  fixtures demonstrate their upstream shape.
- Do not let an unknown Kick event crash or disconnect the chat loop.
- Automatic Twitch-to-Kick name mapping must remain explicitly overridable.

## Update notifications

Expose the installed SemVer version and canonical repository through `info.json`.
A shared notifier may check stable GitHub releases at most once every 24 hours,
show a Chatterino system message and link to the release page. It must be
disableable and must never download or install an update automatically.

## Development flow

1. Add a redacted fixture for any new or changed upstream event.
2. Add normalization and malformed-input regression tests.
3. Test behavior with the overlay available and unavailable.
4. Run the repository's complete test/package scripts.
5. Update compatibility and release notes when behavior changes.

Pull requests must state the observed upstream payload, security/privacy impact,
fallback behavior and exact checks performed. Never include credentials, private
chat exports or unrelated generated files.


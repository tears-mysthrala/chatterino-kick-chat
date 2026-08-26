# chatterino-kick-chat

A read-only Kick chat viewer plugin for Chatterino, structured after
`chatterino-yt-chat`: pure Lua parsing, one `c2` adapter, shared connections,
persistent bindings and an executable test harness.

> Unofficial project. It is not affiliated with Chatterino or Kick. Kick does
> not document the anonymous realtime web protocol used by its website. That
> protocol can change without notice and is isolated in `src/kick/protocol.lua`.

## Requirements

- Chatterino 2.5.4 or newer, built with plugin support.
- A public Kick channel. No Kick login, OAuth token or API key is used.

## Installation

Download the versioned ZIP from the repository's Releases page, verify it with
the adjacent `.sha256` file and extract it into Chatterino's plugin directory
as `Plugins/chatterino-kick-chat/`. Restart Chatterino and enable the plugin.

- Windows: `%APPDATA%\Chatterino2\Plugins\`
- Linux: `~/.local/share/chatterino/Plugins/`
- macOS: `~/Library/Application Support/chatterino/Plugins/`

## Usage

Run this in a named Chatterino split:

```text
/kick-chat xqc
/kick-chat https://kick.com/xqc
/kick-chat auto
/kick-chat auto different-kick-slug
/kick-chat list
/kick-chat status
/kick-chat pause xqc
/kick-chat resume xqc
/kick-chat remove xqc
```

`/kick-chat auto` uses the current split's channel name as the Kick slug. This
is intended for creators who use the same name on Twitch and Kick. Pass an
explicit slug after `auto` when the names differ. The binding is persisted and
reconnects when Chatterino starts again.

The plugin displays ordinary messages, badges, subscriptions, gifted
subscriptions, deletions, bans and chat clears. It never sends chat messages
or moderation actions. Multiple splits bound to the same Kick channel share
one WebSocket connection.

When [chatterino-multichat-overlay](https://github.com/tears-mysthrala/chatterino-multichat-overlay)
is running, events are also copied to its loopback-only OBS overlay. Failures
are silent and never affect chat delivery in Chatterino.

## Network and persisted data

- `https://kick.com/api/v2/channels/<slug>` discovers the public chatroom id.
- `wss://ws-us2.pusher.com/...` receives public realtime events.
- `KICK_CHAT.json` stores only channel slugs, chatroom ids, split names and
  paused state. Messages, tokens and credentials are never persisted.

## Development

From WSL/Linux:

```bash
scripts/test.sh
scripts/build_release.sh 0.2.0
```

On Windows, `scripts/test.ps1` invokes the test suite through WSL.

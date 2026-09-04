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

### Windows (double-click installer)

1. Open the [Releases page](https://github.com/tears-mysthrala/chatterino-kick-chat/releases)
   and select the latest release that is not marked **Pre-release**.
2. Under **Assets**, download the file whose name starts with
   `chatterino-kick-chat-` and ends in `.zip`, plus its matching `.sha256`
   file. Do not download the files named **Source code**.
3. Before extracting anything, complete the **Required download verification**
   below. Stop if the hashes do not match.
4. Right-click the verified ZIP, select **Extract all**, and open the extracted folder.
   Do not run the installer from inside the ZIP preview.
5. Double-click `install-or-update.cmd`. Do not run it as administrator.
6. Wait for `Done`, press any key to close the installer, and open Chatterino.
7. In the input box of a named channel panel, enter `/kick-chat status` to
   confirm that the plugin responds.

The installer closes Chatterino normally if needed, backs up the previous
plugin and its settings under `%APPDATA%\Chatterino2\PluginBackups`, preserves
`data/`, removes obsolete program files, and enables the plugin automatically.
It uses the Windows PowerShell already installed with Windows, without changing
the system-wide execution policy. No Kick login, API key, administrator access,
or extra software is required.

If the launcher does not open, right-click an empty area in the extracted
folder, select **Open in Terminal**, and run:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -CloseChatterino
```

### macOS and Linux

Extract the contents of the release ZIP into a folder named
`chatterino-kick-chat` inside Chatterino's `Plugins` directory:

- macOS: `~/Library/Application Support/chatterino/Plugins/`
- Linux: `~/.local/share/chatterino/Plugins/`
- Linux (Flatpak): `~/.var/app/com.chatterino.chatterino/data/chatterino/Plugins/`

After extraction, `init.lua` and `info.json` must be directly inside that
folder. Restart Chatterino, open **Settings → Plugins**, turn on
**Enable plugins**, and enable `chatterino-kick-chat`.

### Required download verification

The release provides a `.sha256` file with the expected SHA-256 fingerprint.
Verify it before extracting or running the ZIP. On Windows, open PowerShell, type `Get-FileHash `
(including the final space), drag the downloaded ZIP into the PowerShell
window, type ` -Algorithm SHA256`, and press Enter. The displayed **Hash** must
match the sequence in the `.sha256` file; uppercase and lowercase do not
matter. This command only reads the file.

## Updating without losing saved channels

Download and extract the new release, then double-click
`install-or-update.cmd` again. The same installer handles clean installs and
updates. It preserves and verifies `data/`, creates a recoverable backup, and
updates the existing plugin without manual file copying. Open Chatterino and
enter `/kick-chat status` in a named channel panel.

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
reconnects when Chatterino starts again or the Kick connection is interrupted.

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

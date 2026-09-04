# Security policy

## Threat model

`chatterino-kick-chat` consumes public Kick discovery responses and WebSocket
frames inside Chatterino. Malformed chat content, tampered responses, hostile
URLs, reconnect storms and accidental credential leakage are untrusted inputs.

## Security boundaries

- The plugin is anonymous and read-only: no Kick credentials, cookies, chat
  writes or moderation actions.
- Discovery uses HTTPS on an explicit `kick.com` allowlist.
- The WebSocket endpoint is a fixed `wss://ws-us2.pusher.com` URL rather than a
  value accepted from a discovery response.
- WebSocket frames are capped at 1 MiB and parsed defensively. Discovery JSON is
  parsed as untrusted data; adding an explicit response-size cap remains a
  defense-in-depth improvement.
- Remote content is never evaluated as Lua and cannot select an executable,
  command or local path.
- Production logs must not contain full frames, chat histories, continuations,
  authorization material or identifiers unnecessary for diagnosis.

## Overlay publishing

Overlay support is optional and publishes normalized chat data only to
`http://127.0.0.1:8765/api/events`. It never forwards cookies, tokens, discovery
responses or WebSocket metadata. A missing overlay is a non-fatal state.

The shared contract and local-agent controls are documented by
[chatterino-multichat-overlay](https://github.com/tears-mysthrala/chatterino-multichat-overlay/blob/main/SECURITY.md).

## Updates

Update notifications may request stable release metadata from the canonical
GitHub repository at most once every 24 hours. They must be disableable, send no
channel/account/chat data and never download or execute an update automatically.
Release assets are installed only through an explicit user action and should be
verified against the published SHA-256 checksum.

On Windows, `install-or-update.cmd` invokes the operating system's bundled
Windows PowerShell with an execution-policy bypass limited to that installer
process. It does not change the user or machine policy and does not require
administrator access. The installer closes Chatterino before changing settings,
moves the previous plugin and settings to a recoverable backup outside the
active `Plugins` directory, preserves and hashes `data/`, enables plugin support
and this plugin, and restores the previous installation if an update fails.

## Reporting

Report vulnerabilities privately through GitHub Security Advisories. Include
the affected version, synthetic reproduction and security impact. Do not place
working exploits, credentials or private chat content in a public issue. We aim
to acknowledge reports within seven days.

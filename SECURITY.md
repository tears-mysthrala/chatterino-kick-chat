# Security

The plugin is read-only and anonymous. It does not request Kick credentials,
send messages, moderate users, execute remote code or load response bodies as
Lua. Input URLs are restricted to HTTPS on `kick.com`; discovery JSON and
WebSocket frames are parsed as untrusted data with a 1 MiB frame limit.

Report vulnerabilities privately to the repository owner. Do not include
credentials or private chat data in a report.

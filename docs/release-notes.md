# chatterino-kick-chat 0.3.3

This patch makes the one-click Windows installer reliable when Chatterino
leaves a background process behind or `Get-FileHash` is unavailable during
Windows PowerShell script execution. Chat behavior is unchanged.

## Install or update on Windows

1. Download `chatterino-kick-chat-0.3.3.zip` and its matching `.sha256`
   file from this release.
2. Before extraction, open PowerShell in the download folder and run
   `(Get-FileHash .\chatterino-kick-chat-0.3.3.zip -Algorithm SHA256).Hash`.
3. Compare the result with the hash in the `.sha256` file. Continue only when
   they match.
4. Select **Extract all** in File Explorer.
5. Double-click `install-or-update.cmd` in the extracted folder. Do not run it
   as administrator.
6. Reopen Chatterino and run `/kick-chat status`.

The launcher uses the Windows PowerShell already included with Windows. Its
execution-policy bypass applies only to the installer process. The installer
requests a normal Chatterino shutdown and, after a 15-second grace period,
stops only remaining processes without a window. It creates a recoverable
backup under `%APPDATA%\Chatterino2\PluginBackups`, preserves and hashes the plugin's `data/`
directory, migrates compatible data from older versioned plugin folders,
enables plugin support and this plugin, and restores the previous installation
if an update fails.

## From this release onward

Future Windows updates use the same flow: download, verify, extract, and
double-click `install-or-update.cmd`. No files need to be copied into
Chatterino by hand. Update notifications remain advisory: they may link to a
stable GitHub release, but they never download, extract, replace, or execute an
update automatically. macOS and Linux installations remain manual.

## Assets

- `chatterino-kick-chat-0.3.3.zip`
- `chatterino-kick-chat-0.3.3.zip.sha256`

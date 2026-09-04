# chatterino-kick-chat 0.3.2

This release adds a safe one-click Windows installer and updater. Chat behavior
is unchanged.

## Install or update on Windows

1. Download `chatterino-kick-chat-0.3.2.zip` and its `.sha256` file from this
   release, then verify the ZIP.
2. Select **Extract all** in File Explorer.
3. Double-click `install-or-update.cmd` in the extracted folder. Do not run it
   as administrator.
4. Reopen Chatterino and run `/kick-chat status`.

The launcher uses the Windows PowerShell already included with Windows. Its
execution-policy bypass applies only to the installer process. The installer
closes Chatterino normally, creates a recoverable backup under
`%APPDATA%\Chatterino2\PluginBackups`, preserves and hashes the plugin's `data/`
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

- `chatterino-kick-chat-0.3.2.zip`
- `chatterino-kick-chat-0.3.2.zip.sha256`

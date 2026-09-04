$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function New-TestDirectory {
  param([string[]]$Path)
  foreach ($entry in $Path) { [IO.Directory]::CreateDirectory($entry) | Out-Null }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceInstaller = Join-Path $PSScriptRoot "install.ps1"
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("kick-installer-test-" + [Guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $sandbox "package[release]"
$installer = Join-Path $packageRoot "scripts\install.ps1"
$pluginTarget = Join-Path $sandbox "Plugins\chatterino-kick-chat"
$settingsPath = Join-Path $sandbox "Settings\settings.json"

try {
  New-TestDirectory -Path (Split-Path -Parent $installer)
  Copy-Item -LiteralPath $sourceInstaller -Destination $installer
  Copy-Item -LiteralPath (Join-Path $repoRoot "src") -Destination $packageRoot -Recurse
  Copy-Item -LiteralPath (Join-Path $repoRoot "init.lua"), (Join-Path $repoRoot "info.json"), (Join-Path $repoRoot "LICENSE"), (Join-Path $repoRoot "SECURITY.md") -Destination $packageRoot
  New-TestDirectory -Path @((Join-Path $pluginTarget "data"), (Split-Path -Parent $settingsPath))
  [IO.File]::WriteAllText((Join-Path $pluginTarget "data\KICK_CHAT.json"), '{"saved":true}')
  [IO.File]::WriteAllText((Join-Path $pluginTarget "obsolete.lua"), 'old')
  [IO.File]::WriteAllText($settingsPath, '{"plugins":{"supportEnabled":false,"enabledPlugins":["other-plugin","chatterino-kick-chat-0.1.0","Chatterino-Kick-Chat"]},"unrelated":{"keep":42,"label":"Canal espa\u00f1ol \u65e5\u672c\u8a9e \ud83d\udd25"}}')

  & $installer -ChatterinoRoot $sandbox -SkipProcessCheck
  if (-not (Test-Path -LiteralPath (Join-Path $pluginTarget "src"))) { throw "src was not installed" }
  if (Test-Path -LiteralPath (Join-Path $pluginTarget "obsolete.lua")) { throw "obsolete payload was not removed" }
  if ((Get-Content -LiteralPath (Join-Path $pluginTarget "data\KICK_CHAT.json") -Raw) -ne '{"saved":true}') { throw "saved data changed" }

  $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $expectedLabel = '"Canal espa\u00f1ol \u65e5\u672c\u8a9e \ud83d\udd25"' | ConvertFrom-Json
  if (-not $settings.plugins.supportEnabled) { throw "plugin support was not enabled" }
  if (@($settings.plugins.enabledPlugins) -cnotcontains "chatterino-kick-chat") { throw "plugin was not enabled with its exact id" }
  if (@($settings.plugins.enabledPlugins) -ccontains "Chatterino-Kick-Chat") { throw "plugin id casing variant remains enabled" }
  if (@($settings.plugins.enabledPlugins) -contains "chatterino-kick-chat-0.1.0") { throw "legacy plugin id remains enabled" }
  if (@($settings.plugins.enabledPlugins) -notcontains "other-plugin" -or $settings.unrelated.keep -ne 42 -or $settings.unrelated.label -ne $expectedLabel) { throw "unrelated settings changed" }

  $nullPluginsRoot = Join-Path $sandbox "NullPluginsCase"
  $nullPluginsSettingsPath = Join-Path $nullPluginsRoot "Settings\settings.json"
  New-TestDirectory -Path (Split-Path -Parent $nullPluginsSettingsPath)
  [IO.File]::WriteAllText($nullPluginsSettingsPath, '{"plugins":null,"unrelated":{"keep":7}}')
  & $installer -ChatterinoRoot $nullPluginsRoot -SkipProcessCheck
  $nullPluginsSettings = [IO.File]::ReadAllText($nullPluginsSettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  if (-not $nullPluginsSettings.plugins.supportEnabled -or @($nullPluginsSettings.plugins.enabledPlugins) -cnotcontains "chatterino-kick-chat" -or $nullPluginsSettings.unrelated.keep -ne 7) {
    throw "null plugins settings were not initialized safely"
  }

  $migrationRoot = Join-Path $sandbox "MigrationCase"
  $legacyData = Join-Path $migrationRoot "Plugins\chatterino-kick-chat-0.1.0\data"
  $migrationSettingsPath = Join-Path $migrationRoot "Settings\settings.json"
  New-TestDirectory -Path @($legacyData, (Split-Path -Parent $migrationSettingsPath))
  $hiddenLegacyFile = Join-Path $legacyData "KICK_CHAT.json"
  [IO.File]::WriteAllText($hiddenLegacyFile, '{"legacy":true}')
  (Get-Item -LiteralPath $hiddenLegacyFile -Force).Attributes = (Get-Item -LiteralPath $hiddenLegacyFile -Force).Attributes -bor [IO.FileAttributes]::Hidden
  [IO.File]::WriteAllText($migrationSettingsPath, '{"plugins":{"supportEnabled":true,"enabledPlugins":["other-plugin"]}}')
  & $installer -ChatterinoRoot $migrationRoot -SkipProcessCheck
  if ((Get-Content -LiteralPath (Join-Path $migrationRoot "Plugins\chatterino-kick-chat\data\KICK_CHAT.json") -Raw) -ne '{"legacy":true}') {
    throw "legacy saved data was not migrated"
  }
  $migrationSettings = Get-Content -LiteralPath $migrationSettingsPath -Raw | ConvertFrom-Json
  if (@($migrationSettings.plugins.enabledPlugins) -contains "chatterino-kick-chat-0.1.0") { throw "migrated legacy plugin id remains enabled" }
  if (@($migrationSettings.plugins.enabledPlugins) -cnotcontains "chatterino-kick-chat" -or @($migrationSettings.plugins.enabledPlugins) -notcontains "other-plugin") {
    throw "disabled legacy installation was not migrated and enabled without preserving other plugins"
  }
  if (Test-Path -LiteralPath (Split-Path -Parent $legacyData)) { throw "migrated legacy plugin folder remains active" }
  $legacyBackups = @(Get-ChildItem -LiteralPath (Join-Path $migrationRoot "PluginBackups") -Directory -Recurse | Where-Object { $_.Name -eq "chatterino-kick-chat-0.1.0" })
  if ($legacyBackups.Count -ne 1 -or (Get-Content -LiteralPath (Join-Path $legacyBackups[0].FullName "data\KICK_CHAT.json") -Raw) -ne '{"legacy":true}') {
    throw "migrated legacy plugin folder was not preserved in the backup"
  }

  $conflictRoot = Join-Path $sandbox "ConflictCase"
  $conflictCanonicalData = Join-Path $conflictRoot "Plugins\chatterino-kick-chat\data"
  $conflictLegacyData = Join-Path $conflictRoot "Plugins\chatterino-kick-chat-0.1.0\data"
  $conflictSettingsPath = Join-Path $conflictRoot "Settings\settings.json"
  New-TestDirectory -Path @($conflictCanonicalData, $conflictLegacyData, (Split-Path -Parent $conflictSettingsPath))
  [IO.File]::WriteAllText((Join-Path $conflictCanonicalData "KICK_CHAT.json"), '{"canonical":true}')
  [IO.File]::WriteAllText((Join-Path $conflictLegacyData "KICK_CHAT.json"), '{"legacy":true}')
  [IO.File]::WriteAllText($conflictSettingsPath, '{"plugins":{"supportEnabled":true,"enabledPlugins":["chatterino-kick-chat-0.1.0"]}}')
  $conflictRejected = $false
  try { & $installer -ChatterinoRoot $conflictRoot -SkipProcessCheck } catch { $conflictRejected = $true }
  if (-not $conflictRejected) { throw "conflicting saved data was not rejected" }
  if ((Get-Content -LiteralPath (Join-Path $conflictCanonicalData "KICK_CHAT.json") -Raw) -ne '{"canonical":true}') { throw "conflict rollback did not restore canonical data" }
  $conflictSettings = Get-Content -LiteralPath $conflictSettingsPath -Raw | ConvertFrom-Json
  if (@($conflictSettings.plugins.enabledPlugins) -notcontains "chatterino-kick-chat-0.1.0" -or @($conflictSettings.plugins.enabledPlugins) -contains "chatterino-kick-chat") {
    throw "conflict rollback changed plugin activation"
  }

  & $installer -ChatterinoRoot $sandbox -SkipProcessCheck
  $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
  if (@($settings.plugins.enabledPlugins | Where-Object { $_ -eq "chatterino-kick-chat" }).Count -ne 1) {
    throw "reinstall duplicated the plugin id"
  }
  if (@(Get-ChildItem -LiteralPath (Join-Path $sandbox "PluginBackups") -Directory).Count -lt 2) {
    throw "install backups were not created"
  }
  $fullBackups = @(Get-ChildItem -LiteralPath (Join-Path $sandbox "PluginBackups") -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName "plugin") -PathType Container
  })
  if ($fullBackups.Count -lt 1) { throw "the previous plugin was not moved outside Plugins into a full backup" }

  Write-Host "Kick installer behavior verified."
} finally {
  $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if ($resolvedSandbox.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force -ErrorAction SilentlyContinue
  }
}

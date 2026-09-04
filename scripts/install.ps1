[CmdletBinding()]
param(
  [string]$ChatterinoRoot = (Join-Path $env:APPDATA "Chatterino2"),
  [switch]$CloseChatterino,
  [switch]$SkipProcessCheck
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$pluginName = "chatterino-kick-chat"
$packageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$payloadEntries = @("src", "init.lua", "info.json", "LICENSE", "SECURITY.md")
$pluginsRoot = Join-Path $ChatterinoRoot "Plugins"
$pluginTarget = Join-Path $pluginsRoot $pluginName
$settingsPath = Join-Path $ChatterinoRoot "Settings\settings.json"
$installId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$backupPath = Join-Path (Join-Path $ChatterinoRoot "PluginBackups") "$pluginName-$installId"
$stageTarget = Join-Path $backupPath "stage"
$previousTarget = Join-Path $backupPath "plugin"
$quarantinedLegacy = @()

function Set-JsonProperty {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -ne $Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
  }
}

function Ensure-Directory {
  param([string[]]$Path)
  foreach ($entry in $Path) { [IO.Directory]::CreateDirectory($entry) | Out-Null }
}

function Assert-ChatterinoClosed {
  if ($SkipProcessCheck) { return }
  $running = @(Get-Process -Name "chatterino" -ErrorAction SilentlyContinue)
  if ($running.Count -eq 0) { return }
  if (-not $CloseChatterino) {
    throw "Chatterino is running. Close it and run the installer again."
  }

  Write-Host "Closing Chatterino so its settings can be updated safely..."
  foreach ($process in $running) { [void]$process.CloseMainWindow() }
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  do {
    Start-Sleep -Milliseconds 250
    $running = @(Get-Process -Name "chatterino" -ErrorAction SilentlyContinue)
  } while ($running.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
  if ($running.Count -gt 0) {
    throw "Chatterino did not close. Close it manually and run the installer again."
  }
}

function Get-DataFingerprint {
  param([string]$DataPath)
  if (-not (Test-Path -LiteralPath $DataPath -PathType Container)) { return @() }
  return @(
    Get-ChildItem -LiteralPath $DataPath -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
      $relative = $_.FullName.Substring($DataPath.Length).TrimStart('\', '/')
      "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative
    }
  )
}

function Move-LegacyPluginToBackup {
  param([string]$Id)
  $source = Join-Path $pluginsRoot $Id
  if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
  $legacyBackupRoot = Join-Path $backupPath "legacy"
  $destination = Join-Path $legacyBackupRoot $Id
  if (Test-Path -LiteralPath $destination) { throw "Legacy backup already exists for $Id." }
  Ensure-Directory -Path $legacyBackupRoot
  Move-Item -LiteralPath $source -Destination $destination
  $script:quarantinedLegacy += [pscustomobject]@{ Source = $source; Backup = $destination }
  Write-Host "Moved legacy plugin folder $Id into the recoverable backup."
}

function Restore-QuarantinedLegacyPlugins {
  $failures = @()
  for ($index = $script:quarantinedLegacy.Count - 1; $index -ge 0; $index--) {
    $move = $script:quarantinedLegacy[$index]
    if (-not (Test-Path -LiteralPath $move.Backup -PathType Container)) { continue }
    if (Test-Path -LiteralPath $move.Source) {
      $failures += "Could not restore legacy plugin folder $($move.Source): the path already exists."
      continue
    }
    try { Move-Item -LiteralPath $move.Backup -Destination $move.Source -ErrorAction Stop }
    catch { $failures += $_.Exception.Message }
  }
  if ($failures.Count -gt 0) { throw ($failures -join " ") }
}

function Enable-ChatterinoPlugin {
  $settingsDirectory = Split-Path -Parent $settingsPath
  Ensure-Directory -Path $settingsDirectory
  $settingsBackup = Join-Path $backupPath "settings.json"
  $tempSettings = Join-Path $settingsDirectory ".settings-$installId.tmp"

  if ($settingsExisted) {
    Copy-Item -LiteralPath $settingsPath -Destination $settingsBackup -Force
    $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $settings) { throw "Chatterino settings are empty or invalid." }
  } else {
    $settings = [pscustomobject]@{}
  }

  try {
    if ($null -eq $settings.PSObject.Properties["plugins"] -or $settings.plugins -isnot [pscustomobject]) {
      Set-JsonProperty -Object $settings -Name "plugins" -Value ([pscustomobject]@{})
    }
    $plugins = $settings.plugins
    Set-JsonProperty -Object $plugins -Name "supportEnabled" -Value $true

    $enabled = @()
    $configuredIds = @()
    $legacyPattern = "^" + [Regex]::Escape($pluginName) + "-\d+\.\d+\.\d+(?:[-+].*)?$"
    if ($null -ne $plugins.PSObject.Properties["enabledPlugins"]) {
      $configuredIds = @($plugins.enabledPlugins)
    }
    $legacyDirectoryIds = @(Get-ChildItem -LiteralPath $pluginsRoot -Directory -Force |
      Where-Object { $_.Name -match $legacyPattern } | ForEach-Object { $_.Name })
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in @($configuredIds + $legacyDirectoryIds)) {
        if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) { continue }
        if ([string]::Equals($id, $pluginName, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($id -match $legacyPattern) {
          $legacyData = Join-Path (Join-Path $pluginsRoot $id) "data"
          $legacyFiles = @(Get-DataFingerprint -DataPath $legacyData)
          if ($legacyFiles.Count -gt 0) {
            $canonicalData = Join-Path $pluginTarget "data"
            $canonicalFiles = @(Get-DataFingerprint -DataPath $canonicalData)
            if ($canonicalFiles.Count -eq 0) {
              Ensure-Directory -Path $canonicalData
              Get-ChildItem -LiteralPath $legacyData -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $canonicalData -Recurse -Force
              }
              $migratedFiles = @(Get-DataFingerprint -DataPath $canonicalData)
              foreach ($legacyFile in $legacyFiles) {
                if ($migratedFiles -notcontains $legacyFile) { throw "Could not verify migrated data from $id." }
              }
              Write-Host "Migrated saved data from legacy plugin folder $id."
              Move-LegacyPluginToBackup -Id $id
              continue
            }
            $alreadyMigrated = $true
            foreach ($legacyFile in $legacyFiles) {
              if ($canonicalFiles -notcontains $legacyFile) { $alreadyMigrated = $false; break }
            }
            if ($alreadyMigrated) {
              Write-Host "Legacy plugin data from $id is already present in $pluginName."
              Move-LegacyPluginToBackup -Id $id
              continue
            }
            throw "Both $id and $pluginName contain different saved data. Nothing was disabled; reconcile those data folders and run the installer again."
          } else {
            Move-LegacyPluginToBackup -Id $id
            continue
          }
        }
      if ($seen.Add($id)) { $enabled += $id }
    }
    $enabled += $pluginName
    Set-JsonProperty -Object $plugins -Name "enabledPlugins" -Value @($enabled)

    $json = $settings | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($tempSettings, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    $verified = [IO.File]::ReadAllText($tempSettings, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $verified.plugins.supportEnabled -or @($verified.plugins.enabledPlugins) -cnotcontains $pluginName) {
      throw "The updated Chatterino settings could not be verified."
    }
    Move-Item -LiteralPath $tempSettings -Destination $settingsPath -Force
  } catch {
    Remove-Item -LiteralPath $tempSettings -Force -ErrorAction SilentlyContinue
    if ($settingsExisted -and (Test-Path -LiteralPath $settingsBackup)) {
      Copy-Item -LiteralPath $settingsBackup -Destination $settingsPath -Force
    } elseif (-not $settingsExisted) {
      Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
    }
    throw
  }
}

function Restore-ChatterinoSettings {
  $settingsBackup = Join-Path $backupPath "settings.json"
  if ($settingsExisted -and (Test-Path -LiteralPath $settingsBackup)) {
    Copy-Item -LiteralPath $settingsBackup -Destination $settingsPath -Force
  } elseif (-not $settingsExisted) {
    Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
  }
}

foreach ($entry in $payloadEntries) {
  if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $entry))) {
    throw "The package is incomplete: missing $entry. Extract the whole release ZIP before running the installer."
  }
}

Assert-ChatterinoClosed
$settingsExisted = Test-Path -LiteralPath $settingsPath -PathType Leaf
Ensure-Directory -Path @($pluginsRoot, $backupPath, $stageTarget)

$dataBefore = Get-DataFingerprint -DataPath (Join-Path $pluginTarget "data")

foreach ($entry in $payloadEntries) {
  Copy-Item -LiteralPath (Join-Path $packageRoot $entry) -Destination $stageTarget -Recurse -Force
}
if (Test-Path -LiteralPath (Join-Path $pluginTarget "data") -PathType Container) {
  Copy-Item -LiteralPath (Join-Path $pluginTarget "data") -Destination $stageTarget -Recurse -Force
}

$swapped = $false
try {
  if (Test-Path -LiteralPath $pluginTarget) {
    Move-Item -LiteralPath $pluginTarget -Destination $previousTarget
  }
  Move-Item -LiteralPath $stageTarget -Destination $pluginTarget
  $swapped = $true

  Enable-ChatterinoPlugin

  $manifest = [IO.File]::ReadAllText((Join-Path $pluginTarget "info.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
  if ($manifest.name -ne $pluginName) { throw "Installed plugin manifest has the wrong name." }
  $dataAfter = Get-DataFingerprint -DataPath (Join-Path $pluginTarget "data")
  foreach ($savedEntry in $dataBefore) {
    if ($dataAfter -notcontains $savedEntry) { throw "Saved plugin data changed during installation." }
  }

} catch {
  $installError = $_
  $rollbackErrors = @()
  try { Restore-ChatterinoSettings } catch { $rollbackErrors += $_.Exception.Message }
  if ($swapped -and (Test-Path -LiteralPath $pluginTarget)) {
    try { Remove-Item -LiteralPath $pluginTarget -Recurse -Force -ErrorAction Stop }
    catch { $rollbackErrors += $_.Exception.Message }
  }
  if (Test-Path -LiteralPath $previousTarget) {
    if (Test-Path -LiteralPath $pluginTarget) {
      $rollbackErrors += "The failed plugin target still exists, so the previous version was not moved into it."
    } else {
      try { Move-Item -LiteralPath $previousTarget -Destination $pluginTarget -ErrorAction Stop }
      catch { $rollbackErrors += $_.Exception.Message }
    }
  }
  if (Test-Path -LiteralPath $stageTarget) {
    try { Remove-Item -LiteralPath $stageTarget -Recurse -Force -ErrorAction Stop }
    catch { $rollbackErrors += $_.Exception.Message }
  }
  try { Restore-QuarantinedLegacyPlugins } catch { $rollbackErrors += $_.Exception.Message }
  if ($rollbackErrors.Count -gt 0) {
    throw "Installation failed: $($installError.Exception.Message) Rollback also failed: $($rollbackErrors -join ' ') Backup: $backupPath"
  }
  throw $installError
}

Write-Host "Installed and enabled $pluginName version $($manifest.version)."
Write-Host "Backup: $backupPath"
Write-Host "Open Chatterino and run /kick-chat status in a named channel."

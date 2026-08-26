$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
wsl.exe bash -lc "cd /mnt/d/github/chatterino-kick-chat && lua tests/run.lua"

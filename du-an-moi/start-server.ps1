param(
  [int]$Port = 8092,
  [string]$BindAddress = "0.0.0.0"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "server.ps1") -Port $Port -BindAddress $BindAddress

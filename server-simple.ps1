param(
  [int]$Port = 8091
)

$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.png'  { 'image/png' }
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.gif'  { 'image/gif' }
    '.svg'  { 'image/svg+xml' }
    '.mp3'  { 'audio/mpeg' }
    '.wav'  { 'audio/wav' }
    default { 'application/octet-stream' }
  }
}

function Send-Response($stream, [int]$status, [string]$statusText, [string]$contentType, [byte[]]$body) {
  $headers = "HTTP/1.1 $status $statusText`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($body.Length -gt 0) {
    $stream.Write($body, 0, $body.Length)
  }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port"

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 1024, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

    $parts = $requestLine.Split(' ')
    if ($parts.Length -lt 2) { continue }

    $method = $parts[0].ToUpperInvariant()
    $rawPath = $parts[1]

    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq '') { break }
    }

    if ($method -ne 'GET' -and $method -ne 'HEAD') {
      $body = [Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
      Send-Response $stream 405 'Method Not Allowed' 'text/plain; charset=utf-8' $body
      continue
    }

    $pathOnly = $rawPath.Split('?')[0]
    $decoded = [Uri]::UnescapeDataString($pathOnly)
    if ($decoded -eq '/') { $decoded = '/index.html' }

    $rel = $decoded.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $root $rel))

    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      $body = [Text.Encoding]::UTF8.GetBytes('404 Not Found')
      Send-Response $stream 404 'Not Found' 'text/plain; charset=utf-8' $body
      continue
    }

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    $contentType = Get-ContentType $fullPath

    if ($method -eq 'HEAD') {
      Send-Response $stream 200 'OK' $contentType @()
    } else {
      Send-Response $stream 200 'OK' $contentType $bytes
    }
  }
  catch {
    try {
      $stream = $client.GetStream()
      $body = [Text.Encoding]::UTF8.GetBytes('500 Internal Server Error')
      Send-Response $stream 500 'Internal Server Error' 'text/plain; charset=utf-8' $body
    } catch {}
  }
  finally {
    $client.Close()
  }
}

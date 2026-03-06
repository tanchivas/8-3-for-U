param(
  [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataFile = Join-Path $ScriptDir "data.json"
$IndexFile = Join-Path $ScriptDir "index.html"
$Sessions = @{}

function New-SeedDb {
  [pscustomobject]@{
    users = @(
      [pscustomobject]@{ id = "u-admin"; username = "admin"; password = "123456"; name = "Quan Ly"; role = "manager" },
      [pscustomobject]@{ id = "u-cn01"; username = "cn01"; password = "123456"; name = "Cong Nhan 01"; role = "worker" },
      [pscustomobject]@{ id = "u-cn02"; username = "cn02"; password = "123456"; name = "Cong Nhan 02"; role = "worker" }
    )
    records = @()
  }
}

function Ensure-Db {
  if (-not (Test-Path $DataFile)) {
    (New-SeedDb | ConvertTo-Json -Depth 10) | Set-Content -Path $DataFile -Encoding UTF8
  }
}

function Load-Db {
  Ensure-Db
  $db = Get-Content -Path $DataFile -Raw | ConvertFrom-Json
  if (-not $db.PSObject.Properties["users"]) { $db | Add-Member -NotePropertyName users -NotePropertyValue @() }
  if (-not $db.PSObject.Properties["records"]) { $db | Add-Member -NotePropertyName records -NotePropertyValue @() }
  return $db
}

function Save-Db($db) {
  ($db | ConvertTo-Json -Depth 10) | Set-Content -Path $DataFile -Encoding UTF8
}

function Send-Json($ctx, [int]$statusCode, $obj) {
  $json = $obj | ConvertTo-Json -Depth 10 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $ctx.Response.StatusCode = $statusCode
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}

function Send-Text($ctx, [int]$statusCode, [string]$contentType, [string]$text) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  $ctx.Response.StatusCode = $statusCode
  $ctx.Response.ContentType = $contentType
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}

function Read-JsonBody($ctx) {
  $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream, $ctx.Request.ContentEncoding)
  $raw = $reader.ReadToEnd()
  $reader.Close()
  if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
  return ($raw | ConvertFrom-Json)
}

function Parse-Cookies($ctx) {
  $map = @{}
  $header = $ctx.Request.Headers["Cookie"]
  if ([string]::IsNullOrWhiteSpace($header)) { return $map }
  foreach ($part in ($header -split ";")) {
    $kv = $part.Trim() -split "=", 2
    if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() }
  }
  return $map
}

function Parse-Query([string]$queryRaw) {
  $map = @{}
  if ([string]::IsNullOrWhiteSpace($queryRaw)) { return $map }
  $q = $queryRaw.TrimStart("?")
  if ([string]::IsNullOrWhiteSpace($q)) { return $map }
  foreach ($pair in ($q -split "&")) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }
    $kv = $pair -split "=", 2
    $k = [System.Uri]::UnescapeDataString($kv[0])
    $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { "" }
    $map[$k] = $v
  }
  return $map
}

function Today { (Get-Date).ToString("yyyy-MM-dd") }
function TimeNow { (Get-Date).ToString("HH:mm:ss") }

function Get-SessionUser($ctx, $db) {
  $sid = (Parse-Cookies $ctx)["session_id"]
  if ([string]::IsNullOrWhiteSpace($sid)) { return $null }
  if (-not $Sessions.ContainsKey($sid)) { return $null }
  $uid = $Sessions[$sid]
  return $db.users | Where-Object { $_.id -eq $uid } | Select-Object -First 1
}

function Require-Role($ctx, $db, [string]$role) {
  $user = Get-SessionUser $ctx $db
  if (-not $user) {
    Send-Json $ctx 401 @{ error = "Ban chua dang nhap" }
    return $null
  }
  if ($user.role -ne $role) {
    Send-Json $ctx 403 @{ error = "Khong du quyen" }
    return $null
  }
  return $user
}

function Handle-Api($ctx) {
  $db = Load-Db
  $method = $ctx.Request.HttpMethod.ToUpperInvariant()
  $path = $ctx.Request.Url.AbsolutePath.ToLowerInvariant()

  if ($method -eq "POST" -and $path -eq "/api/login") {
    $body = Read-JsonBody $ctx
    $user = $db.users | Where-Object { $_.username -eq [string]$body.username -and $_.password -eq [string]$body.password } | Select-Object -First 1
    if (-not $user) { Send-Json $ctx 401 @{ error = "Sai tai khoan hoac mat khau" }; return }
    $sid = [guid]::NewGuid().ToString("N")
    $Sessions[$sid] = $user.id
    $ctx.Response.AppendHeader("Set-Cookie", "session_id=$sid; Path=/; HttpOnly; SameSite=Lax")
    Send-Json $ctx 200 @{ user = @{ id = $user.id; name = $user.name; role = $user.role; username = $user.username } }
    return
  }

  if ($method -eq "POST" -and $path -eq "/api/logout") {
    $sid = (Parse-Cookies $ctx)["session_id"]
    if ($sid -and $Sessions.ContainsKey($sid)) { $Sessions.Remove($sid) }
    $ctx.Response.AppendHeader("Set-Cookie", "session_id=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax")
    Send-Json $ctx 200 @{ ok = $true }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/me") {
    $me = Get-SessionUser $ctx $db
    if (-not $me) { Send-Json $ctx 401 @{ error = "Ban chua dang nhap" }; return }
    Send-Json $ctx 200 @{ user = @{ id = $me.id; name = $me.name; role = $me.role; username = $me.username } }
    return
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/checkin") {
    $me = Require-Role $ctx $db "worker"
    if (-not $me) { return }
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec) {
      $rec = [pscustomobject]@{ id = [guid]::NewGuid().ToString("N"); workerId = $me.id; date = $d; checkIn = ""; checkOut = "" }
      $db.records += $rec
    }
    if ($rec.checkIn) { Send-Json $ctx 400 @{ error = "Ban da check-in hom nay" }; return }
    $rec.checkIn = TimeNow
    Save-Db $db
    Send-Json $ctx 200 @{ ok = $true; record = $rec }
    return
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/checkout") {
    $me = Require-Role $ctx $db "worker"
    if (-not $me) { return }
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec -or -not $rec.checkIn) { Send-Json $ctx 400 @{ error = "Ban chua check-in" }; return }
    if ($rec.checkOut) { Send-Json $ctx 400 @{ error = "Ban da check-out hom nay" }; return }
    $rec.checkOut = TimeNow
    Save-Db $db
    Send-Json $ctx 200 @{ ok = $true; record = $rec }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/my-attendance/today") {
    $me = Require-Role $ctx $db "worker"
    if (-not $me) { return }
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec) { $rec = @{ workerId = $me.id; date = $d; checkIn = ""; checkOut = "" } }
    Send-Json $ctx 200 @{ record = $rec }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/workers") {
    $me = Require-Role $ctx $db "manager"
    if (-not $me) { return }
    $workers = @($db.users | Where-Object { $_.role -eq "worker" } | ForEach-Object { @{ id = $_.id; name = $_.name; username = $_.username } })
    Send-Json $ctx 200 @{ workers = $workers }
    return
  }

  if ($method -eq "POST" -and $path -eq "/api/workers") {
    $me = Require-Role $ctx $db "manager"
    if (-not $me) { return }
    $body = Read-JsonBody $ctx
    $name = ([string]$body.name).Trim()
    $username = ([string]$body.username).Trim()
    $password = ([string]$body.password).Trim()
    if (-not $name -or -not $username -or -not $password) { Send-Json $ctx 400 @{ error = "Thieu thong tin" }; return }
    $exists = $db.users | Where-Object { $_.username.ToLower() -eq $username.ToLower() } | Select-Object -First 1
    if ($exists) { Send-Json $ctx 400 @{ error = "Ten dang nhap da ton tai" }; return }
    $newUser = [pscustomobject]@{ id = "u-" + [guid]::NewGuid().ToString("N").Substring(0,8); username = $username; password = $password; name = $name; role = "worker" }
    $db.users += $newUser
    Save-Db $db
    Send-Json $ctx 201 @{ worker = @{ id = $newUser.id; name = $newUser.name; username = $newUser.username } }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/stats/today") {
    $me = Require-Role $ctx $db "manager"
    if (-not $me) { return }
    $d = Today
    $workers = @($db.users | Where-Object { $_.role -eq "worker" })
    $recs = @($db.records | Where-Object { $_.date -eq $d })
    Send-Json $ctx 200 @{
      stats = @{
        date = $d
        totalWorkers = $workers.Count
        checkedIn = (@($recs | Where-Object { $_.checkIn })).Count
        checkedOut = (@($recs | Where-Object { $_.checkOut })).Count
      }
    }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/attendance") {
    $me = Require-Role $ctx $db "manager"
    if (-not $me) { return }
    $q = Parse-Query $ctx.Request.Url.Query
    $date = $q["date"]
    $workerId = $q["workerId"]
    $rows = @($db.records)
    if ($date) { $rows = @($rows | Where-Object { $_.date -eq $date }) }
    if ($workerId) { $rows = @($rows | Where-Object { $_.workerId -eq $workerId }) }
    $mapped = @($rows | Sort-Object date, workerId | ForEach-Object {
      $w = $db.users | Where-Object { $_.id -eq $PSItem.workerId } | Select-Object -First 1
      @{
        id = $PSItem.id
        date = $PSItem.date
        workerId = $PSItem.workerId
        workerName = if ($w) { $w.name } else { $PSItem.workerId }
        workerUsername = if ($w) { $w.username } else { "" }
        checkIn = $PSItem.checkIn
        checkOut = $PSItem.checkOut
        status = if ($PSItem.checkOut) { "Hoan tat" } elseif ($PSItem.checkIn) { "Dang lam" } else { "Chua vao" }
      }
    })
    Send-Json $ctx 200 @{ records = $mapped }
    return
  }

  if ($method -eq "GET" -and $path -eq "/api/attendance/export") {
    $me = Require-Role $ctx $db "manager"
    if (-not $me) { return }
    $q = Parse-Query $ctx.Request.Url.Query
    $date = $q["date"]
    $workerId = $q["workerId"]
    $rows = @($db.records)
    if ($date) { $rows = @($rows | Where-Object { $_.date -eq $date }) }
    if ($workerId) { $rows = @($rows | Where-Object { $_.workerId -eq $workerId }) }
    $lines = @("Ngay,CongNhan,Username,CheckIn,CheckOut,TrangThai")
    foreach ($r in $rows) {
      $w = $db.users | Where-Object { $_.id -eq $r.workerId } | Select-Object -First 1
      $status = if ($r.checkOut) { "Hoan tat" } elseif ($r.checkIn) { "Dang lam" } else { "Chua vao" }
      $workerName = if ($w) { $w.name } else { $r.workerId }
      $workerUsername = if ($w) { $w.username } else { "" }
      $vals = @($r.date, $workerName, $workerUsername, $r.checkIn, $r.checkOut, $status) | ForEach-Object { '"' + (($_ -as [string]).Replace('"','""')) + '"' }
      $lines += ($vals -join ",")
    }
    $csv = $lines -join "`n"
    $ctx.Response.AppendHeader("Content-Disposition", "attachment; filename=cham-cong-$(Today).csv")
    Send-Text $ctx 200 "text/csv; charset=utf-8" $csv
    return
  }

  Send-Json $ctx 404 @{ error = "Khong tim thay API" }
}

function Handle-Static($ctx) {
  $path = $ctx.Request.Url.AbsolutePath
  if ($path -eq "/" -or $path -eq "/index.html") {
    $html = Get-Content -Path $IndexFile -Raw
    Send-Text $ctx 200 "text/html; charset=utf-8" $html
    return
  }
  Send-Text $ctx 404 "text/plain; charset=utf-8" "Not Found"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

Write-Host "Server dang chay tai http://localhost:$Port"
Write-Host "Nhan Ctrl+C de dung"

while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath.ToLowerInvariant()
    if ($path.StartsWith("/api/")) { Handle-Api $ctx } else { Handle-Static $ctx }
  }
  catch [System.Net.HttpListenerException] {
    break
  }
  catch {
    Write-Host "Loi server: $($_.Exception.Message)"
    if ($ctx -and $ctx.Response) {
      try { Send-Json $ctx 500 @{ error = "Loi server noi bo" } } catch {}
    }
  }
}

$listener.Stop()
$listener.Close()

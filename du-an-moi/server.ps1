param(
  [int]$Port = 8092,
  [string]$BindAddress = "0.0.0.0"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataFile = Join-Path $ScriptDir "data.json"
$Sessions = @{}

function New-SeedDb {
  [pscustomobject]@{
    users = @(
      [pscustomobject]@{ id = "u-admin"; username = "admin"; password = "123456"; name = "Quan Ly Xuong"; role = "manager" },
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

function New-JsonResponse([int]$statusCode, $obj, [hashtable]$extraHeaders = @{}) {
  $json = $obj | ConvertTo-Json -Depth 10 -Compress
  return @{
    StatusCode = $statusCode
    StatusText = (Get-StatusText $statusCode)
    ContentType = "application/json; charset=utf-8"
    BodyBytes = [Text.Encoding]::UTF8.GetBytes($json)
    Headers = $extraHeaders
  }
}

function New-TextResponse([int]$statusCode, [string]$contentType, [string]$text, [hashtable]$extraHeaders = @{}) {
  return @{
    StatusCode = $statusCode
    StatusText = (Get-StatusText $statusCode)
    ContentType = $contentType
    BodyBytes = [Text.Encoding]::UTF8.GetBytes($text)
    Headers = $extraHeaders
  }
}

function New-FileResponse([string]$path, [string]$contentType) {
  return @{
    StatusCode = 200
    StatusText = "OK"
    ContentType = $contentType
    BodyBytes = [IO.File]::ReadAllBytes($path)
    Headers = @{}
  }
}

function Get-StatusText([int]$statusCode) {
  switch ($statusCode) {
    200 { "OK" }
    201 { "Created" }
    400 { "Bad Request" }
    401 { "Unauthorized" }
    403 { "Forbidden" }
    404 { "Not Found" }
    405 { "Method Not Allowed" }
    500 { "Internal Server Error" }
    default { "OK" }
  }
}

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".css"  { "text/css; charset=utf-8" }
    ".js"   { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".png"  { "image/png" }
    ".jpg"  { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".gif"  { "image/gif" }
    ".svg"  { "image/svg+xml" }
    ".ico"  { "image/x-icon" }
    default { "application/octet-stream" }
  }
}

function Parse-Cookies([hashtable]$headers) {
  $map = @{}
  $header = $headers["cookie"]
  if ([string]::IsNullOrWhiteSpace($header)) { return $map }
  foreach ($part in ($header -split ";")) {
    $kv = $part.Trim() -split "=", 2
    if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() }
  }
  return $map
}

function Parse-Query([string]$rawPath) {
  $map = @{}
  $parts = $rawPath -split "\?", 2
  if ($parts.Count -lt 2) { return $map }
  foreach ($pair in ($parts[1] -split "&")) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }
    $kv = $pair -split "=", 2
    $k = [System.Uri]::UnescapeDataString($kv[0])
    $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { "" }
    $map[$k] = $v
  }
  return $map
}

function Get-PathOnly([string]$rawPath) {
  return ([System.Uri]::UnescapeDataString(($rawPath -split "\?", 2)[0]))
}

function Read-JsonBody([string]$rawBody) {
  if ([string]::IsNullOrWhiteSpace($rawBody)) { return @{} }
  return ($rawBody | ConvertFrom-Json)
}

function Today { (Get-Date).ToString("yyyy-MM-dd") }
function TimeNow { (Get-Date).ToString("HH:mm:ss") }

function Normalize-Time([string]$timeValue) {
  if ([string]::IsNullOrWhiteSpace($timeValue)) { return "" }
  if ($timeValue.Length -eq 5) { return "$timeValue`:00" }
  return $timeValue
}

function Get-DaysInMonth([string]$monthValue) {
  $parts = $monthValue -split "-"
  $year = [int]$parts[0]
  $month = [int]$parts[1]
  return [DateTime]::DaysInMonth($year, $month)
}

function Get-SessionUser($headers, $db) {
  $sid = (Parse-Cookies $headers)["session_id"]
  if ([string]::IsNullOrWhiteSpace($sid)) { return $null }
  if (-not $Sessions.ContainsKey($sid)) { return $null }
  $uid = $Sessions[$sid]
  return $db.users | Where-Object { $_.id -eq $uid } | Select-Object -First 1
}

function Require-Role($headers, $db, [string]$role) {
  $user = Get-SessionUser $headers $db
  if (-not $user) { return @{ Error = (New-JsonResponse 401 @{ error = "Ban chua dang nhap" }) } }
  if ($user.role -ne $role) { return @{ Error = (New-JsonResponse 403 @{ error = "Khong du quyen" }) } }
  return @{ User = $user }
}

function Get-MappedRecords($db, $rows) {
  return @($rows | Sort-Object date, workerId | ForEach-Object {
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
}

function Handle-Api($request) {
  $db = Load-Db
  $method = $request.Method
  $path = (Get-PathOnly $request.RawPath).ToLowerInvariant()

  if ($method -eq "POST" -and $path -eq "/api/login") {
    $body = Read-JsonBody $request.Body
    $user = $db.users | Where-Object { $_.username -eq [string]$body.username -and $_.password -eq [string]$body.password } | Select-Object -First 1
    if (-not $user) { return (New-JsonResponse 401 @{ error = "Sai tai khoan hoac mat khau" }) }
    $sid = [guid]::NewGuid().ToString("N")
    $Sessions[$sid] = $user.id
    return (New-JsonResponse 200 @{ user = @{ id = $user.id; name = $user.name; role = $user.role; username = $user.username } } @{ "Set-Cookie" = "session_id=$sid; Path=/; HttpOnly; SameSite=Lax" })
  }

  if ($method -eq "POST" -and $path -eq "/api/logout") {
    $sid = (Parse-Cookies $request.Headers)["session_id"]
    if ($sid -and $Sessions.ContainsKey($sid)) { $Sessions.Remove($sid) }
    return (New-JsonResponse 200 @{ ok = $true } @{ "Set-Cookie" = "session_id=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax" })
  }

  if ($method -eq "GET" -and $path -eq "/api/me") {
    $me = Get-SessionUser $request.Headers $db
    if (-not $me) { return (New-JsonResponse 401 @{ error = "Ban chua dang nhap" }) }
    return (New-JsonResponse 200 @{ user = @{ id = $me.id; name = $me.name; role = $me.role; username = $me.username } })
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/checkin") {
    $auth = Require-Role $request.Headers $db "worker"
    if ($auth.Error) { return $auth.Error }
    $me = $auth.User
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec) {
      $rec = [pscustomobject]@{ id = [guid]::NewGuid().ToString("N"); workerId = $me.id; date = $d; checkIn = ""; checkOut = "" }
      $db.records += $rec
    }
    if ($rec.checkIn) { return (New-JsonResponse 400 @{ error = "Ban da check-in hom nay" }) }
    $rec.checkIn = TimeNow
    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true; record = $rec })
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/checkout") {
    $auth = Require-Role $request.Headers $db "worker"
    if ($auth.Error) { return $auth.Error }
    $me = $auth.User
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec -or -not $rec.checkIn) { return (New-JsonResponse 400 @{ error = "Ban chua check-in" }) }
    if ($rec.checkOut) { return (New-JsonResponse 400 @{ error = "Ban da check-out hom nay" }) }
    $rec.checkOut = TimeNow
    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true; record = $rec })
  }

  if ($method -eq "GET" -and $path -eq "/api/my-attendance/today") {
    $auth = Require-Role $request.Headers $db "worker"
    if ($auth.Error) { return $auth.Error }
    $me = $auth.User
    $d = Today
    $rec = $db.records | Where-Object { $_.workerId -eq $me.id -and $_.date -eq $d } | Select-Object -First 1
    if (-not $rec) { $rec = @{ workerId = $me.id; date = $d; checkIn = ""; checkOut = "" } }
    return (New-JsonResponse 200 @{ record = $rec })
  }

  if ($method -eq "GET" -and $path -eq "/api/workers") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $workers = @($db.users | Where-Object { $_.role -eq "worker" } | ForEach-Object { @{ id = $_.id; name = $_.name; username = $_.username } })
    return (New-JsonResponse 200 @{ workers = $workers })
  }

  if ($method -eq "POST" -and $path -eq "/api/workers") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $body = Read-JsonBody $request.Body
    $name = ([string]$body.name).Trim()
    $username = ([string]$body.username).Trim()
    $password = ([string]$body.password).Trim()
    if (-not $name -or -not $username -or -not $password) { return (New-JsonResponse 400 @{ error = "Thieu thong tin" }) }
    $exists = $db.users | Where-Object { $_.username.ToLower() -eq $username.ToLower() } | Select-Object -First 1
    if ($exists) { return (New-JsonResponse 400 @{ error = "Ten dang nhap da ton tai" }) }
    $newUser = [pscustomobject]@{ id = "u-" + [guid]::NewGuid().ToString("N").Substring(0,8); username = $username; password = $password; name = $name; role = "worker" }
    $db.users += $newUser
    Save-Db $db
    return (New-JsonResponse 201 @{ worker = @{ id = $newUser.id; name = $newUser.name; username = $newUser.username } })
  }

  if ($method -eq "POST" -and $path -eq "/api/workers/update") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $body = Read-JsonBody $request.Body
    $worker = $db.users | Where-Object { $_.id -eq [string]$body.id -and $_.role -eq "worker" } | Select-Object -First 1
    if (-not $worker) { return (New-JsonResponse 404 @{ error = "Khong tim thay cong nhan" }) }
    $name = ([string]$body.name).Trim()
    $username = ([string]$body.username).Trim()
    $password = ([string]$body.password).Trim()
    if (-not $name -or -not $username) { return (New-JsonResponse 400 @{ error = "Thieu thong tin" }) }
    $exists = $db.users | Where-Object { $_.id -ne $worker.id -and $_.username.ToLower() -eq $username.ToLower() } | Select-Object -First 1
    if ($exists) { return (New-JsonResponse 400 @{ error = "Ten dang nhap da ton tai" }) }
    $worker.name = $name
    $worker.username = $username
    if ($password) { $worker.password = $password }
    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true })
  }

  if ($method -eq "POST" -and $path -eq "/api/workers/delete") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $body = Read-JsonBody $request.Body
    $workerId = ([string]$body.id).Trim()
    $worker = $db.users | Where-Object { $_.id -eq $workerId -and $_.role -eq "worker" } | Select-Object -First 1
    if (-not $worker) { return (New-JsonResponse 404 @{ error = "Khong tim thay cong nhan" }) }
    $db.users = @($db.users | Where-Object { $_.id -ne $workerId })
    $db.records = @($db.records | Where-Object { $_.workerId -ne $workerId })
    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true })
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/upsert") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $body = Read-JsonBody $request.Body
    $workerId = ([string]$body.workerId).Trim()
    $date = ([string]$body.date).Trim()
    if (-not $workerId -or -not $date) { return (New-JsonResponse 400 @{ error = "Thieu cong nhan hoac ngay" }) }
    $worker = $db.users | Where-Object { $_.id -eq $workerId -and $_.role -eq "worker" } | Select-Object -First 1
    if (-not $worker) { return (New-JsonResponse 404 @{ error = "Khong tim thay cong nhan" }) }

    $checkIn = Normalize-Time ([string]$body.checkIn)
    $checkOut = Normalize-Time ([string]$body.checkOut)
    $recordId = ([string]$body.id).Trim()
    $record = $null

    if ($recordId) {
      $record = $db.records | Where-Object { $_.id -eq $recordId } | Select-Object -First 1
    } else {
      $record = $db.records | Where-Object { $_.workerId -eq $workerId -and $_.date -eq $date } | Select-Object -First 1
    }

    if (-not $record) {
      $record = [pscustomobject]@{
        id = [guid]::NewGuid().ToString("N")
        workerId = $workerId
        date = $date
        checkIn = $checkIn
        checkOut = $checkOut
      }
      $db.records += $record
    } else {
      $record.workerId = $workerId
      $record.date = $date
      $record.checkIn = $checkIn
      $record.checkOut = $checkOut
    }

    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true; record = $record })
  }

  if ($method -eq "POST" -and $path -eq "/api/attendance/delete") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $body = Read-JsonBody $request.Body
    $recordId = ([string]$body.id).Trim()
    if (-not $recordId) { return (New-JsonResponse 400 @{ error = "Thieu ma ban ghi" }) }
    $db.records = @($db.records | Where-Object { $_.id -ne $recordId })
    Save-Db $db
    return (New-JsonResponse 200 @{ ok = $true })
  }

  if ($method -eq "GET" -and $path -eq "/api/stats/today") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $d = Today
    $workers = @($db.users | Where-Object { $_.role -eq "worker" })
    $recs = @($db.records | Where-Object { $_.date -eq $d })
    return (New-JsonResponse 200 @{
      stats = @{
        date = $d
        totalWorkers = $workers.Count
        checkedIn = (@($recs | Where-Object { $_.checkIn })).Count
        checkedOut = (@($recs | Where-Object { $_.checkOut })).Count
      }
    })
  }

  if ($method -eq "GET" -and $path -eq "/api/attendance") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $q = Parse-Query $request.RawPath
    $date = $q["date"]
    $month = $q["month"]
    $workerId = $q["workerId"]
    $rows = @($db.records)
    if ($date) { $rows = @($rows | Where-Object { $_.date -eq $date }) }
    if ($month) { $rows = @($rows | Where-Object { $_.date.StartsWith($month) }) }
    if ($workerId) { $rows = @($rows | Where-Object { $_.workerId -eq $workerId }) }
    return (New-JsonResponse 200 @{ records = (Get-MappedRecords $db $rows) })
  }

  if ($method -eq "GET" -and $path -eq "/api/attendance/export") {
    $auth = Require-Role $request.Headers $db "manager"
    if ($auth.Error) { return $auth.Error }
    $q = Parse-Query $request.RawPath
    $date = $q["date"]
    $month = $q["month"]
    $workerId = $q["workerId"]
    $rows = @($db.records)
    if ($date) { $rows = @($rows | Where-Object { $_.date -eq $date }) }
    if ($month) { $rows = @($rows | Where-Object { $_.date.StartsWith($month) }) }
    if ($workerId) { $rows = @($rows | Where-Object { $_.workerId -eq $workerId }) }

    if ($month) {
      $daysInMonth = Get-DaysInMonth $month
      $workers = @($db.users | Where-Object { $_.role -eq "worker" })
      if ($workerId) { $workers = @($workers | Where-Object { $_.id -eq $workerId }) }

      $header = @("CongNhan", "TaiKhoan")
      $header += @(1..$daysInMonth | ForEach-Object { "Ngay_$('{0:d2}' -f $_)" })
      $header += @("TongCong", "ChuaRa", "Vang")
      $lines = @($header -join ",")

      foreach ($worker in $workers) {
        $workerRows = @($rows | Where-Object { $_.workerId -eq $worker.id })
        $recordsByDay = @{}
        foreach ($record in $workerRows) {
          $recordsByDay[[int]($record.date.Substring(8, 2))] = $record
        }

        $presentCount = 0
        $incompleteCount = 0
        $absentCount = 0
        $values = @('"' + $worker.name.Replace('"', '""') + '"', '"' + $worker.username.Replace('"', '""') + '"')

        foreach ($day in 1..$daysInMonth) {
          if ($recordsByDay.ContainsKey($day)) {
            $record = $recordsByDay[$day]
            if ($record.checkIn -and $record.checkOut) {
              $presentCount++
              $values += '"P"'
            } elseif ($record.checkIn) {
              $incompleteCount++
              $values += '"V"'
            } else {
              $absentCount++
              $values += '"-"'
            }
          } else {
            $absentCount++
            $values += '"-"'
          }
        }

        $values += @('"' + $presentCount + '"', '"' + $incompleteCount + '"', '"' + $absentCount + '"')
        $lines += ($values -join ",")
      }

      $csv = $lines -join "`n"
      return (New-TextResponse 200 "text/csv; charset=utf-8" $csv @{ "Content-Disposition" = "attachment; filename=bang-cong-thang-$month.csv" })
    }

    $lines = @("Ngay,CongNhan,TaiKhoan,CheckIn,CheckOut,TrangThai")
    foreach ($r in (Get-MappedRecords $db $rows)) {
      $vals = @($r.date, $r.workerName, $r.workerUsername, $r.checkIn, $r.checkOut, $r.status) | ForEach-Object { '"' + (($_ -as [string]).Replace('"','""')) + '"' }
      $lines += ($vals -join ",")
    }
    $csv = $lines -join "`n"
    return (New-TextResponse 200 "text/csv; charset=utf-8" $csv @{ "Content-Disposition" = "attachment; filename=cham-cong-$(Today).csv" })
  }

  return (New-JsonResponse 404 @{ error = "Khong tim thay API" })
}

function Handle-Static($request) {
  $path = Get-PathOnly $request.RawPath
  if ($path -eq "/") { $path = "/index.html" }

  $relative = $path.TrimStart("/").Replace("/", [IO.Path]::DirectorySeparatorChar)
  $fullPath = [IO.Path]::GetFullPath((Join-Path $ScriptDir $relative))

  if (-not $fullPath.StartsWith($ScriptDir, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    return (New-TextResponse 404 "text/plain; charset=utf-8" "Not Found")
  }

  return (New-FileResponse $fullPath (Get-ContentType $fullPath))
}

function Write-HttpResponse($stream, $response) {
  $headers = [System.Collections.Generic.List[string]]::new()
  $headers.Add("HTTP/1.1 $($response.StatusCode) $($response.StatusText)")
  $headers.Add("Content-Type: $($response.ContentType)")
  $headers.Add("Content-Length: $($response.BodyBytes.Length)")
  $headers.Add("Connection: close")

  foreach ($key in $response.Headers.Keys) {
    $headers.Add("$key`: $($response.Headers[$key])")
  }

  $headerText = ($headers -join "`r`n") + "`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($headerText)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($response.BodyBytes.Length -gt 0) { $stream.Write($response.BodyBytes, 0, $response.BodyBytes.Length) }
}

function Read-HttpRequest($client) {
  $stream = $client.GetStream()
  $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
  $requestLine = $reader.ReadLine()
  if ([string]::IsNullOrWhiteSpace($requestLine)) { return $null }

  $parts = $requestLine.Split(" ")
  if ($parts.Length -lt 2) { return $null }

  $headers = @{}
  while ($true) {
    $line = $reader.ReadLine()
    if ($null -eq $line -or $line -eq "") { break }
    $kv = $line -split ":", 2
    if ($kv.Count -eq 2) { $headers[$kv[0].Trim().ToLowerInvariant()] = $kv[1].Trim() }
  }

  $body = ""
  $contentLength = 0
  if ($headers.ContainsKey("content-length")) { [int]::TryParse($headers["content-length"], [ref]$contentLength) | Out-Null }

  if ($contentLength -gt 0) {
    $buffer = New-Object char[] $contentLength
    $offset = 0
    while ($offset -lt $contentLength) {
      $read = $reader.Read($buffer, $offset, $contentLength - $offset)
      if ($read -le 0) { break }
      $offset += $read
    }
    if ($offset -gt 0) { $body = -join $buffer[0..($offset - 1)] }
  }

  return @{
    Method = $parts[0].ToUpperInvariant()
    RawPath = $parts[1]
    Headers = $headers
    Body = $body
    Stream = $stream
  }
}

$ipAddress = if ($BindAddress -eq "0.0.0.0") { [System.Net.IPAddress]::Any } else { [System.Net.IPAddress]::Parse($BindAddress) }
$listener = [System.Net.Sockets.TcpListener]::new($ipAddress, $Port)
$listener.Start()

Write-Host "Server dang chay tai http://localhost:$Port"
if ($BindAddress -eq "0.0.0.0") {
  Write-Host "Server dang mo cho mang noi bo tren cong $Port"
} else {
  Write-Host "Server dang bind tai http://${BindAddress}:$Port"
}
Write-Host "Nhan Ctrl+C de dung"

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $request = Read-HttpRequest $client
    if ($null -eq $request) {
      $client.Close()
      continue
    }

    if ($request.Method -ne "GET" -and $request.Method -ne "POST" -and $request.Method -ne "HEAD") {
      Write-HttpResponse $request.Stream (New-TextResponse 405 "text/plain; charset=utf-8" "Method Not Allowed")
      $client.Close()
      continue
    }

    $response = if ((Get-PathOnly $request.RawPath).ToLowerInvariant().StartsWith("/api/")) { Handle-Api $request } else { Handle-Static $request }
    if ($request.Method -eq "HEAD") { $response.BodyBytes = @() }
    Write-HttpResponse $request.Stream $response
  }
  catch {
    try {
      Write-HttpResponse ($client.GetStream()) (New-TextResponse 500 "text/plain; charset=utf-8" "Internal Server Error")
    } catch {}
  }
  finally {
    $client.Close()
  }
}

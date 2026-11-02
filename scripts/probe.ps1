# 장애 재현(E08) 동안 사용자 쪽 응답을 기록한다. 1초마다 URL마다 curl.exe를 하나씩 띄우고,
# 응답을 기다리지 않고 다음 요청을 보낸다(DB 장애처럼 응답이 30초 넘게 걸려도 간격이 밀리지 않게).
# 결과는 요청 시작 시각 기준 CSV 한 줄씩: 시각(KST), URL, 상태 코드(연결 실패·시간 초과는 000), 응답 시간(초), curl 종료 코드,
# ok(1 = 상태 200이고 curl 종료 코드 0. 헤더 200을 받은 뒤 본문 수신 중 시간 초과된 요청은 0).
# 멈출 때는 Ctrl+C. 이미 띄운 요청의 결과는 그 전까지 끝난 것만 남는다.
#
# 예) powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe.ps1 -Url https://3tier.link/posts
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe.ps1 -Url https://3tier.link/posts,https://3tier.link/actuator/health,https://3tier.link/actuator/health/liveness -IntervalSeconds 2

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Url,
    [double]$IntervalSeconds = 1,
    # curl --max-time. ALB 유휴 시간 60초보다 짧고, Hikari 연결 대기 30초보다 길게
    [int]$MaxTimeSeconds = 40,
    # 기본은 레포의 local/captures/E8/probe-<시작 시각>.csv (local/은 추적하지 않는다)
    [string]$OutFile
)

$ErrorActionPreference = "Stop"

# -File로 실행하면 쉼표 목록이 문자열 하나로 들어온다. 직접 나눈다
$Url = @($Url | ForEach-Object { $_.Split(",") } | Where-Object { $_ })

if (-not $OutFile) {
    $dir = Join-Path $PSScriptRoot "..\local\captures\E8"
    $OutFile = Join-Path $dir ("probe-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
}
$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$OutFile = [System.IO.Path]::GetFullPath($OutFile)

# PowerShell 5.1의 Out-File은 BOM을 붙이므로 .NET으로 UTF-8(BOM 없음)을 쓴다
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutFile, "time_kst,url,status,time_s,curl_exit,ok`n", $utf8)
Write-Host "probe -> $OutFile (Ctrl+C to stop)"

$pending = New-Object System.Collections.ArrayList

function Write-Finished {
    foreach ($p in @($pending)) {
        if (-not $p.Process.HasExited) { continue }
        $out = $p.Process.StandardOutput.ReadToEnd().Trim()
        $parts = $out.Split(",")
        $status = if ($parts.Count -ge 1 -and $parts[0]) { $parts[0] } else { "000" }
        $time = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        $exit = $p.Process.ExitCode
        $ok = if ($status -eq "200" -and $exit -eq 0) { 1 } else { 0 }
        $line = "{0},{1},{2},{3},{4},{5}" -f $p.Start, $p.Url, $status, $time, $exit, $ok
        [System.IO.File]::AppendAllText($OutFile, $line + "`n", $utf8)
        Write-Host $line
        $p.Process.Dispose()
        [void]$pending.Remove($p)
    }
}

try {
    while ($true) {
        $tick = Get-Date
        foreach ($u in $Url) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "curl.exe"
            # -s 진행 표시 없음, -o NUL 본문 버림, -w 상태 코드와 전체 시간만 출력
            $psi.Arguments = "-s -o NUL --max-time $MaxTimeSeconds -w ""%{http_code},%{time_total}"" ""$u"""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            [void]$pending.Add([pscustomobject]@{
                    Process = $proc
                    Url     = $u
                    Start   = $tick.ToString("yyyy-MM-ddTHH:mm:ss.fff")
                })
        }
        Write-Finished
        $sleepMs = [int]($IntervalSeconds * 1000 - ((Get-Date) - $tick).TotalMilliseconds)
        if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
    }
}
finally {
    Write-Finished
}

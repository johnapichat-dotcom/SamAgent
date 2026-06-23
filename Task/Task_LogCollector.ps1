param([string]$ZipName = "SAM_Logs_Archive.zip")
$LogFile = "C:\IT_Support\SAM_Log.txt"
$ZipPath = "C:\IT_Support\$ZipName"
$TempLogDir = "$env:TEMP\SAM_Logs_Extract"
try {
    if (Test-Path $TempLogDir) { Remove-Item -Path $TempLogDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $TempLogDir | Out-Null
    wevtutil epl System "$TempLogDir\SystemLog.evtx" /q:"*[System[TimeCreated[timediff(@SystemTime) <= 604800000]]]"
    wevtutil epl Application "$TempLogDir\AppLog.evtx" /q:"*[System[TimeCreated[timediff(@SystemTime) <= 604800000]]]"
    Copy-Item -Path $LogFile -Destination $TempLogDir -ErrorAction SilentlyContinue
    Compress-Archive -Path "$TempLogDir\*" -DestinationPath $ZipPath -Force
    Remove-Item -Path $TempLogDir -Recurse -Force
    "$(Get-Date) - [Task_LogCollector] Zipped to $ZipPath" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

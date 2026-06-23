param(
    [string]$TargetApp
)

$LogFile = "C:\IT_Support\SAM_Log.txt"

Function Write-SAMLog {
    param([string]$Message)
    $Timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $LogEntry = "$Timestamp - [UninstallTask] $Message"
    Add-Content -Path $LogFile -Value $LogEntry
}

if (-not $TargetApp) { 
    Write-SAMLog "Failed: No target application specified in Payload."
    exit 
}

Write-SAMLog "Initiated search for target: '$TargetApp'"

$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$App = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $TargetApp } | Select-Object -First 1

if ($App -and $App.UninstallString) {
    $AppName = $App.DisplayName
    $UninstStr = $App.UninstallString
    
    Write-SAMLog "Match found: '$AppName'. Base String: $UninstStr"
    
    # ---------------------------------------------------------
    # [NEW LOGIC] PRE-KILL PROCESS & SERVICE (ปลดล็อกไฟล์ก่อนลบ)
    # ---------------------------------------------------------
    Write-SAMLog "Attempting to terminate running processes and services..."
    
    # 1. ปิด Process ทั้งหมดที่มีชื่อตรงกับ Target (เช่น HopToDesk.exe)
    Get-Process | Where-Object { $_.Name -match $TargetApp -or $_.Description -match $TargetApp } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # 2. ปิด Service ทั้งหมดที่มีชื่อเกี่ยวข้อง
    Get-Service | Where-Object { $_.Name -match $TargetApp -or $_.DisplayName -match $TargetApp } | Stop-Service -Force -ErrorAction SilentlyContinue
    
    # หน่วงเวลา 3 วินาทีให้ Windows คืนทรัพยากร (Release File Lock)
    Start-Sleep -Seconds 3
    # ---------------------------------------------------------

    $Exe = ""
    if ($UninstStr -match '(?i)(.*?\.exe)') {
        $Exe = $matches[1] -replace '"', ''
    } else {
        $Exe = $UninstStr.Split(' ')[0] -replace '"', ''
    }
    
    if ($UninstStr -match "msiexec") {
        $Args = "/x $($App.PSChildName) /qn /norestart"
        $Exe = "msiexec.exe"
    } elseif ($Exe -match "unins000.exe" -or $Exe -match "setup.exe") {
        $Args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    } else {
        $Args = "/S"
    }

    Write-SAMLog "Executing removal: `"$Exe`" $Args"

    try {
        $Process = Start-Process -FilePath $Exe -ArgumentList $Args -WindowStyle Hidden -Wait -PassThru
        Write-SAMLog "Process finished. Exit Code: $($Process.ExitCode)"
    } catch {
        Write-SAMLog "Execution Error: $($_.Exception.Message)"
    }
} else {
    Write-SAMLog "Target '$TargetApp' not found in system Registry. Process aborted."
}

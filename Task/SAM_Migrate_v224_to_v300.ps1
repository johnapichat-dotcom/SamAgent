# ==============================================================================
# S.A.M. MIGRATION SCRIPT
# FROM    : v2.2.4 (Single-file SAM_Agent.ps1 / JARVIS legacy)
# TO      : v3.0.0 (SAM_Scheduler + SAM_Agent + SAM_Update)
# FILE    : SAM_Migrate_v224_to_v300.ps1
#
# วิธีใช้:
#   [A] ส่งผ่าน C2 Command ใน Supabase:
#       RUN_TASK:SAM_Migrate_v224_to_v300.ps1
#
#   [B] รันตรงบนเครื่อง (Admin):
#       powershell -ExecutionPolicy Bypass -File "SAM_Migrate_v224_to_v300.ps1"
#
# Script นี้จะ:
#   1. ตรวจสอบว่าเป็น v2.2.4 จริงหรือไม่
#   2. Backup ไฟล์และ config เดิมทั้งหมด
#   3. ดาวน์โหลด v3.0.0 ทั้ง 3 ไฟล์
#   4. ย้าย Config เดิมมาใช้กับระบบใหม่
#   5. ลบ Scheduled Task เก่า / ลง Task ใหม่ผ่าน SAM_Scheduler
#   6. รัน SAM_Agent ครั้งแรก (ForceFullSync)
#   7. ลบ Legacy files ที่ไม่ใช้แล้ว
# ==============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ==========================================
# CONSTANTS
# ==========================================
$MIG_VERSION   = "1.0.0"
$WorkDir       = "C:\IT_Support"
$BackupDir     = "$WorkDir\_Backup_v224_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$LogFile       = "$WorkDir\SAM_Log.txt"
$MigLogFile    = "$WorkDir\SAM_MigrationLog.txt"
$ConfigFile    = "$WorkDir\SystemConfig.json"
$StateFile     = "$WorkDir\LastState.json"

# Remote URLs — ชี้ไปที่ไฟล์ v3.0.0 บน GitHub
$BaseRawUrl    = "https://raw.githubusercontent.com/johnapichat-dotcom/SamAgent/main/Agent"
$AgentUrl      = "$BaseRawUrl/SAM_Agent.txt"
$SchedulerUrl  = "$BaseRawUrl/SAM_Scheduler.txt"
$UpdateUrl     = "$BaseRawUrl/SAM_Update.txt"

# Local target paths
$AgentScript     = "$WorkDir\SAM_Agent.ps1"
$SchedulerScript = "$WorkDir\SAM_Scheduler.ps1"
$UpdateScript    = "$WorkDir\SAM_Update.ps1"

# Legacy identifiers
$LegacyTaskNames = @(
    "SAM_Agent_DailySync",   # v2.2.4 task name
    "SAM_Smart_Sync",        # older legacy
    "JARVIS_Smart_Sync"      # oldest legacy
)

# ==========================================
# LOGGING
# ==========================================
function Write-MigLog {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Timestamp [$Level] [Migration] $Message"
    try {
        Add-Content -Path $MigLogFile -Value $Line -Encoding UTF8 -ErrorAction SilentlyContinue
        Add-Content -Path $LogFile    -Value $Line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
    $Color = switch ($Level) {
        "ERROR" { "Red" }; "WARN" { "Yellow" }; "OK" { "Green" }; default { "Cyan" }
    }
    Write-Host $Line -ForegroundColor $Color
}

function Write-MigSection {
    param([string]$Title)
    $Sep = "=" * 60
    Write-MigLog $Sep
    Write-MigLog "  $Title"
    Write-MigLog $Sep
}

# ==========================================
# STEP 0: PRIVILEGE CHECK
# ==========================================
Write-MigSection "S.A.M. MIGRATION v$MIG_VERSION  (v2.2.4 → v3.0.0)"

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-MigLog "Not running as Administrator. Re-launching elevated..." -Level "WARN"
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit 0
}
Write-MigLog "Running as Administrator. OK." -Level "OK"

# ==========================================
# STEP 1: ตรวจว่าเป็น v2.2.4 จริงหรือเปล่า
# ==========================================
Write-MigSection "STEP 1: Verify Current Version"

$IsLegacy = $false
$LegacyAgentPath = "$WorkDir\SAM_Agent.ps1"

# วิธีตรวจ: หา string "2.2.4" หรือ "JARVIS" ใน SAM_Agent.ps1 ปัจจุบัน
if (Test-Path $LegacyAgentPath) {
    $AgentContent = Get-Content $LegacyAgentPath -Raw -ErrorAction SilentlyContinue
    if ($AgentContent -match "2\.2\.4|JARVIS PROTOCOL|SAM_Agent_DailySync") {
        $IsLegacy = $true
        Write-MigLog "Detected v2.2.4 / JARVIS legacy system. Migration required." -Level "OK"
    } elseif ($AgentContent -match "3\.0\.0") {
        Write-MigLog "System already on v3.0.0. Migration not needed." -Level "OK"
        exit 0
    } else {
        Write-MigLog "Unknown version detected. Proceeding with migration anyway." -Level "WARN"
        $IsLegacy = $true
    }
} else {
    Write-MigLog "SAM_Agent.ps1 not found at $LegacyAgentPath" -Level "WARN"
    Write-MigLog "Assuming fresh install context. Will deploy v3.0.0." -Level "WARN"
    $IsLegacy = $false
}

# ตรวจ Legacy Scheduled Tasks
$LegacyTaskFound = @()
foreach ($TName in $LegacyTaskNames) {
    if (Get-ScheduledTask -TaskName $TName -ErrorAction SilentlyContinue) {
        $LegacyTaskFound += $TName
        Write-MigLog "Legacy task found: $TName"
    }
}

# ==========================================
# STEP 2: BACKUP ไฟล์และ State เดิม
# ==========================================
Write-MigSection "STEP 2: Backup Existing Files"

try {
    # ปลด lock โฟลเดอร์ก่อน backup
    cmd.exe /c "attrib -h -s -r `"$WorkDir`" /s /d >nul 2>&1"

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Write-MigLog "Backup directory: $BackupDir"

    # ไฟล์ที่ backup
    $FilesToBackup = @(
        "$WorkDir\SAM_Agent.ps1",
        "$WorkDir\SystemConfig.json",
        "$WorkDir\LastState.json",
        "$WorkDir\SAM_Log.txt",
        "$WorkDir\SAM_ForceSync.bat",
        "$WorkDir\SAM_DeepScan.bat",
        "$WorkDir\SAM_Uninstall.bat",
        "$WorkDir\Uninstall.ps1",
        "$WorkDir\SAM_ForceSync.ps1"
    )

    $BackedUp = 0
    foreach ($F in $FilesToBackup) {
        if (Test-Path $F) {
            $DestName = Split-Path $F -Leaf
            Copy-Item $F "$BackupDir\$DestName" -Force -ErrorAction SilentlyContinue
            Write-MigLog "Backed up: $DestName"
            $BackedUp++
        }
    }

    # Backup HTML reports ทั้งหมด
    Get-ChildItem $WorkDir -Filter "*.html" | ForEach-Object {
        Copy-Item $_.FullName "$BackupDir\$($_.Name)" -Force -ErrorAction SilentlyContinue
    }

    Write-MigLog "Backup complete. $BackedUp files saved to: $BackupDir" -Level "OK"
} catch {
    Write-MigLog "Backup error: $($_.Exception.Message)" -Level "ERROR"
    Write-MigLog "Continuing migration despite backup error..." -Level "WARN"
}

# ==========================================
# STEP 3: อ่าน Config เดิม (SystemConfig.json)
# ==========================================
Write-MigSection "STEP 3: Preserve Configuration"

$ExistingConfig = $null
if (Test-Path $ConfigFile) {
    try {
        $ExistingConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        Write-MigLog "Existing config loaded:"
        Write-MigLog "  BU       = $($ExistingConfig.BU)"
        Write-MigLog "  BranchID = $($ExistingConfig.BranchID)"
        Write-MigLog "  Province = $($ExistingConfig.Province)"
    } catch {
        Write-MigLog "Config file corrupt: $($_.Exception.Message)" -Level "WARN"
        $ExistingConfig = $null
    }
} else {
    Write-MigLog "No existing config found. Will prompt on first run." -Level "WARN"
}

# ==========================================
# STEP 4: หยุด Legacy Scheduled Tasks
# ==========================================
Write-MigSection "STEP 4: Remove Legacy Scheduled Tasks"

foreach ($TName in $LegacyTaskNames) {
    try {
        $T = Get-ScheduledTask -TaskName $TName -ErrorAction SilentlyContinue
        if ($T) {
            # หยุด task ที่กำลังรันอยู่ก่อน
            if ($T.State -eq "Running") {
                Stop-ScheduledTask -TaskName $TName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            }
            schtasks /delete /tn $TName /f 2>$null | Out-Null
            Write-MigLog "Removed legacy task: $TName" -Level "OK"
        }
    } catch {
        Write-MigLog "Could not remove task $TName : $($_.Exception.Message)" -Level "WARN"
    }
}

# ==========================================
# STEP 5: ดาวน์โหลด v3.0.0 Files
# ==========================================
Write-MigSection "STEP 5: Download v3.0.0 Files"

# Network check
$NetOK = $false
$NetRetry = 0
while (-not $NetOK -and $NetRetry -lt 6) {
    try {
        $R = Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($R.Content -match "Microsoft Connect Test") { $NetOK = $true }
    } catch { $NetRetry++; Start-Sleep -Seconds 30 }
}

if (-not $NetOK) {
    Write-MigLog "No internet after 6 retries. Migration aborted." -Level "ERROR"
    Write-MigLog "ROLLBACK: Restoring original files from backup..."
    # Rollback: คืนไฟล์เดิม
    foreach ($F in (Get-ChildItem $BackupDir)) {
        Copy-Item $F.FullName "$WorkDir\$($F.Name)" -Force -ErrorAction SilentlyContinue
    }
    # คืน legacy tasks
    $OldAgent = "$WorkDir\SAM_Agent.ps1"
    if (Test-Path $OldAgent) {
        try {
            $Action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$OldAgent`" -Silent"
            $Trigger  = @(New-ScheduledTaskTrigger -AtStartup, (New-ScheduledTaskTrigger -Once -At "8:00AM" -RepetitionInterval (New-TimeSpan -Hours 2)))
            $Settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -StartWhenAvailable -AllowStartIfOnBatteries
            Register-ScheduledTask -TaskName "SAM_Agent_DailySync" -Action $Action -Trigger $Trigger -Settings $Settings -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force | Out-Null
            Write-MigLog "Rollback: Legacy task restored." -Level "WARN"
        } catch { Write-MigLog "Rollback task failed: $($_.Exception.Message)" -Level "ERROR" }
    }
    exit 1
}
Write-MigLog "Network OK." -Level "OK"

# Helper function: download with validation
function Download-V3File {
    param([string]$Url, [string]$OutPath, [string]$Label)
    $TmpPath = "$env:TEMP\SAM_mig_$([System.IO.Path]::GetRandomFileName()).ps1"
    $MaxAttempts = 3
    for ($A = 1; $A -le $MaxAttempts; $A++) {
        try {
            Write-MigLog "Downloading $Label (attempt $A/$MaxAttempts)..."
            Invoke-WebRequest -Uri $Url -OutFile $TmpPath -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop

            # Validate: ต้องมีขนาด > 1KB และมี SAM signature
            $Size    = (Get-Item $TmpPath -ErrorAction Stop).Length
            $Content = Get-Content $TmpPath -Raw -ErrorAction Stop
            if ($Size -lt 1024) { throw "File too small ($Size bytes)" }
            if ($Content -notmatch "(?i)(S\.A\.M\.|SAM_VERSION|function\s+\w)") { throw "File failed signature check" }

            Move-Item $TmpPath $OutPath -Force -ErrorAction Stop
            Write-MigLog "$Label downloaded OK ($([math]::Round($Size/1KB,1)) KB)" -Level "OK"
            return $true
        } catch {
            Write-MigLog "$Label download attempt $A failed: $($_.Exception.Message)" -Level "WARN"
            Remove-Item $TmpPath -Force -ErrorAction SilentlyContinue
            if ($A -lt $MaxAttempts) { Start-Sleep -Seconds 15 }
        }
    }
    Write-MigLog "$Label download FAILED after $MaxAttempts attempts." -Level "ERROR"
    return $false
}

# ดาวน์โหลดทีละไฟล์
$DLResults = @{}
$DLResults["SAM_Scheduler"] = Download-V3File -Url $SchedulerUrl -OutPath $SchedulerScript -Label "SAM_Scheduler.ps1"
$DLResults["SAM_Agent"]     = Download-V3File -Url $AgentUrl     -OutPath $AgentScript     -Label "SAM_Agent.ps1"
$DLResults["SAM_Update"]    = Download-V3File -Url $UpdateUrl    -OutPath $UpdateScript    -Label "SAM_Update.ps1"

$FailedDL = ($DLResults.Values | Where-Object { $_ -eq $false }).Count
if ($FailedDL -gt 0) {
    Write-MigLog "$FailedDL file(s) failed to download." -Level "ERROR"
    # ถ้า Scheduler ไม่ได้ หรือ Agent ไม่ได้ → Rollback
    if (-not $DLResults["SAM_Scheduler"] -or -not $DLResults["SAM_Agent"]) {
        Write-MigLog "Critical files missing. Rolling back..." -Level "ERROR"
        foreach ($F in (Get-ChildItem $BackupDir -ErrorAction SilentlyContinue)) {
            Copy-Item $F.FullName "$WorkDir\$($F.Name)" -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
    Write-MigLog "Non-critical file missing. Continuing..." -Level "WARN"
}

# ==========================================
# STEP 6: ตรวจสอบ Config — ถ้ามีอยู่แล้วให้คืนค่า
# ==========================================
Write-MigSection "STEP 6: Restore Configuration"

if ($ExistingConfig) {
    # Config format ของ v3.0.0 เหมือนกับ v2.2.4 (BU, BranchID, Province)
    # ไม่ต้องแปลงอะไร — แค่ตรวจว่า field ครบ
    $V3Config = @{
        BU       = if ($ExistingConfig.BU)       { $ExistingConfig.BU }       else { "Unknown" }
        BranchID = if ($ExistingConfig.BranchID) { $ExistingConfig.BranchID } else { "Unknown" }
        Province = if ($ExistingConfig.Province) { $ExistingConfig.Province } else { "N/A" }
    }
    try {
        $V3Config | ConvertTo-Json | Out-File $ConfigFile -Encoding UTF8 -Force
        Write-MigLog "Config preserved: BU=$($V3Config.BU) | Branch=$($V3Config.BranchID) | Prov=$($V3Config.Province)" -Level "OK"
    } catch {
        Write-MigLog "Failed to write config: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    Write-MigLog "No config to restore. Setup GUI will appear on next Agent run." -Level "WARN"
}

# ล้าง State เดิม — บังคับ FullSync ในรอบแรก
if (Test-Path $StateFile) {
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    Write-MigLog "Old state cleared → will trigger FullSync on first run."
}

# ==========================================
# STEP 7: ติดตั้ง v3.0.0 Scheduled Tasks
# ==========================================
Write-MigSection "STEP 7: Install v3.0.0 Scheduled Tasks"

try {
    Write-MigLog "Running SAM_Scheduler -Setup ..."
    $ProcArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SchedulerScript`" -Setup"
    $Proc = Start-Process powershell.exe -ArgumentList $ProcArgs -WindowStyle Hidden -Wait -PassThru
    $ExitCode = $Proc.ExitCode
    Write-MigLog "SAM_Scheduler -Setup completed. ExitCode: $ExitCode" -Level $(if($ExitCode -eq 0){"OK"}else{"WARN"})
} catch {
    Write-MigLog "Scheduler setup failed: $($_.Exception.Message)" -Level "ERROR"
}

# ตรวจว่า Task ถูกสร้างจริง
Start-Sleep -Seconds 3
$NewTasks = @("SAM_Agent_Sync","SAM_C2_Poll","SAM_FullSync_Daily","SAM_Update_Check","SAM_LogRotate")
$MissingTasks = @()
foreach ($TN in $NewTasks) {
    if (Get-ScheduledTask -TaskName $TN -ErrorAction SilentlyContinue) {
        Write-MigLog "Task verified: $TN" -Level "OK"
    } else {
        Write-MigLog "Task NOT found after setup: $TN" -Level "WARN"
        $MissingTasks += $TN
    }
}

# ==========================================
# STEP 8: รัน SAM_Agent ครั้งแรก (ForceFullSync)
# ==========================================
Write-MigSection "STEP 8: Initial Full Sync"

try {
    Write-MigLog "Launching SAM_Agent -ForceFullSync ..."
    $AgentArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$AgentScript`" -ForceFullSync"
    Start-Process powershell.exe -ArgumentList $AgentArgs -WindowStyle Hidden
    Write-MigLog "SAM_Agent launched in background." -Level "OK"
} catch {
    Write-MigLog "Failed to launch SAM_Agent: $($_.Exception.Message)" -Level "ERROR"
}

# ==========================================
# STEP 9: ลบ Legacy Files ที่ไม่ใช้แล้ว
# ==========================================
Write-MigSection "STEP 9: Cleanup Legacy Files"

$LegacyFiles = @(
    "$WorkDir\Uninstall.ps1",
    "$WorkDir\SAM_ForceSync.ps1",
    "$WorkDir\SAM_Agent.ps1.bak"   # backup อัตโนมัติจาก updater เก่า
)

foreach ($F in $LegacyFiles) {
    if (Test-Path $F) {
        try {
            Remove-Item $F -Force -ErrorAction Stop
            Write-MigLog "Removed legacy file: $(Split-Path $F -Leaf)"
        } catch {
            Write-MigLog "Could not remove $F : $($_.Exception.Message)" -Level "WARN"
        }
    }
}

# ==========================================
# STEP 10: สรุปผล Migration
# ==========================================
Write-MigSection "MIGRATION SUMMARY"

$AllOK = ($MissingTasks.Count -eq 0) -and ($FailedDL -eq 0)
$Status = if ($AllOK) { "SUCCESS" } else { "PARTIAL" }

Write-MigLog "Migration Status    : $Status"
Write-MigLog "Files downloaded    : $($DLResults.Values | Where-Object { $_ }).Count / $($DLResults.Count)"
Write-MigLog "Tasks installed     : $($NewTasks.Count - $MissingTasks.Count) / $($NewTasks.Count)"
Write-MigLog "Config preserved    : $(if ($ExistingConfig) { 'YES' } else { 'NO (fresh setup on next run)' })"
Write-MigLog "Backup location     : $BackupDir"
Write-MigLog "Legacy tasks removed: $($LegacyTaskNames.Count - (($LegacyTaskNames | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue }).Count))"
Write-MigLog ""

if ($AllOK) {
    Write-MigLog "✅  Migration v2.2.4 → v3.0.0 completed successfully." -Level "OK"
    Write-MigLog "    SAM_Agent is running FullSync in the background."
    Write-MigLog "    SAM_Update will check for latest files at 07:00 tomorrow."
} else {
    Write-MigLog "⚠️  Migration completed with warnings." -Level "WARN"
    if ($MissingTasks.Count -gt 0) {
        Write-MigLog "    Missing tasks: $($MissingTasks -join ', ')" -Level "WARN"
        Write-MigLog "    → Run SAM_Scheduler.ps1 -Setup manually to fix." -Level "WARN"
    }
    if ($FailedDL -gt 0) {
        Write-MigLog "    Some files failed to download." -Level "WARN"
        Write-MigLog "    → SAM_Update.ps1 will self-heal at 07:00 tomorrow." -Level "WARN"
    }
}

Write-MigLog ""
Write-MigLog "Migration log saved: $MigLogFile"
Write-MigLog $("=" * 60)

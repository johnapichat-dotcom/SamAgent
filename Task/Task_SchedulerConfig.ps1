<#
.SYNOPSIS
    SAM Task — Scheduler Configuration Manager
    รับ parameters จาก C2 แก้ไข Scheduled Tasks ของ SAM และรายงานผลกลับ

.PARAMETER Action
    LIST    = แสดงค่าปัจจุบันทั้งหมด (default)
    SET     = ตั้งค่า interval ของ task ที่ระบุ
    ENABLE  = เปิด task
    DISABLE = ปิด task
    RESET   = reset กลับค่า default

.PARAMETER TaskName
    ชื่อ task: AgentSync | C2PollDay | C2PollNight | FullSync | UpdateCheck | LogRotate

.PARAMETER IntervalMinutes
    ระยะเวลา interval (นาที) — ใช้กับ Action=SET

.EXAMPLE
    .\Task_SchedulerConfig.ps1 -Action LIST
    .\Task_SchedulerConfig.ps1 -Action SET -TaskName C2PollDay -IntervalMinutes 30
    .\Task_SchedulerConfig.ps1 -Action DISABLE -TaskName C2PollNight
    .\Task_SchedulerConfig.ps1 -Action RESET
#>

param(
    [ValidateSet('LIST','SET','ENABLE','DISABLE','RESET')]
    [string]$Action = 'LIST',

    [ValidateSet('AgentSync','C2PollDay','C2PollNight','FullSync','UpdateCheck','LogRotate','')]
    [string]$TaskName = '',

    [int]$IntervalMinutes = 0
)

# ── Config ────────────────────────────────────────────────────
$SAM_TASKS = @{
    AgentSync    = @{ Name='SAM_Agent_Sync';      Default=240;  Min=30;  Max=1440; Unit='min'; Desc='Agent Sync' }
    C2PollDay    = @{ Name='SAM_C2_Poll_Day';     Default=40;   Min=5;   Max=120;  Unit='min'; Desc='C2 Poll (กลางวัน)' }
    C2PollNight  = @{ Name='SAM_C2_Poll_Night';   Default=80;   Min=10;  Max=240;  Unit='min'; Desc='C2 Poll (กลางคืน)' }
    FullSync     = @{ Name='SAM_FullSync_Weekly'; Default=10080;Min=1440;Max=20160;Unit='min'; Desc='Full Sync (รายสัปดาห์)' }
    UpdateCheck  = @{ Name='SAM_Update_Check';    Default=1440; Min=360; Max=10080;Unit='min'; Desc='Update Check' }
    LogRotate    = @{ Name='SAM_LogRotate';       Default=1440; Min=360; Max=10080;Unit='min'; Desc='Log Rotate' }
}

$Results = [System.Collections.ArrayList]::new()
$Errors  = [System.Collections.ArrayList]::new()

# ── Helper: Get Task Info ─────────────────────────────────────
function Get-SAMTaskInfo {
    param([string]$TaskName)
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue

        # ดึง interval จาก trigger
        $interval = 'N/A'
        foreach ($trigger in $task.Triggers) {
            if ($trigger.RepetitionInterval) {
                $ts = [System.Xml.XmlConvert]::ToTimeSpan($trigger.RepetitionInterval)
                $interval = [int]$ts.TotalMinutes
                break
            }
        }

        return @{
            Name        = $task.TaskName
            State       = $task.State.ToString()
            Interval    = $interval
            LastRun     = if ($info.LastRunTime -and $info.LastRunTime -gt [DateTime]::MinValue) {
                              $info.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss')
                          } else { 'Never' }
            LastResult  = if ($info.LastTaskResult -eq 0) { 'Success' }
                          elseif ($info.LastTaskResult -eq 267009) { 'Running' }
                          else { "Code: $($info.LastTaskResult)" }
            NextRun     = if ($info.NextRunTime -and $info.NextRunTime -gt [DateTime]::MinValue) {
                              $info.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss')
                          } else { 'N/A' }
            Error       = $null
        }
    } catch {
        return @{
            Name       = $TaskName
            State      = 'NotFound'
            Interval   = 'N/A'
            LastRun    = 'N/A'
            LastResult = 'N/A'
            NextRun    = 'N/A'
            Error      = $_.Exception.Message
        }
    }
}

# ── Helper: Set Interval ──────────────────────────────────────
function Set-SAMTaskInterval {
    param([string]$TaskName, [int]$IntervalMin)
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

        foreach ($trigger in $task.Triggers) {
            if ($trigger.RepetitionInterval) {
                $trigger.RepetitionInterval = "PT${IntervalMin}M"
            }
        }

        Set-ScheduledTask -TaskName $TaskName -Trigger $task.Triggers -ErrorAction Stop | Out-Null
        return "OK — $TaskName interval = ${IntervalMin} นาที"
    } catch {
        return "ERROR — $($_.Exception.Message)"
    }
}

# ── ACTION: LIST ──────────────────────────────────────────────
if ($Action -eq 'LIST') {
    Write-Host "`n=== SAM Scheduler Config ===" -ForegroundColor Cyan
    Write-Host ("=" * 90)
    Write-Host ("{0,-20} {1,-10} {2,-12} {3,-12} {4,-20} {5,-10}" -f
        'Task','State','Interval','LastResult','LastRun','NextRun')
    Write-Host ("-" * 90)

    foreach ($key in $SAM_TASKS.Keys | Sort-Object) {
        $cfg  = $SAM_TASKS[$key]
        $info = Get-SAMTaskInfo -TaskName $cfg.Name

        $stateColor = switch ($info.State) {
            'Ready'   { 'Green' }
            'Running' { 'Cyan' }
            'Disabled'{ 'Yellow' }
            default   { 'Red' }
        }
        $ivStr = if ($info.Interval -ne 'N/A') { "$($info.Interval) นาที" } else { 'N/A' }

        Write-Host ("{0,-20} " -f $cfg.Name) -NoNewline
        Write-Host ("{0,-10} " -f $info.State) -NoNewline -ForegroundColor $stateColor
        Write-Host ("{0,-12} {1,-12} {2,-20} {3,-10}" -f
            $ivStr, $info.LastResult, $info.LastRun, $info.NextRun)

        $null = $Results.Add([PSCustomObject]@{
            Key         = $key
            TaskName    = $cfg.Name
            Desc        = $cfg.Desc
            State       = $info.State
            Interval    = $info.Interval
            DefaultMin  = $cfg.Default
            MinAllowed  = $cfg.Min
            MaxAllowed  = $cfg.Max
            LastRun     = $info.LastRun
            LastResult  = $info.LastResult
            NextRun     = $info.NextRun
        })
    }

    Write-Host ("=" * 90)

    # Output JSON สำหรับ SAM sync กลับ Supabase
    $output = @{
        action    = 'LIST'
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        computer  = $env:COMPUTERNAME
        tasks     = $Results
    } | ConvertTo-Json -Depth 5 -Compress

    Write-Host "`n[JSON_OUTPUT_START]"
    Write-Host $output
    Write-Host "[JSON_OUTPUT_END]"
}

# ── ACTION: SET ───────────────────────────────────────────────
elseif ($Action -eq 'SET') {
    if (-not $TaskName) { Write-Error "ต้องระบุ -TaskName"; exit 1 }
    if ($IntervalMinutes -le 0) { Write-Error "ต้องระบุ -IntervalMinutes"; exit 1 }

    if (-not $SAM_TASKS.ContainsKey($TaskName)) {
        Write-Error "ไม่รู้จัก TaskName: $TaskName"; exit 1
    }

    $cfg = $SAM_TASKS[$TaskName]

    # ตรวจ range
    if ($IntervalMinutes -lt $cfg.Min -or $IntervalMinutes -gt $cfg.Max) {
        Write-Error "IntervalMinutes ต้องอยู่ระหว่าง $($cfg.Min)-$($cfg.Max) นาที"
        exit 1
    }

    Write-Host "กำลังตั้งค่า $($cfg.Name) → interval = $IntervalMinutes นาที" -ForegroundColor Cyan
    $res = Set-SAMTaskInterval -TaskName $cfg.Name -IntervalMin $IntervalMinutes
    Write-Host $res -ForegroundColor (if ($res.StartsWith('OK')) { 'Green' } else { 'Red' })

    # แสดงค่าใหม่
    $info = Get-SAMTaskInfo -TaskName $cfg.Name
    Write-Host "`nค่าปัจจุบัน: $($cfg.Name) = $($info.Interval) นาที"

    $output = @{
        action    = 'SET'
        taskKey   = $TaskName
        taskName  = $cfg.Name
        interval  = $IntervalMinutes
        result    = $res
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json -Compress
    Write-Host "`n[JSON_OUTPUT_START]"
    Write-Host $output
    Write-Host "[JSON_OUTPUT_END]"
}

# ── ACTION: ENABLE / DISABLE ──────────────────────────────────
elseif ($Action -in 'ENABLE','DISABLE') {
    if (-not $TaskName) { Write-Error "ต้องระบุ -TaskName"; exit 1 }
    if (-not $SAM_TASKS.ContainsKey($TaskName)) {
        Write-Error "ไม่รู้จัก TaskName: $TaskName"; exit 1
    }

    $cfg = $SAM_TASKS[$TaskName]
    try {
        if ($Action -eq 'ENABLE') {
            Enable-ScheduledTask  -TaskName $cfg.Name -ErrorAction Stop | Out-Null
        } else {
            Disable-ScheduledTask -TaskName $cfg.Name -ErrorAction Stop | Out-Null
        }
        $msg = "OK — $($cfg.Name) $Action สำเร็จ"
        Write-Host $msg -ForegroundColor Green
    } catch {
        $msg = "ERROR — $($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
    }

    $output = @{
        action    = $Action
        taskKey   = $TaskName
        taskName  = $cfg.Name
        result    = $msg
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json -Compress
    Write-Host "`n[JSON_OUTPUT_START]"
    Write-Host $output
    Write-Host "[JSON_OUTPUT_END]"
}

# ── ACTION: RESET ─────────────────────────────────────────────
elseif ($Action -eq 'RESET') {
    Write-Host "RESET — คืนค่า Default ทุก Task" -ForegroundColor Yellow
    $resetResults = @{}

    foreach ($key in $SAM_TASKS.Keys) {
        $cfg = $SAM_TASKS[$key]
        $res = Set-SAMTaskInterval -TaskName $cfg.Name -IntervalMin $cfg.Default
        $resetResults[$key] = $res
        Write-Host "$($cfg.Name) → $($cfg.Default) นาที : $res" `
            -ForegroundColor (if ($res.StartsWith('OK')) { 'Green' } else { 'Red' })
    }

    $output = @{
        action    = 'RESET'
        results   = $resetResults
        timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json -Compress
    Write-Host "`n[JSON_OUTPUT_START]"
    Write-Host $output
    Write-Host "[JSON_OUTPUT_END]"
}
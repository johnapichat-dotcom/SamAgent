param([string]$CommandString)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    Invoke-Expression $CommandString | Out-Null
    "$(Get-Date) - [Task_RunCmd] Executed: $CommandString" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

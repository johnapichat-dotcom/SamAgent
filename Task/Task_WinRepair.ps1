param([string]$Action)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    switch ($Action) {
        "SFC" { Start-Process cmd.exe -ArgumentList "/c sfc /scannow" -WindowStyle Hidden -Wait }
        "DISM" { Start-Process cmd.exe -ArgumentList "/c DISM /Online /Cleanup-Image /RestoreHealth" -WindowStyle Hidden -Wait }
        "CHKDSK" { Start-Process cmd.exe -ArgumentList "/c echo Y | chkdsk C: /f /r" -WindowStyle Hidden -Wait }
    }
    "$(Get-Date) - [Task_WinRepair] Action: $Action" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

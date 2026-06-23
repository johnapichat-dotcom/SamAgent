param([string]$PrinterKeyword)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    $Printers = Get-Printer | Where-Object { $_.Name -match [regex]::Escape($PrinterKeyword) }
    foreach ($Prt in $Printers) {
        Remove-Printer -Name $Prt.Name -ErrorAction SilentlyContinue
        Remove-PrinterDriver -Name $Prt.DriverName -ErrorAction SilentlyContinue
        "$(Get-Date) - [Task_PrtRemove] Removed: $($Prt.Name)" | Out-File $LogFile -Append
    }
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

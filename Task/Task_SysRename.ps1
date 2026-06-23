param([string]$NewName, [string]$NewDesc)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    if ($NewName -and $NewName -ne "SKIP") { Rename-Computer -NewName $NewName -Force -ErrorAction Stop }
    if ($NewDesc -and $NewDesc -ne "SKIP") {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters" -Name "srvcomment" -Value $NewDesc -ErrorAction SilentlyContinue
        $OS = Get-WmiObject Win32_OperatingSystem; $OS.Description = $NewDesc; $OS.Put() | Out-Null
    }
    "$(Get-Date) - [Task_SysRename] Success (Reboot Required)" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

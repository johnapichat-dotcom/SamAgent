param([string]$Action, [string]$IP, [string]$Gateway, [string]$DNS)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    if ($Action -eq "SetPower") {
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bea028fdb6 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /S SCHEME_CURRENT
    } elseif ($Action -eq "SetIP") {
        $Adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
        New-NetIPAddress -InterfaceAlias $Adapter.Name -IPAddress $IP -PrefixLength 24 -DefaultGateway $Gateway -ErrorAction SilentlyContinue
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name -ServerAddresses ($DNS -split ",") -ErrorAction SilentlyContinue
    } elseif ($Action -eq "SetDHCP") {
        $Adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
        Set-NetIPInterface -InterfaceAlias $Adapter.Name -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name -ResetServerAddresses
    }
    "$(Get-Date) - [Task_NetPwrConfig] Success: $Action" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

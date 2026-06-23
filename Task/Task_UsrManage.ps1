param([string]$Action, [string]$Username, [string]$Password)
$LogFile = "C:\IT_Support\SAM_Log.txt"
try {
    switch ($Action) {
        "Create" {
            $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force
            New-LocalUser -Name $Username -Password $SecurePass -FullName $Username -Description "SAM Agent" -ErrorAction Stop
            Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue
        }
        "Delete" { Remove-LocalUser -Name $Username -ErrorAction Stop }
        "ChangePass" {
            $SecurePass = ConvertTo-SecureString $Password -AsPlainText -Force
            Get-LocalUser -Name $Username | Set-LocalUser -Password $SecurePass -ErrorAction Stop
        }
    }
    "$(Get-Date) - [Task_UsrManage] Success: $Action" | Out-File $LogFile -Append
} catch { "$(Get-Date) - Error: $($_.Exception.Message)" | Out-File $LogFile -Append }

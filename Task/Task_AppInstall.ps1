# รับค่า Argument และแยกชื่อโปรแกรมด้วยเครื่องหมายลูกน้ำ (,)
$AppList = $args[0] -split ','
$LogFile = "C:\IT_Support\SAM_Task_Log.txt"

"$(Get-Date) - [Task: Uninstall] Initiated for Multiple Apps: $($args[0])" | Out-File $LogFile -Append

# ดึงข้อมูล Registry เตรียมไว้ครั้งเดียวเพื่อความรวดเร็ว
$RegPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")

# วนลูปจัดการทีละโปรแกรม
foreach ($AppName in $AppList) {
    $CleanName = $AppName.Trim() # ตัดช่องว่างหัวท้าย
    if ([string]::IsNullOrWhiteSpace($CleanName)) { continue }

    # ค้นหาโปรแกรม
    $App = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match [regex]::Escape($CleanName) } | Select-Object -First 1

    if ($App) {
        "$(Get-Date) - [Task: Uninstall] Processing: $($App.DisplayName)" | Out-File $LogFile -Append
        
        # คัดกรอง Silent Switch
        if ($App.QuietUninstallString) {
            $UninstallCmd = $App.QuietUninstallString
        } elseif ($App.UninstallString -match "msiexec") {
            $UninstallCmd = $App.UninstallString -replace "(?i)/I", "/X"
            $UninstallCmd += " /qn /norestart"
        } else {
            $UninstallCmd = $App.UninstallString
            $UninstallCmd += " /S /VERYSILENT /quiet /norestart"
        }

        # ยิงคำสั่งแบบ Background รอจนกว่าแต่ละโปรแกรมจะเสร็จสิ้นก่อนเริ่มตัวถัดไป (-Wait)
        try {
            $Process = Start-Process cmd.exe -ArgumentList "/c `"$UninstallCmd`"" -Wait -WindowStyle Hidden -PassThru
            "$(Get-Date) - [Task: Uninstall] Success: $CleanName (Exit Code: $($Process.ExitCode))" | Out-File $LogFile -Append
        } catch {
            "$(Get-Date) - [Task: Uninstall] Error on $CleanName: $($_.Exception.Message)" | Out-File $LogFile -Append
        }
    } else {
        "$(Get-Date) - [Task: Uninstall] Skipped: '$CleanName' not found in Registry." | Out-File $LogFile -Append
    }
}

#-----------------------
# Phase1.ps1
#-----------------------

$ErrorActionPreference='Stop'

echo "$(date) Phase1.ps1 started" >> $env:SystemDrive\packer\configure.log

try {
    echo "$(date) Phase1.ps1 starting" >> $env:SystemDrive\packer\configure.log    
    echo $(date) > "c:\users\public\desktop\Phase1 Start.txt"
    #--------------------------------------------------------------------------------------------
    # Turn off antimalware
    echo "$(date) Phase1.ps1 Disabling realtime monitoring..." >> $env:SystemDrive\packer\configure.log
    set-mppreference -disablerealtimemonitoring $true

    #--------------------------------------------------------------------------------------------
    # Turn off the powershell execution policy
    echo "$(date) Phase1.ps1 Setting execution policy..." >> $env:SystemDrive\packer\configure.log
    set-executionpolicy bypass -Force

    #--------------------------------------------------------------------------------------------
    # Add the containers features
    echo "$(date) Phase1.ps1 Adding containers feature..." >> $env:SystemDrive\packer\configure.log
    Add-WindowsFeature containers

    #--------------------------------------------------------------------------------------------
    # Re-download the script that downloads our files in case we want to refresh them
    echo "$(date) Phase1.ps1 Re-downloading DownloadScripts.ps1..." >> $env:SystemDrive\packer\configure.log
    $ErrorActionPreference='SilentlyContinue'
    $wc=New-Object net.webclient;$wc.Downloadfile("https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/$env:Branch/DownloadScripts.ps1","$env:SystemDrive\packer\DownloadScripts.ps1")
    $ErrorActionPreference='SilentlyContinue'


    if ($env:LOCAL_CI_INSTALL -ne 1) {
        #--------------------------------------------------------------------------------------------
        # Set full crashdumps (don't fail if by any chance these fail - eg a different config Azure VM. Set for D3_V2)
        $ErrorActionPreference='SilentlyContinue'
        echo "$(date) Phase1.ps1 Enabling full crashdumps..." >> $env:SystemDrive\packer\configure.log    
        REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 1 /f | Out-Null
        REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 1 /f | Out-Null
        REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v DumpFile /t REG_EXPAND_SZ /d "c:\memory.dmp" /f | Out-Null

        echo "$(date) Phase1.ps1 Removing pagefile from D:..." >> $env:SystemDrive\packer\configure.log    
        $pagefile = Get-WmiObject -Query "Select * From Win32_PageFileSetting Where Name='d:\\pagefile.sys'"
        $pagefile.Delete()

        echo "$(date) Phase1.ps1 Directing pagefile.sys to C:..." >> $env:SystemDrive\packer\configure.log    
        Set-WMIInstance -class Win32_PageFileSetting -Arguments @{name="c:\pagefile.sys";InitialSize = 15000;MaximumSize = 15000}

        $ErrorActionPreference='Stop'
    }
    
    #--------------------------------------------------------------------------------------------
    # Configure the CI Environment
    echo "$(date) Phase1.ps1 Configuring the CI environment..." >> $env:SystemDrive\packer\configure.log    
    . $("$env:SystemDrive\packer\ConfigureCIEnvironment.ps1")

    #--------------------------------------------------------------------------------------------
    # Install most things
    echo "$(date) Phase1.ps1 Installing most things..." >> $env:SystemDrive\packer\configure.log    
    . $("$env:SystemDrive\packer\InstallMostThings.ps1")

    #--------------------------------------------------------------------------------------------

    if ($env:LOCAL_CI_INSTALL -ne 1) {
        # Download and install Cygwin for SSH capability  # BUGBUG Hope to get rid of using this....
        echo "$(date) Phase1.ps1 downloading cygwin..." >> $env:SystemDrive\packer\configure.log
        mkdir $env:SystemDrive\cygwin -erroraction silentlycontinue 2>&1 | Out-Null
        $wc=New-Object net.webclient;$wc.Downloadfile("https://cygwin.com/setup-x86_64.exe","$env:SystemDrive\cygwin\cygwinsetup.exe")
        echo "$(date) Phase1.ps1 installing cygwin..." >> $env:SystemDrive\packer\configure.log
        Start-Process -wait $env:SystemDrive\cygwin\cygwinsetup.exe -ArgumentList "-q -R $env:SystemDrive\cygwin --packages openssh openssl -l $env:SystemDrive\cygwin\packages -s http://mirrors.sonic.net/cygwin/ 2>&1 | Out-Null"
    }
    
    #--------------------------------------------------------------------------------------------
    
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        echo "$(date) Phase1.ps1 configuring temp to D..." >> $env:SystemDrive\packer\configure.log
        $env:Temp="d:\temp"
        $env:Tmp=$env:Temp
        [Environment]::SetEnvironmentVariable("TEMP", "$env:Temp", "Machine")
        [Environment]::SetEnvironmentVariable("TMP", "$env:Temp", "Machine")
        [Environment]::SetEnvironmentVariable("TEMP", "$env:Temp", "User")
        [Environment]::SetEnvironmentVariable("TMP", "$env:Temp", "User")
        mkdir $env:Temp -erroraction silentlycontinue 2>&1 | Out-Null
    }
    
    #--------------------------------------------------------------------------------------------
    # Download the ZDP and privates (if there are any)
    if (Test-Path "$env:SystemDrive\packer\DownloadPatches.ps1") {
        echo "$(date) Phase1.ps1 Downloading patches..." >> $env:SystemDrive\packer\configure.log    
        . $("$env:SystemDrive\packer\DownloadPatches.ps1")
    } else {
        echo "$(date) Phase1.ps1 Skipping DownloadPatches.ps1 as doesn't exist..." >> $env:SystemDrive\packer\configure.log
    }



    #--------------------------------------------------------------------------------------------
    # Install the ZDP (if it exists)
    if (Test-Path "$env:SystemDrive\packer\InstallZDP.ps1") {
        echo "$(date) Phase1.ps1 Installing ZDP..." >> $env:SystemDrive\packer\configure.log
        . $("$env:SystemDrive\packer\InstallZDP.ps1")
    } else {
        echo "$(date) Phase1.ps1 Skipping InstallZDP.ps1 as doesn't exist..." >> $env:SystemDrive\packer\configure.log
    }


    #--------------------------------------------------------------------------------------------
    # Initiate Phase2
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-command c:\packer\Phase2.ps1"
    $trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:00
    if ($env:LOCAL_CI_INSTALL -ne 1) {
        $pass = Get-Content c:\packer\password.txt -raw
        Register-ScheduledTask -TaskName "Phase2" -Action $action -Trigger $trigger -User jenkins -Password $pass -RunLevel Highest
    } else {
        Register-ScheduledTask -TaskName "Phase2" -Action $action -Trigger $trigger -User "administrator" -Password "p@ssw0rd" -RunLevel Highest
    }
}
Catch [Exception] {
    echo "$(date) Phase1.ps1 complete with Error '$_'" >> $env:SystemDrive\packer\configure.log
    echo $(date) > "c:\users\public\desktop\ERROR Phase1.txt"
    exit 1
}
Finally {

    # Disable the scheduled task
    echo "$(date) Phase1.ps1 disabling scheduled task.." >> $env:SystemDrive\packer\configure.log
    $ConfirmPreference='none'
    Get-ScheduledTask 'Phase1' | Disable-ScheduledTask

    # Reboot
    echo "$(date) Phase1.ps1 rebooting..." >> $env:SystemDrive\packer\configure.log
    echo $(date) > "c:\users\public\desktop\Phase1 End.txt"
    shutdown /t 0 /r /f /c "Phase1"
    echo "$(date) Phase1.ps1 complete successfully at $(date)" >> $env:SystemDrive\packer\configure.log
}    
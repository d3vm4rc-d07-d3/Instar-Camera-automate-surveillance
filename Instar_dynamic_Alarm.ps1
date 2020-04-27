#requires -Version 3.0
#=============================================================================================
# Modified on            2020-04-27
# Version                1.1
# Created by:            Marcus Opel
# Organization:          https://devmarc.de
#=============================================================================================
Remove-Module * -Force
$VerbosePreference = "SilentlyContinue" # SilentlyContinue | Continue
Import-Module "$PSScriptRoot\funcs.psm1" -NoClobber

$scriptConsoleTitle = 'Instar Dynamic Alarm (<your location>)'
$host.ui.RawUI.WindowTitle = $scriptConsoleTitle

$MainLoopFirstIteration = $true

$locationStatusUrl = 'http://<your local raspberry pi server ip>/IFTTT/status.txt'
$statusTxtFile = 'status.txt'
$isAtHomePattern = 'AtHome123456789' # your secret for @home
$isAwayPattern = 'Away123456789' # your secret for @away

# VARS
$cameraPassSecureStringFile = "$PSScriptRoot\adminSecureString.sec"
$cameraPassPlainStringFile = "$PSScriptRoot\adminPlainPassword.sec"
$cameraUser = 'admin'
$cameraHost = "192.168.X.X" # your ddns3-instar.de address or your local camera ip
$cameraTimeoutInSeconds = 60
$cameraUseSSL = $true
$syslogFilePath = ('{0}\IN-8015_Log.txt' -f $PSScriptRoot)
$actionLogPath = "$PSScriptRoot\action.log"

# Create secure string and store it locally
# ConvertTo-SecureString "yourTopSecretP@ssword" -AsPlainText -Force | ConvertFrom-SecureString | Out-File $cameraPassSecureStringFile; exit

try {
  $cameraSecureString = Get-Content $cameraPassSecureStringFile | ConvertTo-SecureString
  $cameraPassword = (New-Object PSCredential $cameraUser,$cameraSecureString).GetNetworkCredential().Password # or use just a normal string (less secure)
}
catch [DllNotFoundException] { # linux (.net core)

  $cameraUseSSL = $false # linux (.net core) temp workaround

  if (!(Test-Path $cameraPassPlainStringFile)) {
    Read-Host -Prompt "Enter your password" | Out-File $cameraPassPlainStringFile
    $cameraPassword = Get-Content $cameraPassPlainStringFile # linux (.net core) temp workaround
  }
  else {
    $cameraPassword = Get-Content $cameraPassPlainStringFile # linux (.net core) temp workaround
  }
  Write-LogExt "Secure String Security & SSL has been disabled!" -Level Warn
}

# https://wiki.instar.de/1080p_Series_CGI_List
# $command = '/param.cgi?cmd=getmdalarm&-aname=record'                                                                                         # Save Video to SD [on/off status]
# $command = '/param.cgi?cmd=getmdalarm&-aname=emailsnap&cmd=getmdalarm&-aname=record'                                                         # Mail Alarm, Save Video to SD [on/off status]
# $disableSendMailSaveVideoToSD = '/param.cgi?cmd=setmdalarm&-aname=emailsnap&-switch=off&cmd=setmdalarm&-aname=record&-switch=off'            # Disable "Send Mail" & Disable "Save Video to SD"
# $command = '/param.cgi?cmd=setmdalarm&-aname=emailsnap&-switch=on&cmd=setmdalarm&-aname=record&-switch=on'                                   # Enable "Send Mail" & Enable "Save Video to SD"
# $command = '/param.cgi?cmd=preset&-act=goto&-number=0'                                                                                       # goto stored postion 1 (in web gui)
# $command = '/param.cgi?cmd=preset&-act=goto&-number=1'                                                                                       # goto stored postion 2 (in web gui)
# $command = '/param.cgi?cmd=setircutattr&-saradc_switch_value=270&-saradc_b2c_switch_value=270&cmd=set_instar_admin&-index=2&-value=open'     # IR-Cut-Filter open (always day / colour mode) [For all camera models - except IN-9020 FHD and IN-9010 FHD]
# $command = '/param.cgi?cmd=setircutattr&-saradc_switch_value=208&-saradc_b2c_switch_value=190&cmd=set_instar_admin&-index=2&-value=auto'     # IR-Cut-Filter auto (controlled by light sensor) [For all camera models - except IN-9020 FHD and IN-9010 FHD]

# Get Mail Alarm [on/off status]
$mailAlarmStatus = '/param.cgi?cmd=getmdalarm&-aname=emailsnap'
# Disable "Send Mail" & Disable "Save Video to SD" & Goto Positon 2 (in Web Gui) & Infraredstat close (deactivated) & FTP Snapshot Off & IR-Cut-Filter open
$disableAlarmAndDependencies = '/param.cgi?cmd=setmdalarm&-aname=emailsnap&-switch=off&cmd=setmdalarm&-aname=record&-switch=off&?cmd=preset&-act=goto&-number=1&cmd=setinfrared&-infraredstat=close&cmd=setmdalarm&-aname=ftpsnap&-switch=off&cmd=setircutattr&-saradc_switch_value=270&-saradc_b2c_switch_value=270&cmd=set_instar_admin&-index=2&-value=open'
# Goto Positon 1 (in Web Gui) & Infraredstat auto [Enabled Alarm Position]
$goToPosition1_InfraredstatAuto = '/param.cgi?cmd=preset&-act=goto&-number=0&cmd=setinfrared&-infraredstat=auto'
# Enable "Send Mail" & Enable "Save Video to SD" & FTP Snapshot On & IR-Cut-Filter auto
$enableAlarmAndDependencies = '/param.cgi?cmd=setmdalarm&-aname=emailsnap&-switch=on&cmd=setmdalarm&-aname=record&-switch=on&cmd=setmdalarm&-aname=ftpsnap&-switch=on&cmd=setircutattr&-saradc_switch_value=208&-saradc_b2c_switch_value=190&cmd=set_instar_admin&-index=2&-value=auto'
$getSyslogCommand = '/tmpfs/syslog.txt'

Write-LogExt "Start script ..." -Level Info

$result = $null

while ($true)
{
    
  # count actions (security)
  # more than 10 actions and the script wont work more (for today)
  if (Test-Path $actionLogPath) {
    $actionDateCountToday = Get-Content $actionLogPath
    $actionLogEntriesToday = @($actionDateCountToday | Select-String -SimpleMatch -Pattern $((Get-date -f yyyy-MM-dd))).Count
    
    if ($actionLogEntriesToday -gt 10) {
      Write-LogExt -Message "More than 10 Actions done today! -> No more action allowed!" -Level Warn
      Start-Sleep 600 # Wait 10 min
      continue
    }
  }
  
  # get current status from webserver
  $currentStatus = Invoke-WebRequest $locationStatusUrl
  $currentStatus = $currentStatus.Content.Trim()
  
  if ($currentStatus -eq $null) { Write-LogExt -Message "Current Status is null!" -Level Error; Start-Sleep 60; continue } 
  # get last stored status on this server
  $statusResult = Get-Content -Path "$PSScriptRoot\$statusTxtFile"
   
  if (($currentStatus).Equals($statusResult) -and $MainLoopFirstIteration -eq $false) {
    Write-Host -ForegroundColor Magenta "No Status Change! ... Wait..."; Start-Sleep 60; continue
  }
  elseif (($currentStatus).Equals($statusResult) -and $MainLoopFirstIteration) {
    Write-LogExt -Message "Main Loop - First Iteration!" -Level Info
    $MainLoopFirstIteration = $false
  }
  else {
    $currentStatus | Out-File "$PSScriptRoot\$statusTxtFile"
    $statusResult = $currentStatus
  }
        
  
  if ((($statusResult | Select-String -SimpleMatch -Pattern $isAtHomePattern) -eq $null) -and (($statusResult | Select-String -SimpleMatch -Pattern $isAwayPattern) -eq $null)) { 

    Write-LogExt -Message "No valid Status is available!" -Level Error
    Start-Sleep 120 # wait 2 min
    continue
  }
    
      
  if ((($statusResult | Select-String -SimpleMatch -Pattern $isAtHomePattern) -ne $null)) { 
        
    Write-LogExt -Message "I am at home ..." -Level Info
    
    # check also alarm events
    $recentAlarmTriggered = Test-IfSyslogLastAlarmEventIsNotOlderThan -CameraHost $cameraHost -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword `
    -Command $getSyslogCommand -LogfilePath $syslogFilePath -TimeInMinutes 20
    
    if ($recentAlarmTriggered -eq $false) {
      # query
      $result = Invoke-InstarWebRequest -CameraHost $cameraHost -Command $mailAlarmStatus -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword -TimeoutInSeconds $cameraTimeoutInSeconds
      if ($result.ParameterStatus -ne 'off') { 
        $result = Invoke-InstarWebRequest -CameraHost $cameraHost -Command $disableAlarmAndDependencies -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword -TimeoutInSeconds $cameraTimeoutInSeconds
        if ($result.HasError) {
          # log error
          Write-LogExt -Message "$($result.Exception)" -Level Error
        }
        else {
          Write-LogExt -Message $disableAlarmAndDependencies -Level Info -Path $actionLogPath
        }
      }
    }
    else {
      "Cannot change Camera Position to 'Someone is at home' because there was a recent Alarm!" | Out-File "$PSScriptRoot\$statusTxtFile"
      Write-LogExt -Message "Cannot change Camera Position to 'Someone is at home' because there was a recent Alarm!" -Level Warn
    }
  }
  else {

    Write-LogExt -Message "I am away ..." -Level Info

    # query
    $result = Invoke-InstarWebRequest -CameraHost $cameraHost -Command $mailAlarmStatus -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword -TimeoutInSeconds $cameraTimeoutInSeconds
    if ($result.ParameterStatus -ne 'on') {

      $result = Invoke-InstarWebRequest -CameraHost $cameraHost -Command $goToPosition1_InfraredstatAuto -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword -TimeoutInSeconds $cameraTimeoutInSeconds
      if ($result.HasError) {
      
        # log error
        Write-LogExt -Message "$($result.Exception)" -Level Error
      }
      else {
        Write-LogExt -Message $goToPosition1_InfraredstatAuto -Level Info -Path $actionLogPath
      }
      
      # Wait until camera has the correct position (to prevent false alarm)
      Start-Sleep 10

      $result = Invoke-InstarWebRequest -CameraHost $cameraHost -Command $enableAlarmAndDependencies -UseSSL $cameraUseSSL -User $cameraUser -Password $cameraPassword -TimeoutInSeconds $cameraTimeoutInSeconds
      if ($result.HasError) {
      
        # log error
        Write-LogExt -Message "$($result.Exception)" -Level Error
      }
      else {
        Write-LogExt -Message $enableAlarmAndDependencies -Level Info -Path $actionLogPath
      }
    }

  } 
  
  Start-Sleep 60
    
}

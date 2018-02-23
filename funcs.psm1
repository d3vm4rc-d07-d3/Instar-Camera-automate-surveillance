#=============================================================================================
# Modified on            2018-02-23
# Version                1.0
# Created by:            Marcus Opel
# Organization:          https://devmarc.de
#=============================================================================================

function Invoke-InstarWebRequest {
  <#
      .SYNOPSIS
      Invoke-InstarWebRequest allows you via GET WebRequest to trigger a CGI script on the camera webserver
      .EXAMPLE
      Send-Command -CameraHost <string> -Command <string> -UseSSL $true|$false -User <string> -Password <string> -TimeoutInSeconds <int>
      .OUTPUTS
      WebResponseObject
  #>
  
  param
  (
    [string]$CameraHost,

    [string]$Command,

    [bool]$UseSSL,

    [string]$User,

    [string]$Password,

    [int]$TimeoutInSeconds
  )

  try {

    $exception = $null
    $output = $null
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User,$Password)))
    $uriPart = 'https'
    if ($UseSSL) { $uriPart = 'https' } else { $uriPart = 'http' }
    $output = Invoke-WebRequest `
    -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo); Method = 'Get'} `
    -ContentType 'multipart/form-data' `
    -Method Get `
    -Uri "$($uriPart)://$($CameraHost)$Command" `
    -TimeoutSec $TimeoutInSeconds
  }
  catch {
   
    $exception = $_.Exception
  }
   
  $parameterStatus = ($output.Content | Select-String -Pattern '\"(.*?)\"' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value -replace '"','' })

  # error check
  $hasError = $false
  if ($exception -ne $null -or $($output.StatusCode) -ne 200 -or ($($output.Content) | Select-String -SimpleMatch -Pattern 'Error') -ne $null) {
    $hasError = $true
  }
  else {
    $hasError = $false
  }

  $cusObject = New-Object -TypeName PSObject -Property @{

    'HttpStatusCode' = $($output.StatusCode )
    'Content' = $($output.Content)
    'ParameterStatus' = $parameterStatus
    'ParameterStatusCount' = $($parameterStatus.Count)
    'ExceptionResponseStatus' = $($exception.Response.StatusCode)
    'Exception' = $exception
    'HasError' = $hasError
  }
  
  return $cusObject
}

function Write-LogExt {
  <#
      .Synopsis
      Write-Log writes a message to a specified log file with the current time stamp (using .NET Streamwriter means really fast and short files)
      .DESCRIPTION
      The Write-Log function is designed to add logging capability to other scripts.
      In addition to writing output and/or verbose you can write to a log file for
      later debugging.
      To Do:
      * Add error handling if trying to create a log file in a inaccessible location.
      * Add ability to write $Message to $Verbose or $Error pipelines to eliminate
      duplicates.
      .PARAMETER Message
      Message is the content that you wish to add to the log file. 
      .PARAMETER Path
      The path to the log file to which you would like to write. By default the function will 
      create the path and file if it does not exist. 
      .PARAMETER Level
      Specify the criticality of the log information being written to the log (i.e. Error, Warning, Informational)
      .PARAMETER NoClobber
      Use NoClobber if you do not wish to overwrite an existing file.
      .EXAMPLE
      Write-Log -Message 'Log message' 
      Writes the message to c:\Logs\PowerShellLog.log.
      .EXAMPLE
      Write-Log -Message 'Restarting Server.' -Path c:\Logs\Scriptoutput.log
      Writes the content to the specified log file and creates the path and file specified. 
      .EXAMPLE
      Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error
      Writes the message to the specified log file as an error message, and writes the message to the error pipeline.
  #>

  # Write-LogExt v.0.1_29112016

  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory=$true,
    ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [Alias('LogContent')]
    [string]$Message,

    [Parameter(Mandatory=$false)]
    [Alias('LogPath')]
    [string]$Path="$PSScriptRoot\output.log",

    [Parameter(Mandatory=$false)]
    [bool]$SuppressConsoleOutput=$false,
        
    [Parameter(Mandatory=$false)]
    [ValidateSet('Error','Warn','Info')]
    [string]$Level='Info',
        
    [Parameter(Mandatory=$false)]
    [switch]$NoClobber
  )

  Begin
  {
    # Set VerbosePreference to Continue so that verbose messages are displayed.
    $VerbosePreference = 'Continue'
  }
  Process
  {
            
    # If the file already exists and NoClobber was specified, do not write to the log.
    if ((Test-Path $Path) -and $NoClobber) {
      Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
      Return
    }

    # setup some convenience variables to keep each line shorter
    $mode = [IO.FileMode]::Append
    $access = [IO.FileAccess]::Write
    $sharing = [IO.FileShare]::Read

    # create the FileStream and StreamWriter objects
    $fs = New-Object IO.FileStream($Path, $mode, $access, $sharing)
    $encoding = [Text.Encoding]::Unicode
    # $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
    $sw = New-Object System.IO.StreamWriter($fs), $encoding
    
    # Format Date for our Log File
    $FormattedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Write message to error, warning, or verbose pipeline and specify $LevelText
    switch ($Level) {
      'Error' {
        if (!($SuppressConsoleOutput)) { Write-Error "$FormattedDate $Message" }
        $LevelText = 'ERROR:'
      }
      'Warn' {
        if (!($SuppressConsoleOutput)) { Write-Warning "$FormattedDate $Message" }
        $LevelText = 'WARNING:'
      }
      'Info' {
        if (!($SuppressConsoleOutput)) { Write-Verbose "$FormattedDate $Message" }
        $LevelText = 'INFO:'
      }
    }
    # write something and remember to call to Dispose to clean up the resources
    $sw.WriteLine("$FormattedDate $LevelText $Message")
  }
  End
  {
    $sw.Dispose()
    $fs.Dispose()
  }
}

function Test-IfSyslogLastAlarmEventIsNotOlderThan {
  
  param
  (
    [string]$CameraHost,

    [bool]$UseSSL,

    [string]$User,

    [string]$Password,

    [string]$Command,

    [string]$LogfilePath,

    [Int]$TimeInMinutes
  )
  
  $response = Invoke-InstarWebRequest -CameraHost $CameraHost -UseSSL $UseSSL -User $User -Password $Password -Command $Command
  
  $response.Content | Out-File $LogfilePath
    
  $allAlarmEvents = Get-Content -Path $LogfilePath | Where-Object { ($_ | Select-String 'alarm event') }

  $lastAlarmEvent = $allAlarmEvents | Select-Object -Last 1
    
  if ($lastAlarmEvent -eq $null) { return $false }
  
  # extract datetime from string
  $regex = [regex]'\[\w+\s+\d+\:\d+\:\d+\]'
  $match = $regex.Match($lastAlarmEvent) 
  $dateTimeExtract = $match.Captures[0].value
  $dateTimeAlarmEvent = $dateTimeExtract -replace '^.|.$', '' # remove first and last char
  
  $timeSpan = New-TimeSpan -Minutes $TimeInMinutes
  $currentTimeMinusHours = (Get-Date) - $timeSpan
  $dateTimeAlarmEventObj = [Datetime]::ParseExact($dateTimeAlarmEvent, "yyyy_MM_dd H:mm:ss", $null)

  if ($dateTimeAlarmEventObj -gt $currentTimeMinusHours) { # if true, do not change position, because last alarm event was recently triggered
    return $true
  }
  else {
    return $false
  }
}
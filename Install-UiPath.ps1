[CmdletBinding()]
Param (
  [Parameter(Mandatory = $true)]
  [ValidateSet("18.4.5", "19.4.1", "19.4.2", "19.4.3")]
  [string] $studioVersion,

  [Parameter(Mandatory = $true)]
  [ValidateSet("Unattended", "Attended", "Development", "Nonproduction")]
  [string] $robotType,

  [Parameter()]
  [String] $orchestratorUrl,

  [Parameter()]
  [String] $machineKeysUrl,

  [Parameter()]
  [String] $tenant,

  [Parameter()]
  [string] $installationFolder,

  [Parameter()]
  [string] $hostingType
)
#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"
#Script Version
$sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$sDebug = $true
#Log File Info
$LogPath = "C:\ProgramData\AutomationAzureOrchestration"
$LogName = "Install-UiPath-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Orchestrator SSL check
$orchSSLcheck = $false

function Main {

  Begin {
    #Log log log
    Write-Host "Install-UiPath starts"
    Write-Log -LogPath $LogFile -Message "Install-UiPath starts" -Severity "Info"

    #Define TLS for Invoke-WebRequest
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (!$orchSSLcheck) {
      [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    #Setup temp dir in %appdata%\Local\Temp
    $script:tempDirectory = (Join-Path $ENV:TEMP "UiPath-$(Get-Date -f "yyyyMMddhhmmssfff")")
    New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

    #Download UiPlatform
    $msiName = 'UiPathStudio.msi'
    $msiPath = Join-Path $script:tempDirectory $msiName
    $robotExePath = Get-UiRobotExePath

    Write-Host "The result of Get-UiRobotExePath is: $robotExePath"
    if (!(Test-Path $robotExePath)) {
      Download-File -url "https://download.uipath.com/versions/$studioVersion/UiPathStudio.msi" -outputFile $msiPath
    }
  }

  Process {
    #Get Robot path
    $robotExePath = Get-UiRobotExePath

    if (!(Test-Path $robotExePath)) {

      Write-Host "Installing UiPath Robot Type [$robotType]"
      Write-Log -LogPath $LogFile -Message "Installing UiPath Robot Type [$robotType]" -Severity "Info"

      #Install the Robot
      if ($robotType -eq "Development") {
        # log log log
        Write-Host "Installing UiPath Robot with Studio Feature"
        Write-Log -LogPath $LogFile -Message "Installing UiPath Robot with Studio Feature" -Severity "Info"
        $msiFeatures = @("DesktopFeature", "Robot", "Studio", "StartupLauncher", "RegisterService", "Packages")
      }
      Else {
        # log log log
        Write-Host "Installing UiPath Robot without Studio Feature"
        Write-Log -LogPath $LogFile -Message "Installing UiPath Robot without Studio Feature" -Severity "Info"
        $msiFeatures = @("DesktopFeature", "Robot", "StartupLauncher", "RegisterService", "Packages")
      }

      Try {
        if ($installationFolder) {
          Write-Host "Calling Install-Robot with argument installationFolder: $installationFolder"
          Write-Log -LogPath $LogFile -Message "Calling Install-Robot with argument installationFolder: $installationFolder" -Severity "Info"

          $installResult = Install-UiPath -msiPath $msiPath -installationFolder $installationFolder -msiFeatures $msiFeatures
          $uiPathDir = "$installationFolder\UiPath"
          if (!(Test-Path $uiPathDir)) {
            throw "Could not find installation of UiPath at $installationFolder"
          }
        }
        Else {
          $installResult = Install-UiPath -msiPath $msiPath -msiFeatures $msiFeatures
        }
      }
      Catch {
        if ($_.Exception) {
          Write-Host "There was an error installing UiPath: $_.Exception"
          Log-Error -LogPath $LogFile -Message $_.Exception -Severity "Error"
        }
        Else {
          Write-Host "There was an error installing UiPath, but the exception was empty"
          Log-Error -LogPath $LogFile -Message "There was an error, but it was blank" -Severity "Error"
        }
        Break
      }

    }
    Else {
      Write-Host "Previous instance of UiRobot.exe existed at $robotExePath, not installing the robot"
      Write-Log -LogPath $LogFile -Message "Previous instance of UiRobot.exe existed at $robotExePath, not installing the robot" -Severity "Info"
    }

    Write-Host "Removing temp directory $($script:tempDirectory)"
    Write-Log -LogPath $LogFile -Message "Removing temp directory $($script:tempDirectory)" -Severity "Info"
    Remove-Item $script:tempDirectory -Recurse -Force | Out-Null


    Write-Host "Checking robot service now"
    Write-Log -LogPath $LogFile -Message "Checking robot service now" -Severity "Info"

    $roboService = Get-Service -DisplayName "UiPath Robot"
    $roboState = $roboService.Status
    Write-Host "Robo status is: $roboState"
    Write-Log -LogPath $LogFile -Message "Robo status is: $roboState" -Severity "Info"

    if (($roboService -and $roboService.Status -eq "Stopped" )) {
      Write-Host "Robot service was stopped, starting and waiting for it now"
      Write-Log -LogPath $LogFile -Message "Robot service was stopped, starting and waiting for it now" -Severity "Info"
      Start-Service $roboService.Name
    }
  
  }
  End {
    If ($?) {
      Write-Host "Completed Successfully."
      Write-Log -LogPath $LogFile -Message "Completed Successfully." -Severity "Info"
    }
  }

}

<#
  .DESCRIPTION
  Installs an MSI by calling msiexec.exe, with verbose logging
  .PARAMETER msiPath
  Path to the MSI to be installed
  .PARAMETER logPath
  Path to a file where the MSI execution will be logged via "msiexec [...] /lv*"
  .PARAMETER features
  A list of features that will be installed via ADDLOCAL="..."
  .PARAMETER properties
  Additional MSI properties to be passed to msiexec
#>
function Invoke-MSIExec {

  param (
    [Parameter(Mandatory = $true)]
    [string] $msiPath,

    [Parameter(Mandatory = $true)]
    [string] $logPath,

    [string[]] $features,

    [System.Collections.Hashtable] $properties
  )

  if (!(Test-Path $msiPath)) {
    throw "No .msi file found at path '$msiPath'"
  }

  $msiExecArgs = "/i `"$msiPath`" /q /lv* `"$logPath`" "

  if ($features) {
    $msiExecArgs += "ADDLOCAL=`"$($features -join ',')`" "
  }

  if ($properties) {
    $msiExecArgs += (($properties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " ")
  }

  $process = Start-Process "msiexec" -ArgumentList $msiExecArgs -Wait -PassThru

  return $process
}

<#
  .DESCRIPTION
  Gets the path to the UiRobot.exe file
  .PARAMETER community
  Whether to search for the UiPath Studio Community edition executable
#>
function Get-UiRobotExePath {
  param(
    [switch] $community
  )

  $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")

  if ($community) {
    $robotExePath = Get-ChildItem ([System.IO.Path]::Combine($ENV:LOCALAPPDATA, "UiPath")) -Recurse -Include "UiRobot.exe" | `
        Select-Object -ExpandProperty FullName -Last 1
  }

  return $robotExePath
}

<#
  .DESCRIPTION
  Downloads a file from a URL
  .PARAMETER url
  The URL to download from
  .PARAMETER outputFile
  The local path where the file will be downloaded
#>
function Download-File {
  param (
    [Parameter(Mandatory = $true)]
    [string]$url,

    [Parameter(Mandatory = $true)]
    [string] $outputFile
  )

  Write-Verbose "Downloading file from $url to local path $outputFile"

  $webClient = New-Object System.Net.WebClient

  $webClient.DownloadFile($url, $outputFile)

}

<#
  .DESCRIPTION
  Install UiPath Robot and/or Studio.
  .PARAMETER msiPath
  MSI installer path.
  .PARAMETER installationFolder
  Installation folder location.
  .PARAMETER msiFeatures
  MSI features : Robot with or without Studio
#>
function Install-UiPath {

  param (
    [Parameter(Mandatory = $true)]
    [string] $msiPath,

    [string] $installationFolder,

    [string[]] $msiFeatures
  )

  if (!$msiProperties) {
    $msiProperties = @{ }
  }

  if ($installationFolder) {
    Write-Host "Install-UiPath attempting to install UiPath at path $installationFolder"
    $msiProperties["APPLICATIONFOLDER"] = $installationFolder;
  }
  Else {
    Write-Host "Installing UiPath at default path"
  }

  $logPath = Join-Path $script:tempDirectory "install.log"
  $process = Invoke-MSIExec -msiPath $msiPath -logPath $logPath -features $msiFeatures

  return @{
    LogPath        = $logPath;
    MSIExecProcess = $process;
  }
}

Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop
Main

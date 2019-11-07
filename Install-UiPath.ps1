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
$ErrorActionPreference = "Stop"
#Script Version
$sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$sDebug = $true
#Log File Info
$LogPath = "C:\ProgramData\AutomationAzureOrchestration"
$LogName = "Install-UiPath-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Orchestrator SSL check
$tempDirectory = (Join-Path $ENV:TEMP "UiPath-$(Get-Date -f "yyyyMMddhhmmssfff")")
$orchModuleDir = "C:\Program Files\WindowsPowerShell\Modules\Dsb.RobotOrchestration"

$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
$orchSSLcheck = $false

function Main {

  Begin {
    try {
      $orchModule = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Dsb.RobotOrchestration.psm1"
      Write-Host "Attempting to download file from from: $orchModule"
      $orchModuleDownload = "$orchModuleDir\Dsb.RobotOrchestration.psm1"
      $wc = New-Object System.Net.WebClient
      $wc.DownloadFile($orchModule, $orchModuleDownload)

      $p = [Environment]::GetEnvironmentVariable("PSModulePath")
      $p += ";C:\Program Files\WindowsPowerShell\Modules\"
      [Environment]::SetEnvironmentVariable("PSModulePath", $p)
      
      If (Get-Module Dsb.RobotOrchestration) {
          Remove-Module Dsb.RobotOrchestration
      }

      Import-Module Dsb.RobotOrchestration
      
      Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop

      #Log log log
      Write-Host "Install-UiPath starts"

      #Setup temp dir in %appdata%\Local\Temp
      New-Item -ItemType Directory -Path $tempDirectory | Out-Null
      Write-Host "Temp directory is $tempDirectory"

      #Download UiPlatform
      $msiName = 'UiPathStudio.msi'
      $msiPath = Join-Path $tempDirectory $msiName
      $robotExePath = Get-UiRobotExePath

      Write-Host "The result of Get-UiRobotExePath is: $robotExePath"
      if (!(Test-Path $robotExePath)) {
        Write-Host "No robot exe existed, downloading the msi now"

        $uipathMsi = "https://download.uipath.com/versions/$studioVersion/UiPathStudio.msi"
        Write-Host "Attempting to download file from from: $uipathMsi"
        $uipathMsiDownload = "$tempDirectory/UiPathStudio.msi"
        $wc.DownloadFile($uipathMsi, $uipathMsiDownload)      
      }
    }
    catch {
      Write-Host "There was an error installing UiPath: $_.Exception"
      break
    }
  }

  Process {
    #Get Robot path
    $robotExePath = Get-UiRobotExePath

    if (!(Test-Path $robotExePath)) {

      Write-Host "Installing UiPath Robot Type [$robotType]"


      #Install the Robot
      if ($robotType -eq "Development") {
        # log log log
        Write-Host "Installing UiPath Robot with Studio Feature"
  
        $msiFeatures = @("DesktopFeature", "Robot", "Studio", "StartupLauncher", "RegisterService", "Packages")
      }
      Else {
        # log log log
        Write-Host "Installing UiPath Robot without Studio Feature"
  
        $msiFeatures = @("DesktopFeature", "Robot", "StartupLauncher", "RegisterService", "Packages")
      }

      Try {
        if ($installationFolder) {
          Write-Host "Calling Install-Robot with argument installationFolder: $installationFolder"
    

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
  
        }
        Else {
          Write-Host "There was an error installing UiPath, but the exception was empty"
  
        }
        Break
      }

    }
    Else {
      Write-Host "Previous instance of UiRobot.exe existed at $robotExePath, not installing the robot"

    }

    Write-Host "Removing temp directory $($tempDirectory)"
    Remove-Item $tempDirectory -Recurse -Force | Out-Null

    Write-Host "Checking robot service now"

    $roboService = Get-Service -DisplayName "UiPath Robot"
    $roboState = $roboService.Status
    Write-Host "Robo status is: $roboState"

    if (($roboService -and $roboService.Status -eq "Stopped" )) {
      Write-Host "Robot service was stopped, starting and waiting for it now"

      Start-Service $roboService.Name
    }
  
  }
  End {
    If ($?) {
      Write-Host "Completed Successfully."

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

  $logPath = Join-Path $tempDirectory "install.log"
  $process = Invoke-MSIExec -msiPath $msiPath -logPath $logPath -features $msiFeatures

  return @{
    LogPath        = $logPath;
    MSIExecProcess = $process;
  }
}

Main

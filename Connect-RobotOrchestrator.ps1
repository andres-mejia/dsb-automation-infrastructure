[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("6.8.1","7.2.0")]
        [string] $FilebeatVersion,

        [Parameter(Mandatory = $true)]
        [string] $RobotKey,

        [Parameter(Mandatory = $true)]
        [string] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken
    )

$ErrorActionPreference = "SilentlyContinue"
#Script Version
$sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$sDebug = $true
#Log File Info
$sLogPath = "C:\Users\Public"
$sLogName = "Connect-Uipath-Robot-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$global:LogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
#Orchestrator SSL check
$orchSSLcheck = $false

function Main {        
    Process {

        $script:tempDirectory = (Join-Path "C:\Users\Public" "Orchestration-Temp-$(Get-Date -f "yyyyMMddhhmmssfff")")
        New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

        Install-Filebeat -InstallationPath $script:tempDirectory -FilebeatVersion 7.2.0

        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity 'Info'

        Write-Host "Connect Robot Orchestrator starts"
        Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity 'Info'

        Write-Host "Tenant is $tenant"
        Write-Log -LogPath $LogFile -Message "Tenant is $tenant" -Severity 'Info'

        #Define TLS for Invoke-WebRequest
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if(!$orchSSLcheck) {
          [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }

        $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
        Write-Host "Robot exe is $robotExePath"
        Write-Log -LogPath $LogFile -Message "Robot exe is $robotExePath" -Severity 'Info'

        if(!(Test-Path $robotExePath)) {
            Throw 'No robot exe was found on the $env:computername'
        } else {
          Write-Host "Robot exe found at $robotExePath"
          Write-Log -LogPath $LogFile -Message "Robot exe found at $robotExePath" -Severity 'Info'
        }

        Try {
            # $orchMachines = "$machineKeysUrl/api/v1/machines/$tenant"
            # Write-Host "Url for retrieving machine keys is $orchMachines"
            # $wc = New-Object System.Net.WebClient
            # $machineString = $wc.DownloadString($orchMachines)
            # Write-Host "Machines are $machineString"
            # $machines =  $machineString | ConvertFrom-Json

            # $RobotKey = $null
            # ForEach ($machine in $machines) {
            #     If ($env:computername -eq $machine.name) {
            #         $RobotKey = $machine.key
            #     }
            # $RobotKey

            # If ($RobotKey -eq $null) {
            #     Throw ('No license key found for machine: $env:computername')
            # }

            Write-Log -LogPath $LogFile -Message "License key for $env:computername is: $RobotKey" -Severity 'Info'
            Write-Host "License key for $env:computername is: $RobotKey"

            # Starting Robot
            Start-Process -filepath $robotExePath -verb runas

            $waitForRobotSVC = waitForService "UiPath Robot*" "Running"

            $env = "dev"
            $orchestratorUrl = "https://orchestrator-app-${Environment}.azure.dsb.dk"
            # if ($waitForRobotSVC -eq "Running") {
            # connect Robot to Orchestrator with Robot key
            Write-Log -LogPath $LogFile -Message "Orchestrator URL to connect to is: $orchestratorUrl" -Severity 'Info'
            Write-Host "Orchestrator URL to connect to is: $orchestratorUrl"
            # if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
            Try {
                $connectRobot = Start-Process -FilePath $robotExePath -Verb runAs -ArgumentList "--connect -url $orchestratorUrl -key $RobotKey"
            }
            Catch {
                if ($_.Exception) {
                    Write-Host "There was an error running the robot.exe connect command, exception: $_.Exception"
                    Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
                }
                else {
                    Write-Host "There was an error running the robot.exe connect command, but the exception was empty"
                    Write-Log -LogPath $LogFile -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
                }
                Brea
            }
        }
        Catch {
            if ($_.Exception) {
                Write-Host "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
                Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            }
            else {
                Write-Host "There was an error connecting the machine to $orchMachines, but the exception was empty"
                Write-Log -LogPath $LogFile -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
            }
            Break
        }

        Write-Host "Removing temp directory $($script:tempDirectory)"
        Write-Log -LogPath $LogFile -Message "Removing temp directory $($script:tempDirectory)" -Severity 'Info'
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        End {
            If($?){
              Write-Host "Completed Successfully."
                Write-Log -LogPath $LogFile -Message "Completed Successfully." -Severity 'Info'
                Write-Host "Script is ending now."
            }
        }
    }
}

function waitForService($servicesName, $serviceStatus) {

  # Get all services where DisplayName matches $serviceName and loop through each of them.
  foreach($service in (Get-Service -DisplayName $servicesName))
  {
      if($serviceStatus -eq 'Running') {
        Start-Service $service.Name
      }
      if($serviceStatus -eq "Stopped" ) {
        Stop-Service $service.Name
      }
      # Wait for the service to reach the $serviceStatus or a maximum of specified time
      $service.WaitForStatus($serviceStatus, '00:01:20')
 }

 return $serviceStatus

}

function Log-Start {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LogName,

        [Parameter(Mandatory=$true)]
        [string]$ScriptVersion
    )

    Process{
      $logFullPath = Join-Path -Path $LogPath -ChildPath $LogName
      #Check if file exists and delete if it does
      If(!(Test-Path -Path $logFullPath)){
        New-Item -Path $LogPath -Value $LogName -ItemType File
      }

      Write-Log -LogPath $logFullPath -Message "Connect-RobotOrchestrator started for $env:computername" -Severity "Info"

    }
}

<#
  .SYNOPSIS
    Writes to a log file
  .DESCRIPTION
    Appends a new line to the end of the specified log file
  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log
  .PARAMETER LineValue
    Mandatory. The string that you want to write to the log
  .INPUTS
    Parameters above
  .OUTPUTS
    None
#>
function Write-Log
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Info','Warn','Error')]
        [string]$Severity = 'Info',

        [Parameter()]
        [boolean]$ExitGracefully
    )

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $logString = "$now $Severity message='$Message' env=$Environment timeStamp=$now level=$Severity pcName=$env:computername"
    Add-Content -Path $LogPath -Value $logString

    If ($ExitGracefully -eq $True){
        Log-Finish -LogPath $LogPath
        Break
    }
}

<#
  .SYNOPSIS
    Write closing logging data & exit
  .DESCRIPTION
    Writes finishing logging data to specified log and then exits the calling script
  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write finishing data to. Example: C:\Windows\Temp\Script.log
  .PARAMETER NoExit
    Optional. If this is set to True, then the function will not exit the calling script, so that further execution can occur
  .INPUTS
    Parameters above
  .OUTPUTS
    None
#>
function Log-Finish {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$false)]
        [string]$NoExit
    )

    Process{
      #Exit calling script if NoExit has not been specified or is set to False
      If(!($NoExit) -or ($NoExit -eq $False)){
        Exit
      }
    }
}

function Install-Filebeat {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("7.2.0")]
        [string]$FilebeatVersion
    )

    Write-Host "Trying to install filebeat version: $FilebeatVersion"
    Write-Log -LogPath $LogFile -Message "Trying to install filebeat version: $FilebeatVersion" -Severity 'Info'

    $beforeCd = Get-Location

    if ((Get-Service filebeat -ErrorAction SilentlyContinue)) {
        Write-Host "Filebeat already installed, attempting to uninstall"
        Write-Log -LogPath $LogFile -Message "Filebeat already installed, attempting to uninstall" -Severity 'Info'
        Try {
            Stop-Service filebeat
            cd 'C:\Program Files\Filebeat'
            PowerShell.exe -ExecutionPolicy UnRestricted -command ".\uninstall-service-filebeat.ps1" -ErrorAction Stop 
            cd $beforeCd
            Remove-Item 'C:\Program Files\Filebeat' -Recurse -Force -ErrorAction Stop
            Remove-Item 'C:\ProgramData\filebeat' -Recurse -Force -ErrorAction Stop            
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception uninstalling Filebeat: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Break
        } 
    }

    cd 'C:\Program Files\Filebeat'

    $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$FilebeatVersion-windows-x86.zip"
    Write-Host "Attempting to download Filebeat from: $url"
    Write-Log -LogPath $LogFile -Message "Attempting to download from $url" -Severity 'Info'
    $downloadedZip = "$InstallationPath\filebeat.zip"
    if (Test-Path $downloadedZip) {
        Remove-Item $downloadedZip -Recurse
    }
    Write-Host "Downloading to $downloadedZip"
    Write-Log -LogPath $LogFile -Message "Downloading to $downloadedZip" -Severity 'Info'

    Try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $downloadedZip)
        Test-Path $downloadedZip -ErrorAction Stop
    }
    Catch {
        Write-Host "There was an error downloading Filebeat: $_.Exception"
        Write-Log -LogPath $LogFile -Message "There was an error downloading Filebeat: $_.Exception" -Severity 'Error' -ExitGracefully $True
        Break
    }
    Try {
        Expand-Archive -Path $downloadedZip -DestinationPath 'C:\Program Files' -Force
    }
    Catch {
        Write-Host "There was an error unzipping Filebeat: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    }

    $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
    Try {
        Rename-Item -Path $unzippedFile -NewName 'Filebeat' -Force -ErrorAction Stop
        Remove-Item $unzippedFile -Recurse -Force -ErrorAction Stop
    }
    Catch {
        Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    }
    $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
    Remove-Item $filebeatYaml -Force
    $wc = New-Object System.Net.WebClient
    $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"
    Try {
        $wc.DownloadFile($configUri, $filebeatYaml) 
        Test-Path $filebeatYaml -ErrorAction Stop
    }
    Catch {
        Write-Host "There was an error downloading the filebeats config: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    }
    
    $serviceInstaller = "C:\Program Files\Filebeat\install-service-filebeat.ps1"
    Remove-Item $serviceInstaller -Force
    $wc = New-Object System.Net.WebClient
    $serviceInstallerUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/install-service-filebeat.ps1"
    Try {
        $wc.DownloadFile($serviceInstallerUri, $serviceInstaller) 
        Test-Path $serviceInstaller -ErrorAction Stop
    }
    Catch {
        Write-Host "There was an error downloading the filebeats config: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    }

    Write-Host "Humio Token is $HumioIngestToken"
    Try {
        PowerShell.exe -ExecutionPolicy UnRestricted -command ".\install-service-filebeat.ps1 -HumioIngestToken $HumioIngestToken" -ErrorAction Stop 
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception installing Filebeat: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    } 
    Try {
        Start-Service filebeat -ErrorAction Stop
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception starting the Filebeat service: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        Break
    }

    cd $beforeCd
}

Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Main
Log-Finish
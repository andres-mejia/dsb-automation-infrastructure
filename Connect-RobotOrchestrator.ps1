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
$sLogPath = "C:\Users\naku0510"
$sLogName = "Connect-Uipath-Robot.log"
$global:LogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
#Orchestrator SSL check
$orchSSLcheck = $false

function Main {        
    Process {

        $script:tempDirectory = (Join-Path $ENV:TEMP "Orchestration-Temp-$(Get-Date -f "yyyyMMddhhmmssfff")")
        New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

        Install-Filebeat -InstallationPath $script:tempDirectory -FilebeatVersion 7.2.0

        Write-Host "Logging to file $LogFile"
        Log-Write -LogPath $LogFile -LineValue "Logging to file $LogFile"

        #Log log log
        Write-Host "Connect Robot Orchestrator starts"
        Log-Write -LogPath $LogFile -LineValue "Connect Robot Orchestrator starts"

        Write-Host "Tenant is $tenant"
        Log-Write -LogPath $LogFile -LineValue "Tenant is $tenant"

        #Define TLS for Invoke-WebRequest
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if(!$orchSSLcheck) {
          [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }

        $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
        Write-Host "Robot exe is $robotExePath"
        Log-Write -LogPath $LogFile -LineValue "Robot exe is $robotExePath"

        if(!(Test-Path $robotExePath)) {
            Throw 'No robot exe was found on the $env:computername'
        } else {
          Write-Host "Robot exe found at $robotExePath"
          Log-Write -LogPath $LogFile -LineValue "Robot exe found at $robotExePath"
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

            Log-Write -LogPath $LogFile -LineValue "License key for $env:computername is: $RobotKey"
            Write-Host "License key for $env:computername is: $RobotKey"

            # Starting Robot
            Start-Process -filepath $robotExePath -verb runas

            $waitForRobotSVC = waitForService "UiPath Robot*" "Running"

            $env = "dev"
            $orchestratorUrl = "https://orchestrator-app-${Environment}.azure.dsb.dk"
            # if ($waitForRobotSVC -eq "Running") {
            # connect Robot to Orchestrator with Robot key
            Log-Write -LogPath $LogFile -LineValue "Orchestrator URL to connect to is: $orchestratorUrl"
            Write-Host "Orchestrator URL to connect to is: $orchestratorUrl"
            # if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
            Try {
                $connectRobot = Start-Process -FilePath $robotExePath -Verb runAs -ArgumentList "--connect -url $orchestratorUrl -key $RobotKey"
            }
            Catch {
                if ($_.Exception) {
                    Write-Host "There was an error running the robot.exe connect command, exception: $_.Exception"
                    Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
                }
                else {
                    Write-Host "There was an error running the robot.exe connect command, but the exception was empty"
                    Log-Error -LogPath $LogFile -ErrorDesc "There was an error, but it was blank" -ExitGracefully $True
                }
                Brea
            }
        }
        Catch {
            if ($_.Exception) {
                Write-Host "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
                Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            }
            else {
                Write-Host "There was an error connecting the machine to $orchMachines, but the exception was empty"
                Log-Error -LogPath $LogFile -ErrorDesc "There was an error, but it was blank" -ExitGracefully $True
            }
            Break
        }

        Write-Host "Removing temp directory $($script:tempDirectory)"
        Log-Write -LogPath $LogFile -LineValue "Removing temp directory $($script:tempDirectory)"
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        End {
            If($?){
              Write-Host "Completed Successfully."
                Log-Write -LogPath $LogFile -LineValue "Completed Successfully."
                Write-Host "Script is ending now."
                Log-Write -LogPath $LogFile -LineValue " "
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
      $sFullPath = $LogPath + "\" + $LogName

      #Check if file exists and delete if it does
      If(!(Test-Path -Path $sFullPath)){
        New-Item -Path $LogPath -Value $LogName -ItemType File
      }

      $now = Get-Date -Format "o"
      $logString = "$now Info {""message"": Connect-RobotOrchestrator started for $env:computername, ""timeStamp"": $now}"
      Add-Content -Path $LogPath -Value $logString 
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
function Log-Write {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LineValue
    )

    Process{
      $now = Get-Date -format "yyyy:MM:dd.ffff"
      $logString = "$now Info {""message"": ""$LineValue"", ""timeStamp"": ""$now"", ""level"": ""Info"", ""pcName"": ""$env:computername""}"
      Add-Content -Path $LogPath -Value $logString 

      #Write to screen for debug mode
      Write-Debug $LineValue
    }
}

<#
  .SYNOPSIS
    Writes an error to a log file
  .DESCRIPTION
    Writes the passed error to a new line at the end of the specified log file
  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log
  .PARAMETER ErrorDesc
    Mandatory. The description of the error you want to pass (use $_.Exception)
  .PARAMETER ExitGracefully
    Mandatory. Boolean. If set to True, runs Log-Finish and then exits script
  .INPUTS
    Parameters above
  .OUTPUTS
    None
#>
function Log-Error {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$ErrorDesc,

        [Parameter(Mandatory=$true)]
        [boolean]$ExitGracefully
    )

    Process{
      $now = Get-Date -format "yyyy:MM:dd.ffff"
      $logString = "$now Error {""message"": ""$ErrorDesc"", ""timeStamp"": ""$now"", ""level"": ""Error"", ""pcName"": ""$env:computername""}"
      Add-Content -Path $LogPath -Value $logString 

      #Write to screen for debug mode
      Write-Debug "Error: An error has occurred [$ErrorDesc]."

      #If $ExitGracefully = True then run Log-Finish and exit script
      If ($ExitGracefully -eq $True){
        Log-Finish -LogPath $LogPath
        Break
      }
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
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

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
    Log-Write -LogPath $LogFile -LineValue "Trying to install filebeat version: $FilebeatVersion"

    $beforeCd = Get-Location

    if (!(Get-Service filebeat -ErrorAction SilentlyContinue)) {
        $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$FilebeatVersion-windows-x86.zip"
        Write-Host "Attempting to download Filebeat from: $url"
        Log-Write -LogPath $LogFile -LineValue "Attempting to download from $url"
        
        $downloadedZip = "$InstallationPath\filebeat.zip"
        Write-Host "Downloading to $downloadedZip"
        Log-Write -LogPath $LogFile -LineValue "Downloading to $downloadedZip"

        Try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $downloadedZip)
        }
        Catch {
            Write-Host "There was an error downloading Filebeat: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        }

        $programFiles = "C:\Program Files"
        Try {
            Expand-Archive -Path $downloadedZip -DestinationPath $programFiles -Force
        }
        Catch {
            Write-Host "There was an error unzipping Filebeat: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        }

        $unzippedFile = "$programFiles\filebeat-$FilebeatVersion-windows-x86"
        $simpleName = "Filebeat"
        Try {
            Rename-Item -Path $unzippedFile -NewName $simpleName
            Remove-Item $unzippedFile -Recurse -Force
        }
        Catch {
            Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        }

        cd 'C:\Program Files\Filebeat'

        $filebeatYaml = "$programFiles\$simpleName\filebeat.yml"
        Remove-Item $filebeatYaml -Force
        $wc = New-Object System.Net.WebClient
        $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"
        Try {
            $wc.DownloadFile($configUri, $filebeatYaml)
        }
        Catch {
            Write-Host "There was an error downloading the filebeats config: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        }
        
        $serviceInstaller = "$programFiles\$simpleName\install-service-filebeat.ps1"
        Remove-Item $serviceInstaller -Force
        $wc = New-Object System.Net.WebClient
        $serviceInstallerUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/install-service-filebeat.ps1"
        Try {
            $wc.DownloadFile($serviceInstallerUri, $serviceInstaller)
        }
        Catch {
            Write-Host "There was an error downloading the filebeats config: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        }

        Write-Host "Humio Token is $HumioIngestToken"
        Try {
            PowerShell.exe -ExecutionPolicy UnRestricted -command ".\install-service-filebeat.ps1 -HumioIngestToken $HumioIngestToken" 
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
            Break
        } 
    } 
    else {
        Write-Host "Filebeat already installed"
        Log-Write -LogPath $LogFile -LineValue "Filebeat already installed"
    }

    Try {
        Start-Service filebeat -ErrorAction Stop
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception starting the Filebeat service: $_.Exception"
        Log-Error -LogPath $LogFile -ErrorDesc $_.Exception -ExitGracefully $True
        Break
    }

    cd $beforeCd
}

Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Main
Log-Finish -LogPath $LogFile
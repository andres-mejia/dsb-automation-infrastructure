function Start-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LogName
    )

    If (-Not (Test-Path $LogPath)) {
        Write-Host "There was no directory at $LogPath, trying to create it now"
        Try {
            New-Item -ItemType Directory -Path $LogPath -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Host "There was an error creating $LogPath"
            Throw "There was an error creating {$LogPath}: $_.Exception"
        }
    }
    $logFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    #Check if file exists and delete if it does
    If(-Not (Test-Path -Path $logFullPath)){
        Write-Host "There was no logfile at $logFullPath, trying to create it now"
        Try {
            New-Item -Path $LogPath -Name $LogName -ItemType File -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Host "There was an error creating $logFullPath"
            Throw "There was an error creating {$logFullPath}: $_.Exception"
        }
    }

    If(-Not (Test-Path -Path $logFullPath)){
        Throw "The log file should have been created but could not be found: $logFullPath"
    }
}

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
    Try {
        Add-Content -Path $LogPath -Value $logString
    }
    Catch {
        Write-Host "There was an error writing a log to $LogPath"
        Throw "There was an error creating {$LogPath}: $_.Exception"
    }

    If ($ExitGracefully -eq $True){
        Log-Finish
        Break
    }
}

function Finish-Log {

    [CmdletBinding()]

    param (
        [Parameter()]
        [string]$NoExit
    )

    Process{
      #Exit calling script if NoExit has not been specified or is set to False
      If(!($NoExit) -or ($NoExit -eq $False)){
        Exit
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

function Connect-RobotToOrchestrator {
    [CmdletBinding()]
        Param (
            [Parameter(Mandatory = $true)]
            [string] $LogPath,

            [Parameter(Mandatory = $true)]
            [string] $LogName,

            [Parameter(Mandatory = $true)]
            [string] $RobotKey,

            [Parameter(Mandatory = $true)]
            [string] $Environment
        )

    $fullLogPath = Join-Path -Path $LogPath -ChildPath $LogName
    Start-Log -LogPath $LogPath -LogName $LogName

    $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
    Write-Host "Robot exe is $robotExePath"
    Write-Log -LogPath $fullLogPath -Message "Robot exe is $robotExePath" -Severity 'Info'

    if(!(Test-Path $robotExePath)) {
        Throw "No robot exe was found on the $env:computername"
    } else {
        Write-Host "Robot exe found at $robotExePath"
        Write-Log -LogPath $fullLogPath -Message "Robot exe found at $robotExePath" -Severity 'Info'
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
        Write-Log -LogPath $fullLogPath -Message "License key for $env:computername is: $RobotKey" -Severity 'Info'
        Write-Host "License key for $env:computername is: $RobotKey"

        # Starting Robot
        Start-Process -filepath $robotExePath -verb runas

        $waitForRobotSVC = waitForService "UiPath Robot*" "Running"

        $env = "dev"
        $orchestratorUrl = "https://orchestrator-app-${Environment}.azure.dsb.dk"
        # if ($waitForRobotSVC -eq "Running") {
        # connect Robot to Orchestrator with Robot key
        Write-Log -LogPath $fullLogPath -Message "Orchestrator URL to connect to is: $orchestratorUrl" -Severity 'Info'
        Write-Host "Orchestrator URL to connect to is: $orchestratorUrl"
        # if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
        Try {
            Write-Log -LogPath $fullLogPath -Message "Running connection command" -Severity 'Info'
            Write-Host "Running connection command"
            $connectRobot = Start-Process -FilePath $robotExePath -Verb runAs -ArgumentList "--connect -url $orchestratorUrl -key $RobotKey" -Wait -NoNewWindow
        }
        Catch {
            if ($_.Exception) {
                Write-Host "There was an error running the robot.exe connect command, exception: $_.Exception"
                Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            }
            else {
                Write-Host "There was an error running the robot.exe connect command, but the exception was empty"
                Write-Log -LogPath $fullLogPath -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
            }
            Break
        }
    }
    Catch {
        if ($_.Exception) {
            Write-Host "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
        }
        else {
            Write-Host "There was an error connecting the machine to $orchMachines, but the exception was empty"
            Write-Log -LogPath $fullLogPath -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
            Throw "There was an error connecting the machine to $orchMachines, but the exception was empty"
        }
        Break
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
        Write-Host "Filebeat service already installed, attempting to stop service"
        Write-Log -LogPath $LogFile -Message "Filebeat service already installed, attempting to stop servcie" -Severity 'Info'
        Try {
            $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
            $service.StopService()
            Start-Sleep -s 1
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception stopping Filebeat service: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Break
        } 
    }
    else {
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
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        Write-Host "Expanding archive $downloadedZip"
        Write-Log -LogPath $LogFile -Message "Expanding archive $downloadedZip" -Severity 'Info'

        Try {
            Expand-Archive -Path $downloadedZip -DestinationPath 'C:\Program Files' -Force
        }
        Catch {
            Write-Host "There was an error unzipping Filebeat: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
        Write-Host "Renaming $unzippedFile to Filebeat"
        Write-Log -LogPath $LogFile -Message "Renaming $unzippedFile to Filebeat" -Severity 'Info'
        
        Try {
            Rename-Item -Path $unzippedFile -NewName 'Filebeat' -Force -ErrorAction Stop
            if (Test-Path $unzippedFile) {
                Remove-Item $unzippedFile -Recurse -Force -ErrorAction Stop
            }
        }
        Catch {
            Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw "There was an error renaming unzipped Filebeat dir: $_.Exception"
        }

        Write-Host "Retrieving installer script"
        Write-Log -LogPath $LogFile -Message "Retrieving installer script" -Severity 'Info'

        $serviceInstaller = "C:\Program Files\Filebeat\install-service-filebeat.ps1"
        Remove-Item $serviceInstaller -Force
        $wc = New-Object System.Net.WebClient
        $serviceInstallerUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/install-service-filebeat.ps1"
        Try {
            $wc.DownloadFile($serviceInstallerUri, $serviceInstaller) 
            if (-not (Test-Path $serviceInstaller)) {
                throw [System.IO.FileNotFoundException] "$serviceInstaller not found."
            }
        }
        Catch {
            Write-Host "There was an error downloading the filebeats config: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw [System.IO.Exception] $_.Exception
        }

        Write-Host "Attempting to install Filebeats"
        Write-Log -LogPath $LogFile -Message "Attempting to install Filebeats" -Severity 'Info'

        Write-Host "Humio Token is $HumioIngestToken"
        Try {
            cd 'C:\Program Files\Filebeat'
            PowerShell.exe -ExecutionPolicy UnRestricted -command ".\install-service-filebeat.ps1 -HumioIngestToken '$HumioIngestToken'" -ErrorAction Stop 
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw [System.IO.Exception] $_.Exception
        } 

    }

    Write-Host "Retrieving filebeats config"
    Write-Log -LogPath $LogFile -Message "Retrieving filebeats config" -Severity 'Info'
    
    $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
    Remove-Item $filebeatYaml -Force
    $wc = New-Object System.Net.WebClient
    $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"
    Try {
        $wc.DownloadFile($configUri, $filebeatYaml) 
        if (-not (Test-Path $filebeatYaml)) {
             throw [System.IO.FileNotFoundException] "$filebeatYaml not found."
        }
    }
    Catch {
        Write-Host "There was an error downloading the filebeats config: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        throw $_.Exception
    }

    Try {
    
    Write-Host "Trying to start Filebeat service"
        Write-Log -LogPath $LogFile -Message "Trying to start Filebeat service" -Severity 'Info'
        Start-Service filebeat -ErrorAction Stop
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception starting the Filebeat service: $_.Exception"
        Write-Log -LogPath $LogFile -Message "There was an exception starting the Filebeat service: $_.Exception" -Severity 'Error' -ExitGracefully $True
        throw "There was an exception starting the Filebeat service: $_.Exception"
    }

    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    if ($service.State -eq "Running") {
        Write-Host "Filebeat Service started successfully"
        Write-Log -LogPath $LogFile -Message "Filebeat Service started successfully" -Severity 'Info'
    }
    else {
        cd $beforeCd
        Write-Host "Filebeats service is not running correctly"
        Write-Log -LogPath $LogFile -Message "Filebeats service is not running correctly" -Severity 'Error'
        Throw "Filebeats service is not running correctly"
    }

    cd $beforeCd
}

function install-service-filebeat {
    [CmdletBinding()]
        Param (
            [Parameter(Mandatory = $true)]
            [string] $HumioIngestToken
        )

    # Delete and stop the service if it already exists.
    if (Get-Service filebeat -ErrorAction SilentlyContinue) {
    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    $service.StopService()
    Start-Sleep -s 1
    $service.delete()
    }

    $workdir = Split-Path $MyInvocation.MyCommand.Path
    $elasticToken = "output.elasticsearch.password=$HumioIngestToken"
    Write-Host "Elastic setting is $elasticToken"
    # Create the new service.
    New-Service -name filebeat `
    -displayName Filebeat `
    -binaryPathName "`"$workdir\filebeat.exe`" -c `"$workdir\filebeat.yml`" -path.home `"$workdir`" -path.data `"C:\ProgramData\filebeat`" -path.logs `"C:\ProgramData\filebeat\logs`" -E `"output.elasticsearch.password=AwhoOLTo8KsRv6S3IIbQvUxR4uyw3tvQY8YVmHIkqoCk`""

    # Attempt to set the service to delayed start using sc config.
    Try {
    Start-Process -FilePath sc.exe -ArgumentList 'config filebeat start=delayed-auto'
    }
    Catch { Write-Host "An error occured setting the service to delayed start." -ForegroundColor Red }
}

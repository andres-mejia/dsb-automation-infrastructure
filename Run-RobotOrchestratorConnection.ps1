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

$script:ErrorActionPreference = "SilentlyContinue"
$script:sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$script:sDebug = $true
#Log File Info
$script:sLogPath = "C:\ProgramData\AutomationAzureOrchestration"
$script:overallLog = "Run-Robot-Orchestrator-Connection-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$script:LogFile = Join-Path -Path $sLogPath -ChildPath $overallLog
# Orchestration script directory
$script:orchestrationDir = "C:\Program Files\WindowsPowerShell\Modules\RobotOrchestration"
$script:scheduledTaskScript = "Connect-Robot-Orchestrator-$(Get-Date -f "yyyyMMddhhmmssfff").log"
#Orchestrator SSL check
$sslCheck = $false

function Main {
    Begin {
        #Define TLS for Invoke-WebRequest
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if(!$sslCheck) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }

        $script:tempDirectory = (Join-Path "C:\Users\Public" "Orchestration-Temp-$(Get-Date -f "yyyyMMddhhmmssfff")")
        Write-Host "Saving all temporary files to $script:tempDirectory"
        New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

        If (-Not (Test-Path $orchestrationDir)) {
            Write-Host "Creating program file dir at: $orchestrationDir"
            New-Item -ItemType Directory -Path $orchestrationDir
        }
        
        $p = [Environment]::GetEnvironmentVariable("PSModulePath")
        $p += ";C:\Program Files\WindowsPowerShell\Modules\"
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)

        $wc = New-Object System.Net.WebClient
        $orchModule = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/RobotOrchestration.psm1"
        Write-Host "Attempting to download file from from: $orchModule"
        $orchModuleDownload = "$orchestrationDir\RobotOrchestration.psm1"
        $wc.DownloadFile($orchModule, $orchModuleDownload)        
        
        Import-Module RobotOrchestration

        # Downloading Log files
        $wc = New-Object System.Net.WebClient
        $startLogUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Start-Log.ps1"
        Write-Host "Attempting to download file from from: $startLogUri"
        $startLogDownload = "$orchestrationDir\Start-Log.ps1"
        $wc.DownloadFile($startLogUri, $startLogDownload)        

        $writeLogUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Write-Log.ps1"
        Write-Host "Attempting to download file from from: $writeLogUri"
        $writeLogDownload = "$orchestrationDir\Write-Log.ps1"
        $wc.DownloadFile($writeLogUri, $writeLogDownload)

        $finishLogUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Finish-Log.ps1"
        Write-Host "Attempting to download file from from: $finishLogUri"
        $finishLogDownload = "$orchestrationDir\Finish-Log.ps1"
        $wc.DownloadFile($finishLogUri, $finishLogDownload)

        $connectRobot = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Connect-RobotToOrchestrator.ps1"
        Write-Host "Attempting to download file from from: $connectRobot"
        $connectRobotDownload = "$orchestrationDir\Connect-RobotToOrchestrator.ps1"
        $wc.DownloadFile($connectRobot, $connectRobotDownload)

        . "orchestrationDir\Start-Log.ps1"
        . ".\orchestrationDir\Start-Log.ps1"
        . "orchestrationDir\Write-Log.ps1"
        . ".\orchestrationDir\Write-Log.ps1"
        . "orchestrationDir\Finish-Log.ps1"
        . ".\orchestrationDir\Finish-Log.ps1"
        . "orchestrationDir\Connect-RobotToOrchestrator.ps1"
        . ".\orchestrationDir\Connect-RobotToOrchestrator.ps1"

        Try {
            ./Start-Log -LogPath $sLogPath -LogName $overallLog -ErrorAction Stop
        }
        Catch {
            ./Write-Host "There was an error creating logfile: $_.Exception"
            Throw "There was an error creating logfile: $_.Exception"
            Break
        }
        ./Write-Log -LogPath $LogFile -Message "Saving all temporary files to $script:tempDirectory" -Severity 'Info'
    }   

    Process {
        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity 'Info'

        Write-Host "Connect Robot Orchestrator starts"
        ./Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity 'Info'

        Write-Host "Tenant is $tenant"
        ./Write-Log -LogPath $LogFile -Message "Tenant is $tenant" -Severity 'Info'
        
        Write-Host "Trying to install Filebeat"
        ./Write-Log -LogPath $LogFile -Message "Trying to install Filebeat" -Severity 'Info'

        Try {
            Install-Filebeat -InstallationPath $script:tempDirectory -FilebeatVersion 7.2.0
        }
        Catch {
            Write-Host "There was an error trying to install Filebeats, exception: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw 'There was a problem installing Filebeats'
        }

        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        Write-Host "Try running robot connection script"
        Try {
            ./Connect-RobotToOrchestrator -LogPath $sLogPath -LogName $scheduledTaskScript -RobotKey $RobotKey -Environment $Environment -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error trying to run robot connection script, exception: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
        }

        End {
            If($?){
                Write-Host "Completed Successfully."
                ./Write-Log -LogPath $LogFile -Message "Completed Successfully." -Severity 'Info'
                Write-Host "Script is ending now."
            }
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
    ./Write-Log -LogPath $LogFile -Message "Trying to install filebeat version: $FilebeatVersion" -Severity 'Info'

    $beforeCd = Get-Location

    if ((Get-Service filebeat -ErrorAction SilentlyContinue)) {
        Write-Host "Filebeat service already installed, attempting to stop service"
        ./Write-Log -LogPath $LogFile -Message "Filebeat service already installed, attempting to stop servcie" -Severity 'Info'
        Try {
            $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
            $service.StopService()
            Start-Sleep -s 1
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception stopping Filebeat service: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Break
        } 
    }
    else {
        cd 'C:\Program Files\Filebeat'

        $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$FilebeatVersion-windows-x86.zip"
        Write-Host "Attempting to download Filebeat from: $url"
        ./Write-Log -LogPath $LogFile -Message "Attempting to download from $url" -Severity 'Info'
        $downloadedZip = "$InstallationPath\filebeat.zip"
        if (Test-Path $downloadedZip) {
            Remove-Item $downloadedZip -Recurse
        }
        Write-Host "Downloading to $downloadedZip"
        ./Write-Log -LogPath $LogFile -Message "Downloading to $downloadedZip" -Severity 'Info'

        Try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $downloadedZip)
            Test-Path $downloadedZip -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error downloading Filebeat: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message "There was an error downloading Filebeat: $_.Exception" -Severity 'Error' -ExitGracefully $True
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        Write-Host "Expanding archive $downloadedZip"
        ./Write-Log -LogPath $LogFile -Message "Expanding archive $downloadedZip" -Severity 'Info'

        Try {
            Expand-Archive -Path $downloadedZip -DestinationPath 'C:\Program Files' -Force
        }
        Catch {
            Write-Host "There was an error unzipping Filebeat: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
        Write-Host "Renaming $unzippedFile to Filebeat"
        ./Write-Log -LogPath $LogFile -Message "Renaming $unzippedFile to Filebeat" -Severity 'Info'
        
        Try {
            Rename-Item -Path $unzippedFile -NewName 'Filebeat' -Force -ErrorAction Stop
            if (Test-Path $unzippedFile) {
                Remove-Item $unzippedFile -Recurse -Force -ErrorAction Stop
            }
        }
        Catch {
            Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw "There was an error renaming unzipped Filebeat dir: $_.Exception"
        }

        Write-Host "Retrieving installer script"
        ./Write-Log -LogPath $LogFile -Message "Retrieving installer script" -Severity 'Info'

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
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw [System.IO.Exception] $_.Exception
        }

        Write-Host "Attempting to install Filebeats"
        ./Write-Log -LogPath $LogFile -Message "Attempting to install Filebeats" -Severity 'Info'

        Write-Host "Humio Token is $HumioIngestToken"
        Try {
            cd 'C:\Program Files\Filebeat'
            PowerShell.exe -ExecutionPolicy UnRestricted -command ".\install-service-filebeat.ps1 -HumioIngestToken '$HumioIngestToken'" -ErrorAction Stop 
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            throw [System.IO.Exception] $_.Exception
        } 

    }

    # if (Test-Path 'C:\Program Files\Filebeat') {
    #     Write-Host "Filebeat folder still exists, trying to delete it"
    #     ./Write-Log -LogPath $LogFile -Message "Filebeat folder still exists, trying to delete it" -Severity 'Info'
    #     Try {
    #         Remove-Item 'C:\Program Files\Filebeat' -Recurse -Force -ErrorAction Stop
    #         # if (Test-Path 'C:\ProgramData\filebeat') {
    #         #     Remove-Item 'C:\ProgramData\filebeat' -Recurse -Force -ErrorAction Stop            
    #         # }
    #     }
    #     Catch {
    #         Write-Host "There was an exception uninstalling Filebeat: $_.Exception"
    #         ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
    #         Break
    #     } 
    # }

    Write-Host "Retrieving filebeats config"
    ./Write-Log -LogPath $LogFile -Message "Retrieving filebeats config" -Severity 'Info'
    
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
        ./Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        throw $_.Exception
    }

    Try {
    
    Write-Host "Trying to start Filebeat service"
        ./Write-Log -LogPath $LogFile -Message "Trying to start Filebeat service" -Severity 'Info'
        Start-Service filebeat -ErrorAction Stop
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception starting the Filebeat service: $_.Exception"
        ./Write-Log -LogPath $LogFile -Message "There was an exception starting the Filebeat service: $_.Exception" -Severity 'Error' -ExitGracefully $True
        throw "There was an exception starting the Filebeat service: $_.Exception"
    }

    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    if ($service.State -eq "Running") {
        Write-Host "Filebeat Service started successfully"
        ./Write-Log -LogPath $LogFile -Message "Filebeat Service started successfully" -Severity 'Info'
    }
    else {
        cd $beforeCd
        Write-Host "Filebeats service is not running correctly"
        ./Write-Log -LogPath $LogFile -Message "Filebeats service is not running correctly" -Severity 'Error'
        Throw "Filebeats service is not running correctly"
    }

    cd $beforeCd
}

Main
./Finish-Log -NoExit
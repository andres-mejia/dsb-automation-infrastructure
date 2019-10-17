[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("6.8.1","7.2.0")]
        [string] $FilebeatVersion,

        [Parameter(Mandatory = $true)]
        [string] $OrchestratorUrl,

        [Parameter(Mandatory = $true)]
        [string] $OrchestratorApiUrl,

        [Parameter(Mandatory = $true)]
        [string] $OrchestratorTenant,

        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken,

        [Parameter(Mandatory = $true)]
        [string] $NugetFeedUrl,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountKey,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountContainer
)

$script:ErrorActionPreference = "SilentlyContinue"
$script:sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$script:sDebug = $true
#Log File Info
$script:connectRoboPath = "C:\Program Files\AutomationAzureOrchestration"
$script:sLogPath = "C:\ProgramData\AutomationAzureOrchestration"
$script:overallLog = "Run-Robot-Orchestrator-Connection-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$script:LogFile = Join-Path -Path $sLogPath -ChildPath $overallLog
# Orchestration script directory
$script:orchModuleDir = "C:\Program Files\WindowsPowerShell\Modules\Dsb.RobotOrchestration"
$script:scheduledTaskScript = "Connect-Robot-Orchestrator-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$script:installFilebeatScript = "Install-Filebeat-$(Get-Date -f "yyyyMMddhhmmssfff").log"
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

        If (-Not (Test-Path $orchModuleDir)) {
            Write-Host "Creating program file dir at: $orchModuleDir"
            New-Item -ItemType Directory -Path $orchModuleDir
        }

        If (-Not (Test-Path $connectRoboPath)) {
            Write-Host "Creating connect robo dir at: $connectRoboPath"
            New-Item -ItemType Directory -Path $connectRoboPath
        }

        $orchModule = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Dsb.RobotOrchestration.psm1"
        Write-Host "Attempting to download file from from: $orchModule"
        $orchModuleDownload = "$orchModuleDir\Dsb.RobotOrchestration.psm1"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($orchModule, $orchModuleDownload)

        $installRobo = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Install-UiPath.ps1"
        Write-Host "Attempting to download file from from: $installRobo"
        $script:installRoboDownload = "$connectRoboPath\Install-UiPath.ps1"
        $wc.DownloadFile($installRobo, $installRoboDownload)        

        $connectRobo = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Connect-RobotToOrchestrator.ps1"
        Write-Host "Attempting to download file from from: $connectRobo"
        $script:connectRoboDownload = "$connectRoboPath\Connect-RobotToOrchestrator.ps1"
        $wc.DownloadFile($connectRobo, $connectRoboDownload)        

        $sendSms = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Get-SendSmsBlob.ps1"
        Write-Host "Attempting to download file from from: $sendSms"
        $script:getSendSmsBlob = "$connectRoboPath\Get-SendSmsBlob.ps1"
        $wc.DownloadFile($sendSms, $getSendSmsBlob)       

        $p = [Environment]::GetEnvironmentVariable("PSModulePath")
        $p += ";C:\Program Files\WindowsPowerShell\Modules\"
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
        
        If (Get-Module Dsb.RobotOrchestration) {
            Remove-Module Dsb.RobotOrchestration
        } 
        
        Import-Module Dsb.RobotOrchestration

        Try {
            Start-Log -LogPath $sLogPath -LogName $overallLog -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error creating logfile: $_.Exception"
            Throw "There was an error creating logfile: $_.Exception"
            Break
        }
        Write-Log -LogPath $LogFile -Message "Saving all temporary files to $script:tempDirectory" -Severity "Info"
    }   

    Process {
        Write-Host "Username for user running this script is: $env:username"
        Write-Log -LogPath $LogFile -Message "Username for user running this script is: $env:username" -Severity "Info"
        
        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity "Info"

        Write-Host "Connect Robot Orchestrator starts"
        Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity "Info"

        Write-Host "Tenant is $OrchestratorTenant"
        Write-Log -LogPath $LogFile -Message "Tenant is $OrchestratorTenant" -Severity "Info"
        
        Write-Host "Trying to install Filebeat"
        Write-Log -LogPath $LogFile -Message "Trying to install Filebeat" -Severity "Info"
        Try {
            Install-Filebeat -LogPath $sLogPath -LogName $installFilebeatScript -DownloadPath $script:tempDirectory -FilebeatVersion 7.2.0 -HumioIngestToken $HumioIngestToken -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error trying to install Filebeats, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message "There was an error trying to install Filebeats, exception: $_.Exception" -Severity "Error"
        }

        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        Write-Host "Attempting to schedule robot connection script located at: $connectRoboDownload"
        Write-Log -LogPath $LogFile -Message "Attempting to schedule robot connection script located at: $connectRoboDownload" -Severity "Info"        
        $jobName = 'ConnectUiPathRobotOrchestrator'
        $existingJobs = Get-ScheduledTask
        
        ForEach ($job in $existingJobs) {
            If ($job.Name -eq $jobName) {
                Write-Host "The job with name: $jobName existed, unregistering now"
                Write-Log -LogPath $LogFile -Message "The job with name: $jobName existed, unregistering now" -Severity "Info"
                Unregister-ScheduledTask $jobName
            }
        }

        Write-Host "Trying to install UiPath"
        Write-Log -LogPath $LogFile -Message "Trying to install UiPath" -Severity "Info"
        Try {
            & $installRoboDownload -studioVersion 19.4.3 -robotType Nonproduction -ErrorAction Stop
            Wait-ForService "UiPath Robot*" "00:01:20"
        }
        Catch {
            Write-Host "There was an error trying to install UiPath, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw "There was an error trying to install UiPath, exception: $_.Exception"
            Break
        }
        
        Write-Host "Trying to run robot connection script"
        Write-Log -LogPath $LogFile -Message "Trying to run robot connection script" -Severity "Info"
        Try {
            & $connectRoboDownload -LogPath $sLogPath -LogName $scheduledTaskScript -OrchestratorUrl $OrchestratorUrl -OrchestratorApiUrl $OrchestratorApiUrl -OrchestratorTenant $OrchestratorTenant -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error trying to run robot connection script, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
            Break
        }

        Write-Host "Trying to add nuget feed"
        Write-Log -LogPath $LogFile -Message "Trying to add nuget feed" -Severity "Info"
        
        Try {
            $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
            $rootPath = "C:"
            $nugetExe = "$rootPath/nuget.exe"
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($nugetUrl, $nugetExe)
            Set-Alias nuget $nugetExe -Scope Global -Verbose
            nuget sources Add -Name "Nuget-prod" -Source $NugetFeedUrl
            nuget sources Add -Name "Nuget-prod" -Source $NugetFeedUrl -configfile "C:\Program Files (x86)\UiPath\Studio\NuGet.Config"
        }
        Catch {
            Write-Host "There was an error trying add Nuget feed, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw "There was an error trying add Nuget feed, exception: $_.Exception"
            Break
        }

        Try {
            & $getSendSmsBlob -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
        }
        Catch {
            
        }
        
    }
    End {
        Write-Host "Run-RobotOrchestrationConnection script has finished running. Exiting now"
        Write-Log -LogPath $LogFile -Message "Run-RobotOrchestrationConnection script has finished running. Exiting now" -Severity "Info"        
    }
}

Main
Finish-Log
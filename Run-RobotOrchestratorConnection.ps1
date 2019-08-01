[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("6.8.1","7.2.0")]
        [string] $FilebeatVersion,

        [Parameter(Mandatory = $true)]
        [string] $RobotKey,

        [Parameter(Mandatory = $true)]
        [string] $OrchestratorUrl,

        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken
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

        $wc = New-Object System.Net.WebClient
        $orchModule = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Dsb.RobotOrchestration.psm1"
        Write-Host "Attempting to download file from from: $orchModule"
        $orchModuleDownload = "$orchModuleDir\Dsb.RobotOrchestration.psm1"
        $wc.DownloadFile($orchModule, $orchModuleDownload)     

        $connectRobo = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Connect-RobotToOrchestrator.ps1"
        Write-Host "Attempting to download file from from: $connectRobo"
        $script:connectRoboDownload = "$connectRoboPath\Connect-RobotToOrchestrator.ps1"
        $wc.DownloadFile($connectRobo, $connectRoboDownload)        

        $p = [Environment]::GetEnvironmentVariable("PSModulePath")
        $p += ";C:\Program Files\WindowsPowerShell\Modules\"
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
        
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
        Write-Host "User is: $env:username"
        Write-Log -LogPath $LogFile -Message "User is: $env:username" -Severity "Info"
        
        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity "Info"

        Write-Host "Connect Robot Orchestrator starts"
        Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity "Info"

        Write-Host "Tenant is $tenant"
        Write-Log -LogPath $LogFile -Message "Tenant is $tenant" -Severity "Info"
        
        Write-Host "Trying to install Filebeat"
        Write-Log -LogPath $LogFile -Message "Trying to install Filebeat" -Severity "Info"

        Try {
            Install-Filebeat -LogPath $sLogPath -LogName $installFilebeatScript -InstallationPath $script:tempDirectory -FilebeatVersion 7.2.0
        }
        Catch {
            Write-Host "There was an error trying to install Filebeats, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw 'There was a problem installing Filebeats'
        }

        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        Write-Host "Attempting to schedule robot connection script located at: $connectRoboDownload"
        Write-Log -LogPath $LogFile -Message "Attempting to schedule robot connection script located at: $connectRoboDownload" -Severity "Info"        
        $jobName = 'ConnectUiPathRobotOrchestrator'

        Try {
            $cmdArgList = @{
                "-LogPath" = $sLogPath;
                "-LogName" = $scheduledTaskScript;
                "-OrchestratorUrl" = $OrchestratorUrl;
                "-RobotKey" = "$RobotKey";
            }
            Write-Host "Command argument list is: $cmdArgList"
            $repeat = (New-TimeSpan -Minutes 5)
            $trigger = New-JobTrigger -Once -At (Get-Date).Date -RepeatIndefinitely -RepetitionInterval $repeat
            $invokeScriptContent = {   
                param($scriptPath, $logPath, $logName, $orchestratorUrl, $robotKey)
                & $scriptPath -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -RobotKey $robotKey
            }
            Register-ScheduledJob -Name $jobName -ScriptBlock $invokeScriptContent -ArgumentList $connectRoboDownload,$sLogPath,$scheduledTaskScript,$OrchestratorUrl,$RobotKey -Trigger $trigger
        }
        Catch {
            Write-Host "Scheduling the connection job failed, reason: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
            Break
        }
        
        $retrievedScheduledJob = Get-ScheduledJob $jobName
        $runJob = $retrievedScheduledJob.Run()
        If ($runJob.ChildJobs[0].JobStateInfo.State -eq "Failed") {
            $failureReason = $runJob.ChildJobs[0].JobStateInfo.Reason.ToString()
            Write-Host "Running the connection job failed, reason: $failureReason"
            Write-Log -LogPath $LogFile -Message "Running the connection job failed, reason: $failureReason" -Severity "Error"
            Throw "Running the connection job failed, reason: $runJob.ChildJobs[0].JobStateInfo.Reason"
        }

        Write-Host "Creating scheduled job did not throw error."
        Write-Log -LogPath $LogFile -Message "Creating scheduled job did not throw error." -Severity "Info"

        End {
            Write-Host "$MyInvocation.MyCommand.Name finished without throwing error"
            Write-Log -LogPath $LogFile -Message "$MyInvocation.MyCommand.Name finished without throwing error" -Severity "Info"
            Write-Host "$MyInvocation.MyCommand.Name is exiting"
            Write-Log -LogPath $LogFile -Message "$MyInvocation.MyCommand.Name is exiting" -Severity "Info"        
        }
    }
}

Main
Finish-Log
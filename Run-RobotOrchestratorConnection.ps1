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
        [string] $OrchestratorTenant,

        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken,
        
        [Parameter(Mandatory = $true)]
        [string] $AdminPassword
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

        $connectRobo = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Connect-RobotToOrchestrator.ps1"
        Write-Host "Attempting to download file from from: $connectRobo"
        $script:connectRoboDownload = "$connectRoboPath\Connect-RobotToOrchestrator.ps1"
        $wc.DownloadFile($connectRobo, $connectRoboDownload)        

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
        Write-Host "User is: $env:username"
        Write-Log -LogPath $LogFile -Message "User is: $env:username" -Severity "Info"
        
        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity "Info"

        Write-Host "Connect Robot Orchestrator starts"
        Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity "Info"

        Write-Host "Tenant is $OrchestratorTenant"
        Write-Log -LogPath $LogFile -Message "Tenant is $OrchestratorTenant" -Severity "Info"
        
        Write-Host "Attempting to schedule robot connection script located at: $connectRoboDownload"
        Write-Log -LogPath $LogFile -Message "Attempting to schedule robot connection script located at: $connectRoboDownload" -Severity "Info"        
        $jobName = 'ConnectUiPathRobotOrchestrator'
        $existingJobs = Get-ScheduledJob
        
        ForEach ($job in $existingJobs) {
            If ($job.Name -eq $jobName) {
                Write-Host "The job with name: $jobName existed, unregistering now"
                Write-Log -LogPath $LogFile -Message "The job with name: $jobName existed, unregistering now" -Severity "Info"
                Unregister-ScheduledJob $jobName
            }
        }

        Write-Host "Trying to run robot connection script"
        Write-Log -LogPath $LogFile -Message "Trying to run robot connection script" -Severity "Info"
        Try {
            & $connectRoboDownload -LogPath $sLogPath -LogName $scheduledTaskScript -RobotKey $RobotKey -OrchestratorUrl $OrchestratorUrl -OrchestratorTenant $OrchestratorTenant -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error trying to run robot connection script, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity "Error"
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
            Break
        }
        
        Try {
            Write-Host "Trying to register robot connection as a scheduled job"
            Write-Log -LogPath $LogFile -Message "Trying to register robot connection as a scheduled job" -Severity "Info"
            $repeat = (New-TimeSpan -Minutes 5)
            $trigger = New-JobTrigger -Once -At (Get-Date).Date -RepeatIndefinitely -RepetitionInterval $repeat
            $invokeScriptContent = {   
                param($scriptPath, $logPath, $logName, $orchestratorUrl, $orchestratorTenant, $robotKey)
                & $scriptPath -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorTenant $orchestratorTenant -RobotKey $robotKey
            }
            $user = "local\administrator"
            $password = $AdminPassword | ConvertTo-SecureString -AsPlainText -Force
            $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password
            $options = New-ScheduledJobOption -RunElevated
            Register-ScheduledJob -Name $jobName -ScriptBlock $invokeScriptContent -ArgumentList $connectRoboDownload,$sLogPath,$scheduledTaskScript,$OrchestratorUrl,$OrchestratorTenant,$RobotKey -Trigger $trigger -ScheduledJobOption $options -Credential $credential -ErrorAction Stop
        }
        Catch {
            Write-Host "Scheduling the connection job failed, reason: $_.Exception"
            Write-Log -LogPath $LogFile -Message "Scheduling the connection job failed, reason: $_.Exception" -Severity "Error"
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
            Break
        }

        Write-Host "Trying to install Filebeat"
        Write-Log -LogPath $LogFile -Message "Trying to install Filebeat" -Severity "Info"
        Try {
            Install-Filebeat -LogPath $sLogPath -LogName $installFilebeatScript -DownloadPath $script:tempDirectory -FilebeatVersion 7.2.0 -HumioIngestToken $HumioIngestToken
        }
        Catch {
            Write-Host "There was an error trying to install Filebeats, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message "There was an error trying to install Filebeats, exception: $_.Exception" -Severity "Error"
            Throw 'There was a problem installing Filebeats'
            break
        }

        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        Write-Host "Attempting to retrieve the scheduled job just created."
        Write-Log -LogPath $LogFile -Message "Attempting to retrieve the scheduled job just created." -Severity "Info"
        $retrievedScheduledJob = Get-ScheduledJob $jobName

        If ($retrievedScheduledJob -eq $null) {
            Write-Host "Retrieving the scheduled job returned null"
            Write-Log -LogPath $LogFile -Message "Retrieving the scheduled job returned null" -Severity "Error"
            Throw "Scheduled orchestrator connection job did not exist"
            Break
        }

        $runJob = $retrievedScheduledJob.Run()
        If ($runJob.ChildJobs[0].JobStateInfo.State -eq "Failed") {
            $failureReason = $runJob.ChildJobs[0].JobStateInfo.Reason.ToString()
            Write-Host "Running the connection job failed, reason: $failureReason"
            Write-Log -LogPath $LogFile -Message "Running the connection job failed, reason: $failureReason" -Severity "Error"
            Throw "Running the connection job failed, reason: $runJob.ChildJobs[0].JobStateInfo.Reason"
            Break
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
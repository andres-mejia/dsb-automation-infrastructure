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
        
        [string] $AdminUser,
        [string] $AdminPassword,
        [string] $AdminDomain
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
        # $wc.DownloadFile($orchModule, $orchModuleDownload)

        $installRobo = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Install-UiPath.ps1"
        Write-Host "Attempting to download file from from: $installRobo"
        $script:installRoboDownload = "$connectRoboPath\Install-UiPath.ps1"
        $wc.DownloadFile($installRobo, $installRoboDownload)        

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
            Wait-ForService "UiPath Robot*" "Running" "00:01:20"        
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

            $domainUser = "$AdminDomain\$AdminUser"
            Write-Host "Domain user is: $domainUser"
            Write-Log -LogPath $LogFile -Message "Username is: $AdminUser" -Severity "Info"

            $repeat = (New-TimeSpan -Minutes 5)
            $trigger = New-JobTrigger -Once -At (Get-Date).Date -RepeatIndefinitely -RepetitionInterval $repeat
            $invokeScriptContent = {   
                param($scriptPath, $logPath, $logName, $orchestratorUrl, $orchestratorTenant, $robotKey)
                & $scriptPath -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorTenant $orchestratorTenant -RobotKey $robotKey
            }
            $password = $AdminPassword | ConvertTo-SecureString -AsPlainText -Force
            $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $domainUser, $password
            $options = New-ScheduledJobOption -RunElevated
            # Register-ScheduledJob -Name $jobName -ScriptBlock $invokeScriptContent -ArgumentList $connectRoboDownload,$sLogPath,$scheduledTaskScript,$OrchestratorUrl,$OrchestratorTenant,$RobotKey -Trigger $trigger # -ScheduledJobOption $options -Credential $credential -ErrorAction Stop
            
            Write-Host "Connect robot to orchestrator script is located: $connectRoboDownload"
            $triggerAction = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval $repeat -RepetitionDuration ([System.TimeSpan]::MaxValue)
            $powershellArg = "& '$connectRoboDownload' -LogPath '$sLogPath' -LogName '$scheduledTaskScript' -RobotKey '$RobotKey' -OrchestratorUrl '$OrchestratorUrl' -OrchestratorTenant '$OrchestratorTenant'" #-ExecutionPolicy Bypass
            Write-Host "Powershell arg is: $powershellArg"
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $powershellArg
            # $action = New-ScheduledTaskAction -Execute powershell.exe -Argument "-ScriptBlock $invokeScriptContent -ArgumentList $connectRoboDownload,$sLogPath,$scheduledTaskScript,$OrchestratorUrl,$OrchestratorTenant,$RobotKey"
            Register-ScheduledTask -TaskName $jobName -Trigger $triggerAction -Action $action -Force -ErrorAction Stop #-User $domainUser -Password $AdminPassword -RunLevel Highest
        }
        Catch {
            Write-Host "Scheduling the connection job failed, reason: $_.Exception"
            Write-Log -LogPath $LogFile -Message "Scheduling the connection job failed, reason: $_.Exception" -Severity "Error"
        }

        Write-Host "Attempting to retrieve the scheduled job just created."
        Write-Log -LogPath $LogFile -Message "Attempting to retrieve the scheduled job just created." -Severity "Info"
        Try {
            $retrievedScheduledTask = Get-ScheduledTask $jobName -ErrorAction Stop
            Start-ScheduledTask -TaskName $jobName -ErrorAction Stop            
            Write-Host "Creating scheduled job did not throw error."
            Write-Log -LogPath $LogFile -Message "Creating scheduled job did not throw error." -Severity "Info"
        }
        Catch {
            Write-Host "Finding and trying to run the scheduled task raised exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message "Finding and trying to run the scheduled task raised exception: $_.Exception" -Severity "Error"
        }
    }
    End {
        Write-Host "Run-RobotOrchestrationConnection script has finished running. Exiting now"
        Write-Log -LogPath $LogFile -Message "Run-RobotOrchestrationConnection script has finished running. Exiting now" -Severity "Info"        
    }
}

Main
Finish-Log
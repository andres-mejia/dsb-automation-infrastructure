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
$script:orchestrationDir = "C:\Program Files\WindowsPowerShell\Modules\Dsb.RobotOrchestration"
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
        
        $wc = New-Object System.Net.WebClient
        $orchModule = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/Dsb.RobotOrchestration.psm1"
        Write-Host "Attempting to download file from from: $orchModule"
        $orchModuleDownload = "$orchestrationDir\Dsb.RobotOrchestration.psm1"
        $wc.DownloadFile($orchModule, $orchModuleDownload)        

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
        Write-Log -LogPath $LogFile -Message "Saving all temporary files to $script:tempDirectory" -Severity 'Info'
    }   

    Process {
        Write-Host "Logging to file $LogFile"
        Write-Log -LogPath $LogFile -Message "Logging to file $LogFile" -Severity 'Info'

        Write-Host "Connect Robot Orchestrator starts"
        Write-Log -LogPath $LogFile -Message "Connect Robot Orchestrator starts" -Severity 'Info'

        Write-Host "Tenant is $tenant"
        Write-Log -LogPath $LogFile -Message "Tenant is $tenant" -Severity 'Info'
        
        Write-Host "Trying to install Filebeat"
        Write-Log -LogPath $LogFile -Message "Trying to install Filebeat" -Severity 'Info'

        Try {
            Install-Filebeat -InstallationPath $script:tempDirectory -FilebeatVersion 7.2.0
        }
        Catch {
            Write-Host "There was an error trying to install Filebeats, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw 'There was a problem installing Filebeats'
        }

        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

        Write-Host "Try running robot connection script"
        Try {
            Connect-RobotToOrchestrator -LogPath $sLogPath -LogName $scheduledTaskScript -RobotKey $RobotKey -Environment $Environment -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error trying to run robot connection script, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
            Throw "There was an error trying to run robot connection script, exception: $_.Exception"
        }

        End {
            If($?){
                Write-Host "Completed Successfully."
                Write-Log -LogPath $LogFile -Message "Completed Successfully." -Severity 'Info'
                Write-Host "Script is ending now."
            }
        }
    }
}

Main
Finish-Log -NoExit
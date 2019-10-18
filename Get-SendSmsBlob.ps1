[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountKey,

    [Parameter(Mandatory = $true)]
    [string] $StorageAccountContainer
)

$ErrorActionPreference = "SilentlyContinue"
#Script Version
$sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$sDebug = $true
#Log File Info
$LogPath = "C:\ProgramData\AutomationAzureOrchestration"
$LogName = "Retrieve-SendSms-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Temp location
$script:tempDirectory = (Join-Path $ENV:TEMP "SendSms-$(Get-Date -f "yyyyMMddhhmmssfff")")
New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

[System.Version] $azureRmVersion = "6.13.1"
$azureRmModuleScript = "C:\Program Files (x86)\WindowsPowerShell\Modules\AzureRM\$azureRmVersion\AzureRM.psd1"

$sendSmsDirectory = "PR_SMS_UDSENDELSE"
$sendSmsCDrive = "C:/$sendSmsDirectory"
$sendSmsZip = "$sendSmsDirectory.zip"

Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop
Write-Host "Checking if $sendSmsDirectory exists"
Write-Log -LogPath $LogFile -Message "Checking if $sendSmsDirectory exists" -Severity "Info"

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

If (!(Test-Path -Path $sendSmsCDrive)) {

    Write-Host "No $sendSmsDirectory existed, downloading it now"
    Write-Log -LogPath $LogFile -Message "No $sendSmsDirectory existed, downloading it now" -Severity "Info"

    Try {
        Write-Host "Checking for local AzureRm Powershell version: $azureRmVersion"
        Write-Log -LogPath $LogFile -Message "Checking for local AzureRm Powershell version: $azureRmVersion" -Severity "Info"

        If (Test-Path $azureRmModuleScript) {

            Write-Host "Local AzureRm module found, version: $azureRmVersion. Trying to import now"
            Write-Log -LogPath $LogFile -Message "Local AzureRm module found, version: $azureRmVersion. Trying to import now" -Severity "Info"

            if ((Get-Module AzureRM)) {
                Write-Host "Unloading AzureRM module ... "
                Write-Log -LogPath $LogFile -Message "Unloading AzureRM module ..." -Severity "Info"
                Remove-Module AzureRM
            }
    
            Write-Host "Importing module $azureRmModuleScript"
            Write-Log -LogPath $LogFile -Message "Importing module $azureRmModuleScript" -Severity "Info"
            $env:PSModulePath = $azureRmModuleScript + ";" + $env:PSModulePath

            $currentVerbosityPreference = $Global:VerbosePreference

            $Global:VerbosePreference = 'SilentlyContinue'
            Import-Module $azureRmModuleScript -Verbose:$false
            $Global:VerbosePreference = $currentVerbosityPreference

        } Else {
            $azureRmMsi = "https://github.com/Azure/azure-powershell/releases/download/v6.13.1-November2018/Azure-Cmdlets-6.13.1.24243-x86.msi"
            $downloadedAzureRmMsi = "$script:tempDirectory/Azure-Cmdlets-6.13.1.24243-x86.msi"
            Write-Host "Attempting to download file from from: $azureRmMsi to path $downloadedAzureRmMsi"
            Write-Log -LogPath $LogFile -Message "Attempting to download file from from: $azureRmMsi to path $downloadedAzureRmMsi" -Severity "Info"

            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($azureRmMsi, $downloadedAzureRmMsi)

            Write-Host "Attempting to install AzureRm from MSI"
            Write-Log -LogPath $LogFile -Message "Attempting to install AzureRm from MSI" -Severity "Info"
            Start-Process msiexec.exe -Wait -ArgumentList "/I $script:tempDirectory\Azure-Cmdlets-6.13.1.24243-x86.msi /quiet"
            
            Write-Host "Trying to import AzureRm module"
            Write-Log -LogPath $LogFile -Message "Trying to import AzureRm module" -Severity "Info"    
            Import-Module AzureRM -Verbose:$false -ErrorAction Stop
        }
    }
    Catch {
        Write-Host "There was an error importing or installing AzureRm module: $_.Exception.Message"
        Throw "There was an error importing or installing AzureRm module: $_.Exception.Message"
    }

    Try {
        Write-Host "Adding storage context for $StorageAccountName"
        Write-Log -LogPath $LogFile -Message "Adding storage context for $StorageAccountName" -Severity "Info"
        $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

        Write-Host "Getting blob at $sendSmsZip"
        Write-Log -LogPath $LogFile -Message "Getting blob at $sendSmsZip from container $StorageAccountContainer" -Severity "Info"
        Get-AzureStorageBlobContent -Container $StorageAccountContainer -Blob $sendSmsZip -Destination "$script:tempDirectory/$sendSmsZip" -Context $context -ErrorAction Stop

        Write-Host "Expanding $script:tempDirectory/$sendSmsZip to C drive"
        Write-Log -LogPath $LogFile -Message "Expanding $script:tempDirectory/$sendSmsZip to C drive" -Severity "Info"
        Expand-Archive -Path "$script:tempDirectory/$sendSmsZip" -DestinationPath "C:/" -Force

        Write-Host "Removing temp directory $script:tempDirectory"
        Write-Log -LogPath $LogFile -Message "Removing temp directory $script:tempDirectory" -Severity "Info"
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null
    }
    Catch {
        Write-Host "There was an error retrieving SendSMS: $_.Exception.Message"
        Throw "There was an error retrieving SendSMS: $_.Exception.Message"
    }
} Else {
    Write-Host "$sendSmsDirectory existed, exiting now"
    Write-Log -LogPath $LogFile -Message "$sendSmsDirectory existed, exiting now" -Severity "Info"
}

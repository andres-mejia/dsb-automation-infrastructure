[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountKey,

        [Parameter(Mandatory = $true)]
        [string] $StorageAccountContainer,

        [System.Version] $azureRmVersion = "6.13.1"
    )

$ErrorActionPreference = "Stop"
#Script Version
$sScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$sDebug = $true
#Log File Info
$LogPath = "C:\Program Files\AutomationAzureOrchestration"
$LogName = "Retrieve-SendSms-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Temp location
$script:tempDirectory = (Join-Path $ENV:TEMP "SendSms-$(Get-Date -f "yyyyMMddhhmmssfff")")
New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

$azureRMModuleLocationBaseDir = 'C:\Modules\azurerm_6.7.0'
$azureRMModuleLocation = "$azureRMModuleLocationBaseDir\AzureRM\6.7.0\AzureRM.psd1"

$sendSmsDirectory = "PR_SMS_UDSENDELSE"
$sendSmsCDrive = "C:/$sendSmsDirectory"
$sendSmsZip = "$sendSmsDirectory.zip"

Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop
Write-Host "Checking if $sendSmsDirectory exists"
Write-Log -LogPath $LogFile -Message "Checking if $sendSmsDirectory exists" -Severity "Info"


If(!(Test-Path -Path $sendSmsCDrive)){

    Write-Host "No $sendSmsDirectory existed, downloading it now"
    Write-Log -LogPath $LogFile -Message "No $sendSmsDirectory existed, downloading it now" -Severity "Info"

    If (Test-Path 'C:\Modules\azurerm_6.7.0\AzureRM\6.7.0\AzureRM.psd1') {
        Import-AzureRmModuleFromLocalMachine
    } Else {
        $azModules = (Get-Module AzureRM -ListAvailable -Verbose:$false | Where-Object {$_.Version.Major -ge $azureRmVersion.Major})
        If ($azModules) {
            Write-Host "AzureRM module version $($azureRmVersion.Major) or greater is already installed. Importing module ..."
            Write-Log -LogPath $LogFile -Message "AzureRM module version $($azureRmVersion.Major) or greater is already installed. Importing module ..." -Severity "Info"

        } Else {
            Write-Host "AzureRM module version $azureRmVersion or later not found. Installing AzureRM $azureRmVersion" -ForegroundColor Yellow
            Write-Log -LogPath $LogFile -Message "AzureRM module version $azureRmVersion or later not found. Installing AzureRM $azureRmVersion" -Severity "Info"
            Install-Module AzureRM -RequiredVersion $azureRmVersion -Force -AllowClobber
        }
        Import-Module AzureRM -Verbose:$false
    }

    Try {
        Write-Host "Adding storage context for $StorageAccountName"
        Write-Log -LogPath $LogFile -Message "Adding storage context for $StorageAccountName" -Severity "Info"
        $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

        Write-Host "Getting blob at $sendSmsZip"
        Write-Log -LogPath $LogFile -Message "Getting blob at $sendSmsZip" -Severity "Info"
        Get-AzureStorageBlobContent -Container $StorageAccountContainer -Blob $sendSmsZip -Destination "$script:tempDirectory/$sendSmsZip" -Context $context -ErrorAction Stop

        Write-Host "Expanding $script:tempDirectory/$sendSmsZip to C drive"
        Write-Log -LogPath $LogFile -Message "Expanding $script:tempDirectory/$sendSmsZip to C drive" -Severity "Info"
        Expand-Archive -Path "$script:tempDirectory/$sendSmsZip" -DestinationPath "C:/" -Force

        Write-Host "Removing temp directory $script:tempDirectory"
        Write-Log -LogPath $LogFile -Message "Removing temp directory $script:tempDirectory" -Severity "Info"
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null
    }
    Catch {
        Write-Host "There was an error retrieving SendSMS"
        Throw "There was an error retrieving SendSMS"
    }
} Else {
    Write-Host "$sendSmsDirectory existed, exiting now"
    Write-Log -LogPath $LogFile -Message "$sendSmsDirectory existed, exiting now" -Severity "Info"

}

function Import-AzureRmModuleFromLocalMachine  {
    
    if ((Get-Module AzureRM)) {
        Write-Host "Unloading AzureRM module ... "
        Remove-Module AzureRM
    }
    
    Write-Host "Importing module $azureRMModuleLocation"
    $env:PSModulePath = $azureRMModuleLocationBaseDir + ";" + $env:PSModulePath

    $currentVerbosityPreference = $Global:VerbosePreference

    $Global:VerbosePreference = 'SilentlyContinue'
    Import-Module $azureRMModuleLocation -Verbose:$false
    $Global:VerbosePreference = $currentVerbosityPreference
}
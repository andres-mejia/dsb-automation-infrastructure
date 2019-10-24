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
$ScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$Debug = $true
#Log File Info
$LogPath = "C:\ProgramData\AutomationAzureOrchestration"
$LogName = "Retrieve-SendSms-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Temp location

$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$script:tempDirectory = (Join-Path $ENV:TEMP "SendSms-$(Get-Date -f "yyyyMMddhhmmssfff")")
New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

[System.Version] $azureRmVersion = "6.13.1"
$powershellModuleDir = "C:\Program Files (x86)\WindowsPowerShell\Modules"
If (!(Test-Path -Path $powershellModuleDir)) {
    New-Item -ItemType Directory -Force -Path $powershellModuleDir
}
$azureRmModuleScript = "$powershellModuleDir\AzureRM\$azureRmVersion\AzureRM.psd1"

$p = [Environment]::GetEnvironmentVariable("PSModulePath")
$p += ";$powershellModuleDir\"
[Environment]::SetEnvironmentVariable("PSModulePath", $p)

$sendSmsDirectory = "PR_SMS_UDSENDELSE"
$sendSmsCDrive = "C:/$sendSmsDirectory"
$sendSmsZip = "$sendSmsDirectory.zip"

Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop

$securityConfig = [Net.ServicePointManager]::SecurityProtocol
Write-Host "Current security protocol is: $securityConfig"
Write-Log -LogPath $LogFile -Message "Current security protocol is: $securityConfig" -Severity "Info"

Write-Host "Temp file location is: $script:tempDirectory"
Write-Log -LogPath $LogFile -Message "Temp file location is: $script:tempDirectory" -Severity "Info"

Write-Host "Storage container is: $StorageAccountContainer"
Write-Log -LogPath $LogFile -Message "Storage container is: $StorageAccountContainer" -Severity "Info"

Write-Host "Storage account name is: $StorageAccountName"
Write-Log -LogPath $LogFile -Message "Storage account name is: $StorageAccountName" -Severity "Info"

Write-Host "Storage account key is $StorageAccountKey"
Write-Log -LogPath $LogFile -Message "Storage account key is $StorageAccountKey" -Severity "Info"

Write-Host "Checking if $sendSmsDirectory exists"
Write-Log -LogPath $LogFile -Message "Checking if $sendSmsDirectory exists" -Severity "Info"

If (!(Test-Path -Path $sendSmsCDrive)) {

    Write-Host "No $sendSmsDirectory existed, downloading it now"
    Write-Log -LogPath $LogFile -Message "No $sendSmsDirectory existed, downloading it now" -Severity "Info"

    Try {
        Write-Host "Checking for AzureRm and Az Modules"
        Write-Log -LogPath $LogFile -Message "Checking for AzureRm and Az Modules" -Severity "Info"

        If (Test-Path $azureRmModuleScript) {
            Write-Host "Local AzureRm was found, trying to uninstall now"
            Write-Log -LogPath $LogFile -Message "Local AzureRm was found, trying to uninstall now" -Severity "Info"

            $azureRmMsi = "https://github.com/Azure/azure-powershell/releases/download/v6.13.1-November2018/Azure-Cmdlets-6.13.1.24243-x86.msi"
            $downloadedAzureRmMsi = "$script:tempDirectory/Azure-Cmdlets-6.13.1.24243-x86.msi"
            Write-Host "Attempting to download file from from: $azureRmMsi to path $downloadedAzureRmMsi"
            Write-Log -LogPath $LogFile -Message "Attempting to download file from from: $azureRmMsi to path $downloadedAzureRmMsi" -Severity "Info"

            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($azureRmMsi, $downloadedAzureRmMsi)

            Write-Host "Attempting to uninstall AzureRm from MSI"
            Write-Log -LogPath $LogFile -Message "Attempting to uninstall AzureRm from MSI" -Severity "Info"
            Start-Process msiexec.exe -Wait -ArgumentList "/x $script:tempDirectory\Azure-Cmdlets-6.13.1.24243-x86.msi /quiet"
        }

        If ((Get-InstalledModule -Name Az)) {
            Write-Host "Az Module exists, unloading it now"
            Write-Log -LogPath $LogFile -Message "Az Module exists, unloading it now" -Severity "Info"
            Remove-Module Az
        }
        Else {
            Write-Host "No Az module found, installing Nuget and then Az modules"
            Write-Log -LogPath $LogFile -Message "No Az module found, installing Nuget and then Az modules" -Severity "Info"

            Write-Host "Attempting to register PSRepository"
            Write-Log -LogPath $LogFile -Message "Attempting to register PSRepository" -Severity "Info"
            Register-PSRepository -Default -InstallationPolicy Trusted -Force

            Write-Host "Trying to install Nuget."
            Write-Log -LogPath $LogFile -Message "Trying to install Nuget." -Severity "Info"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser

            Write-Host "Nuget package installed, trying to install Az module now"
            Write-Log -LogPath $LogFile -Message "Nuget package installed, trying to install Az module now" -Severity "Info"
            Install-Module -Name Az -Repository PSGallery -AllowClobber -Force -Scope CurrentUser
        }

        If ((Get-Module -Name AzureRm)) {
            Write-Host "AzureRm module was found, uninstalling now"
            Write-Log -LogPath $LogFile -Message "AzureRm module was found, uninstalling now" -Severity "Info"
            $versions = (Get-InstalledModule AzureRM -AllVersions | Select-Object Version)
            $versions | ForEach-Object { Uninstall-AllModules -TargetModule AzureRM -Version ($_.Version.ToString()) -Force }
            Uninstall-Module AzureRm
            Uninstall-AzureRm
        }

        Write-Host "Trying to import Az module"
        Write-Log -LogPath $LogFile -Message "Trying to import Az module" -Severity "Info"
        Import-Module Az
    }
    Catch {
        Write-Log -LogPath $LogFile -Message "There was an error installing or importing Az module: $_.Exception.Message" -Severity "Error"
        Write-Host "There was an error installing or importing Az module: $_.Exception.Message"
        Throw "There was an error installing or importing Az module: $_.Exception.Message"
    }

    Try {
        Write-Host "Adding storage context for $StorageAccountName"
        Write-Log -LogPath $LogFile -Message "Adding storage context for $StorageAccountName" -Severity "Info"
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

        Write-Host "Storage context is: $context"
        Write-Log -LogPath $LogFile -Message "Storage context is: $context" -Severity "Info"

        Write-Host "Getting blob at $sendSmsZip"
        Write-Log -LogPath $LogFile -Message "Getting blob at $sendSmsZip from container $StorageAccountContainer" -Severity "Info"
        Get-AzStorageBlobContent -Container $StorageAccountContainer -Blob $sendSmsZip -Destination "$script:tempDirectory/$sendSmsZip" -Context $context -ErrorAction Stop

        Write-Host "Expanding $script:tempDirectory/$sendSmsZip to C drive"
        Write-Log -LogPath $LogFile -Message "Expanding $script:tempDirectory/$sendSmsZip to C drive" -Severity "Info"
        Expand-Archive -Path "$script:tempDirectory/$sendSmsZip" -DestinationPath "C:/" -Force

        Write-Host "Removing temp directory $script:tempDirectory"
        Write-Log -LogPath $LogFile -Message "Removing temp directory $script:tempDirectory" -Severity "Info"
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null
    }
    Catch {
        Write-Log -LogPath $LogFile -Message "There was an error retrieving SendSMS: $_.Exception.Message" -Severity "Error"
        Write-Host "There was an error retrieving SendSMS: $_.Exception.Message"
        Throw "There was an error retrieving SendSMS: $_.Exception.Message"
    }
} Else {
    Write-Host "$sendSmsDirectory existed, exiting now"
    Write-Log -LogPath $LogFile -Message "$sendSmsDirectory existed, exiting now" -Severity "Info"
}

function Uninstall-AllModules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetModule,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [switch]$Force,

        [switch]$WhatIf
    )
  
    $AllModules = @()
    Write-Host "Trying to unistall $TargetModule"

    'Creating list of dependencies...'
    $target = Find-Module $TargetModule -RequiredVersion $version
    $target.Dependencies | ForEach-Object {
        if ($_.PSObject.Properties.Name -contains 'requiredVersion') {
            $AllModules += New-Object -TypeName psobject -Property @{name = $_.name; version = $_.requiredVersion }
        }
        else {
            # Assume minimum version
            # Minimum version actually reports the installed dependency
            # which is used, not the actual "minimum dependency." Check to
            # see if the requested version was installed as a dependency earlier.
            $candidate = Get-InstalledModule $_.name -RequiredVersion $version -ErrorAction Ignore
            if ($candidate) {
                $AllModules += New-Object -TypeName psobject -Property @{name = $_.name; version = $version }
            }
            else {
                $availableModules = Get-InstalledModule $_.name -AllVersions
                Write-Warning ("Could not find uninstall candidate for {0}:{1} - module may require manual uninstall. Available versions are: {2}" -f $_.name, $version, ($availableModules.Version -join ', '))
            }
        }
    }
    $AllModules += New-Object -TypeName psobject -Property @{name = $TargetModule; version = $Version }

    foreach ($module in $AllModules) {
        Write-Host ('Uninstalling {0} version {1}...' -f $module.name, $module.version)
        try {
            Uninstall-Module -Name $module.name -RequiredVersion $module.version -Force:$Force -ErrorAction Stop -WhatIf:$WhatIf
        }
        catch {
            Write-Host ("`t" + $_.Exception.Message)
        }
    }
}

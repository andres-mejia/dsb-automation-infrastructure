[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string] $StorageAccountKey,

    [Parameter(Mandatory = $true)]
    [string] $StorageAccountContainer
)

$ErrorActionPreference = "Stop"
#Script Version
$ScriptVersion = "1.0"
#Debug mode; $true - enabled ; $false - disabled
$Debug = $true
#Log File Info
$LogPath = "C:\ProgramData\AutomationAzureOrchestration"
$LogName = "Install-Fonts-$(Get-Date -f "yyyyMMddhhmmssfff").log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName
#Temp location

$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$tempDirectory = (Join-Path $ENV:TEMP "ViaOffice-$(Get-Date -f "yyyyMMddhhmmssfff")")
New-Item -ItemType Directory -Path $tempDirectory | Out-Null

$p = [Environment]::GetEnvironmentVariable("PSModulePath")
$p += ";$powershellModuleDir\"
[Environment]::SetEnvironmentVariable("PSModulePath", $p)

$via = "ViaOffice"
$viaOfficeZip = "$via.zip"

Start-Log -LogPath $LogPath -LogName $Logname -ErrorAction Stop

$securityConfig = [Net.ServicePointManager]::SecurityProtocol
Write-Host "Current security protocol is: $securityConfig"
Write-Log -LogPath $LogFile -Message "Current security protocol is: $securityConfig" -Severity "Info"

Write-Host "Temp file location is: $tempDirectory"
Write-Log -LogPath $LogFile -Message "Temp file location is: $tempDirectory" -Severity "Info"

Write-Host "Storage container is: $StorageAccountContainer"
Write-Log -LogPath $LogFile -Message "Storage container is: $StorageAccountContainer" -Severity "Info"

Write-Host "Storage account name is: $StorageAccountName"
Write-Log -LogPath $LogFile -Message "Storage account name is: $StorageAccountName" -Severity "Info"

Write-Host "Storage account key is $StorageAccountKey"
Write-Log -LogPath $LogFile -Message "Storage account key is $StorageAccountKey" -Severity "Info"

Try {
    Get-Blob -FullLogPath $LogFile `
        -StorageAccountKey $StorageAccountKey `
        -StorageAccountName $StorageAccountName `
        -StorageAccountContainer $StorageAccountContainer `
        -BlobFile $viaOfficeZip `
        -OutPath $script:tempDirectory

    $viaExpandedDir = "$script:tempDirectory\$via"
    Write-Host "Expanding $script:tempDirectory/$viaOfficeZip to $viaExpandedDir"
    Write-Log -LogPath $LogFile -Message "Expanding $script:tempDirectory/$viaOfficeZip to $viaExpandedDir" -Severity "Info"

    New-Item -ItemType Directory -Path $viaExpandedDir
    Expand-Archive -Path "$script:tempDirectory\$viaOfficeZip" -DestinationPath $viaExpandedDir -Force

    If ((Get-ChildItem $viaExpandedDir | Measure-Object).Count -eq 0) {
        Write-Host "Expanded zip was empty"
        Write-Log -LogPath $LogFile -Message "Expanded zip was empty" -Severity "Error"
        Throw "Expanded zip was empty"
        Break        
    }
    
    $SourceDir = $viaExpandedDir
    $Source = "$viaExpandedDir\*"
    $Destination = (New-Object -ComObject Shell.Application).Namespace(0x14)
    $TempFolder = "C:\Windows\Temp\Fonts"

    New-Item $TempFolder -Type Directory -Force | Out-Null

    Get-ChildItem -Path $Source -Include '*.ttf', '*.ttc', '*.otf' -Recurse | ForEach {
        Write-Host "Font fullname is: $($_.FullName)"
        Write-Log -LogPath $LogFile -Message "Font fullname is: $($_.FullName)" -Severity "Info"

        Write-Host "Font name is: $($_.Name)"
        Write-Log -LogPath $LogFile -Message "Font name is: $($_.Name)" -Severity "Info"

        If (-not(Test-Path "C:\Windows\Fonts\$($_.Name)")) {

            $Font = "$TempFolder\$($_.Name)"
            Write-Host "Trying to install font: $($_.FullName)"
            Write-Log -LogPath $LogFile -Message "Trying to install font: $($_.FullName)" -Severity "Info"

            # Copy font to local temporary folder
            Copy-Item $($_.FullName) -Destination $TempFolder
        
            # Install font
            $Destination.CopyHere($Font, 0x14)

            # Delete temporary copy of font
            Remove-Item $Font -Force
            If (-not(Test-Path "C:\Windows\Fonts\$($_.Name)")) {
                Write-Host "Font file not found after trying to install it"
                Write-Log -LogPath $LogFile -Message "Font file not found after trying to install it" -Severity "Error"
                Throw "Font file not found after trying to install it"
                Break     
            }
            Else {
                Write-Host "Successfully installed font $($_.Name)"
                Write-Log -LogPath $LogFile -Message "Successfully installed font $($_.Name)" -Severity "Info"
            }
        }
    }

    Write-Host "Successfully installed fonts"
    Write-Log -LogPath $LogFile -Message "Successfully installed fonts" -Severity "Info"

    Write-Host "Removing temp directory $script:tempDirectory"
    Write-Log -LogPath $LogFile -Message "Removing temp directory $script:tempDirectory" -Severity "Info"
    Remove-Item $script:tempDirectory -Recurse -Force | Out-Null
}
Catch {
    Write-Log -LogPath $LogFile -Message "There was an error installing fonts: $_.Exception.Message" -Severity "Error"
    Write-Host "There was an error installing fonts: $_.Exception.Message"
    Throw "There was an error installing fonts: $_.Exception.Message"
}
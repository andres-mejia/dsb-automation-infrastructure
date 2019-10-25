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
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

    $fontDirectory = "C:\Windows\Fonts"
    $objShell = New-Object -ComObject Shell.Application
    $objFolder = $objShell.namespace($viaExpandedDir)
    foreach ($file in $objFolder.items())
    {
        $fileType = $($objFolder.getDetailsOf($file, 2))
        if(($fileType -eq "OpenType font file") -or ($fileType -eq "TrueType font file"))
        {
            $fontName = $($objFolder.getDetailsOf($File, 21))
            $regKeyName = $fontName,$openType -join " "
            $regKeyValue = $file.Name
            If (Test-Path -Path (Join-Path -Path $fontDirectory -ChildPath $file.Name)) {
                Write-Host "$regKeyValue already existed, skipping installation"
                Write-Log -LogPath $LogFile -Message "$regKeyValue already existed, skipping installation" -Severity "Info"                
            }
            Else {
                Write-Host "Installing: $regKeyValue"
                Write-Log -LogPath $LogFile -Message "Installing: $regKeyValue" -Severity "Info"
                Move-Item -Path $file.Path -Destination $fontDirectory -Force
                Write-Host "Moved $regKeyValue"
                Invoke-Command -ScriptBlock { $null = New-ItemProperty -Path $args[0] -Name $args[1] -Value $args[2] -PropertyType String -Force } -ArgumentList $regPath, $regKeyname, $regKeyValue -ErrorAction Stop
            }
            If (!(Test-Path -Path (Join-Path -Path $fontDirectory -ChildPath $file.Name))) {
                Write-Host "Font could not be found: $regKeyValue"
                Write-Log -LogPath $LogFile -Message "Font could not be found: $regKeyValue" -Severity "Error"
                Throw "Font could not be found: $regKeyValue"
                Break
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
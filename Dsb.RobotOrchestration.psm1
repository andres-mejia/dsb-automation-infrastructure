function Start-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LogName
    )

    If (-Not (Test-Path -Path $LogPath)) {
        Write-Host "There was no directory at $LogPath, trying to create it now"
        Try {
            New-Item -ItemType Directory -Path $LogPath -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Host "There was an error creating $LogPath"
            Throw "There was an error creating {$LogPath}: $_.Exception"
        }
    }
    Else {
        Write-Host "A directory existed at $LogPath, not trying to create one"
    }

    $logFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    If(-Not (Test-Path -Path $logFullPath)){
        Write-Host "There was no logfile at $logFullPath, trying to create it now"
        Try {
            New-Item -Path $LogPath -Name $LogName -ItemType File -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Host "There was an error creating $logFullPath"
            Throw "There was an error creating {$logFullPath}: $_.Exception"
        }
    }

    If(-Not (Test-Path -Path $logFullPath -Verbose)){
        Throw "The log file should have been created but could not be found: $logFullPath"
    }
}

function Write-Log
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Info','Warn','Error')]
        [string]$Severity = 'Info'
    )

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $logString = "$now $Severity message='$Message' env=$Environment timeStamp=$now level=$Severity pcName=$env:computername"
    Try {
        Add-Content -Path $LogPath -Value $logString -Force
    }
    Catch {
        Write-Host "There was an error writing a log to $LogPath"
        Throw "There was an error creating {$LogPath}: $_.Exception"
    }

}

function Wait-ForService($servicesName, $serviceStatus) {
  # Get all services where DisplayName matches $serviceName and loop through each of them.
  foreach($service in (Get-Service -DisplayName $servicesName))
  {
      if($serviceStatus -eq 'Running') {
        Start-Service $service.Name
      }
      if($serviceStatus -eq "Stopped" ) {
        Stop-Service $service.Name
      }
      # Wait for the service to reach the $serviceStatus or a maximum of specified time
      $service.WaitForStatus($serviceStatus, '00:01:20')
 }

 return $serviceStatus

}

function Get-FilebeatZip {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath,

        [Parameter(Mandatory=$true)]
        [string] $DownloadPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("7.2.0")]
        [string] $FilebeatVersion
    )

    $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$FilebeatVersion-windows-x86.zip"
    Write-Host "Attempting to download Filebeat from: $url"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download from $url" -Severity 'Info'
    $filebeatZipName = "filebeat.zip"
    $downloadedZip = Join-Path -Path $DownloadPath -ChildPath $filebeatZipName
    if (Test-Path -Path $downloadedZip) {
        Write-Host "Found previously downloaded filebeat at: $downloadedZip Deleting the file now"
        Write-Log -LogPath $FullLogPath -Message "Found previously downloaded filebeat at: $downloadedZip Deleting the file now" -Severity 'Info'
        Remove-Item -Path $downloadedZip -Recurse
    }
    Write-Host "Attempting to download filebeat to: $downloadedZip"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download filebeat to: $downloadedZip" -Severity 'Info'
    Try {
        Invoke-WebRequest -Uri $url -OutFile $downloadedZip
    }
    Catch {
        Write-Host "There was an error downloading Filebeat: $_.Exception"
        Write-Log -LogPath $FullLogPath -Message "There was an error downloading Filebeat: $_.Exception" -Severity 'Error'
        Throw "There was an error downloading Filebeat: $_.Exception"
    }

    Write-Host "Expanding archive $downloadedZip"
    Write-Log -LogPath $FullLogPath -Message "Expanding archive $downloadedZip" -Severity 'Info'
    $programFileDir = "C:\Program Files"
    Try {
        Expand-Archive -Path $downloadedZip -DestinationPath $programFileDir -Force
    }
    Catch {
        Write-Host "There was an error unzipping Filebeat: $_.Exception"
        Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity 'Error'
        Throw "There was an error downloading Filebeat: $_.Exception"
    }

    $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
    Write-Host "Renaming $unzippedFile to Filebeat"
    Write-Log -LogPath $FullLogPath -Message "Renaming $unzippedFile to Filebeat" -Severity 'Info'
    
    Try {
        Rename-Item -Path $unzippedFile -NewName 'Filebeat' -Force -ErrorAction Stop
        If (Test-Path -Path $unzippedFile) {
            Remove-Item $unzippedFile -Recurse -Force -ErrorAction Stop
        }
    }
    Catch {
        Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
        Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity 'Error'
        throw "There was an error renaming unzipped Filebeat dir: $_.Exception"
    }
}

function Stop-FilebeatService {
    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    $service.StopService()
    Start-Sleep -s 1
}

function Get-FilebeatService {
    $service = Get-Service -Name filebeat -ErrorAction SilentlyContinue
    return $service
}

function Get-FilebeatConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath
    )

    $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
    Write-Host "Removing existing filebeat config from: $filebeatYaml"
    Write-Log -LogPath $FullLogPath -Message "Removing existing filebeat config from: $filebeatYaml" -Severity 'Info'
    Remove-Item -Path $filebeatYaml -Force
    
    $configUri = "https://raw.githubusercontent.com/nkuik/ion-infrastructure/master/filebeat.yml"
    Write-Host "Attempting to download filbeat config from: $configUri"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download filbeat config from: $configUri" -Severity 'Info'
    Invoke-WebRequest -Uri $configUri -OutFile $filebeatYaml
    if (-not (Test-Path -Path $filebeatYaml)) {
        throw [System.IO.FileNotFoundException] "$filebeatYaml not found."
    }
}

function Confirm-FilebeatServiceRunning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath
    )
    
    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    if ($service.State -eq "Running") {
        Write-Host "Filebeat Service started successfully"
        Write-Log -LogPath $FullLogPath -Message "Filebeat Service started successfully" -Severity 'Info'
    }
    else {
        Write-Host "Filebeat service is not running correctly"
        Write-Log -LogPath $FullLogPath -Message "Filebeat service is not running correctly" -Severity 'Error'
        throw "Filebeat service is not running correctly"
        break
    }
}

function Remove-OldFilebeatFolders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath,

        [Parameter(Mandatory = $true)]
        [string] $FilebeatVersion
    )

    $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
    If (Test-Path -Path $unzippedFile) {
        Write-Host "Item $unzippedFile existed, removing now"
        Write-Log -LogPath $FullLogPath -Message "Item $unzippedFile existed, removing now" -Severity 'Error'
        Remove-Item -Path $unzippedFile -Force
    }
    $programFileFilebeat = "C:\Program Files\Filebeat"
    If (Test-Path -Path $programFileFilebeat) {
        Write-Host "Item $programFileFilebeat existed, removing now"
        Write-Log -LogPath $FullLogPath -Message "Item $programFileFilebeat existed, removing now" -Severity 'Error'
        Remove-Item -Path $programFileFilebeat -Force
    }
}

function Start-FilebeatService {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath
    )

    Write-Host "Trying to start Filebeat service"
    Write-Log -LogPath $FullLogPath -Message "Trying to start Filebeat service" -Severity 'Info'
    Start-Service filebeat -ErrorAction Stop
}

function Install-Filebeat {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $LogPath,

        [Parameter(Mandatory = $true)]
        [string] $LogName,

        [Parameter(Mandatory=$true)]
        [string] $DownloadPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("7.2.0")]
        [string] $FilebeatVersion,

        [Parameter(Mandatory=$true)]
        [string] $HumioIngestToken
    )
    
    $beforeCd = Get-Location

    Start-Log -LogPath $LogPath -LogName $LogName
    $FullLogPath = Join-Path -Path $LogPath -ChildPath $LogName

    Write-Host "Trying to install filebeat version: $FilebeatVersion"
    Write-Log -LogPath $FullLogPath -Message "Trying to install filebeat version: $FilebeatVersion" -Severity 'Info'

    $filebeatService = Get-FilebeatService
    If ($filebeatService) {
        Write-Host "Filebeat service already installed, attempting to stop service"
        Write-Log -LogPath $FullLogPath -Message "Filebeat service already installed, attempting to stop service" -Severity 'Info'
        Try {
            Stop-FilebeatService
        }
        Catch {
            Write-Host "There was an exception stopping Filebeat service: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity 'Error'
            Break
        } 
    }
    Else {
        Write-Host "No Filebeat service existed"
        Write-Log -LogPath $FullLogPath -Message "No Filebeat service existed" -Severity 'Info'

        Remove-OldFilebeatFolders -FullLogPath $FullLogPath -FilebeatVersion $FilebeatVersion
        Get-FilebeatZip -FullLogPath $FullLogPath -DownloadPath $DownloadPath -FilebeatVersion $FilebeatVersion -ErrorAction Stop

        Write-Host "Attempting to install Filebeat"
        Write-Log -LogPath $FullLogPath -Message "Attempting to install Filebeat" -Severity 'Info'

        Write-Host "Humio Token is $HumioIngestToken"
        Write-Log -LogPath $FullLogPath -Message "Humio Token is $HumioIngestToken" -Severity 'Info'
        
        cd 'C:\Program Files\Filebeat'
        Try {
            Write-Host "Running custom filebeat installation function"
            Write-Log -LogPath $FullLogPath -Message "Running custom filebeat installation function" -Severity 'Info'
            Install-CustomFilebeat -HumioIngestToken '$HumioIngestToken' -ErrorAction Stop 
            cd $beforeCd
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity 'Error'
            throw [System.IO.Exception] $_.Exception
        }
    }

    Write-Host "Retrieving filebeat config"
    Write-Log -LogPath $FullLogPath -Message "Retrieving filebeat config" -Severity 'Info'
    
    Get-FilebeatConfig -FullLogPath $FullLogPath
    
    Start-FilebeatService -FullLogPath $FullLogPath

    Confirm-FilebeatServiceRunning -FullLogPath $FullLogPath
}

function Install-CustomFilebeat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken
    )

    # Delete and stop the service if it already exists.
    if (Get-Service filebeat -ErrorAction SilentlyContinue) {
        $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
        $service.StopService()
        Start-Sleep -s 1
        $service.delete()
    }

    $workdir = Split-Path $MyInvocation.MyCommand.Path
    $elasticToken = "output.elasticsearch.password=$HumioIngestToken"
    Write-Host "Elastic setting is $elasticToken"
    # Create the new service.
    New-Service -name filebeat `
    -displayName Filebeat `
    -binaryPathName "`"$workdir\filebeat.exe`" -c `"$workdir\filebeat.yml`" -path.home `"$workdir`" -path.data `"C:\ProgramData\filebeat`" -path.logs `"C:\ProgramData\filebeat\logs`" -E `"$elasticToken`""

    # Attempt to set the service to delayed start using sc config.
    Try {
        Start-Process -FilePath sc.exe -ArgumentList 'config filebeat start=delayed-auto'
    }
    Catch { 
        Write-Host "An error occured setting the service to delayed start." -ForegroundColor Red 
    }
}

Export-ModuleMember -Function Start-Log
Export-ModuleMember -Function Write-Log
Export-ModuleMember -Function Install-Filebeat
Export-ModuleMember -Function Get-FilebeatZip
Export-ModuleMember -Function Stop-FilebeatService
Export-ModuleMember -Function Get-FilebeatService
Export-ModuleMember -Function Get-FilebeatConfig
Export-ModuleMember -Function Start-FilebeatService
Export-ModuleMember -Function Remove-OldFilebeatFolders
Export-ModuleMember -Function Confirm-FilebeatServiceRunning
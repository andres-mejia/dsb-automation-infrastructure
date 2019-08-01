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

    If(-Not (Test-Path -Path $logFullPath)){
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

function waitForService($servicesName, $serviceStatus) {
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

function Install-Filebeat {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $LogPath,

        [Parameter(Mandatory = $true)]
        [string] $LogName,

        [Parameter(Mandatory=$true)]
        [string]$InstallationPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("7.2.0")]
        [string]$FilebeatVersion
    )

    Start-Log -LogPath $LogPath -LogName $LogName
    $fullLogPath = Join-Path -Path $LogPath -ChildPath $LogName

    Write-Host "Trying to install filebeat version: $FilebeatVersion"
    Write-Log -LogPath $fullLogPath -Message "Trying to install filebeat version: $FilebeatVersion" -Severity 'Info'

    $beforeCd = Get-Location

    if ((Get-Service filebeat -ErrorAction SilentlyContinue)) {
        Write-Host "Filebeat service already installed, attempting to stop service"
        Write-Log -LogPath $fullLogPath -Message "Filebeat service already installed, attempting to stop servcie" -Severity 'Info'
        Try {
            $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
            $service.StopService()
            Start-Sleep -s 1
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception stopping Filebeat service: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
            Break
        } 
    }
    else {
        cd 'C:\Program Files\Filebeat'

        $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$FilebeatVersion-windows-x86.zip"
        Write-Host "Attempting to download Filebeat from: $url"
        Write-Log -LogPath $fullLogPath -Message "Attempting to download from $url" -Severity 'Info'
        $downloadedZip = "$InstallationPath\filebeat.zip"
        if (Test-Path $downloadedZip) {
            Remove-Item $downloadedZip -Recurse
        }
        Write-Host "Downloading to $downloadedZip"
        Write-Log -LogPath $fullLogPath -Message "Downloading to $downloadedZip" -Severity 'Info'

        Try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $downloadedZip)
            Test-Path $downloadedZip -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an error downloading Filebeat: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message "There was an error downloading Filebeat: $_.Exception" -Severity 'Error'
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        Write-Host "Expanding archive $downloadedZip"
        Write-Log -LogPath $fullLogPath -Message "Expanding archive $downloadedZip" -Severity 'Info'

        Try {
            Expand-Archive -Path $downloadedZip -DestinationPath 'C:\Program Files' -Force
        }
        Catch {
            Write-Host "There was an error unzipping Filebeat: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
            Throw "There was an error downloading Filebeat: $_.Exception"
        }

        $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
        Write-Host "Renaming $unzippedFile to Filebeat"
        Write-Log -LogPath $fullLogPath -Message "Renaming $unzippedFile to Filebeat" -Severity 'Info'
        
        Try {
            Rename-Item -Path $unzippedFile -NewName 'Filebeat' -Force -ErrorAction Stop
            if (Test-Path $unzippedFile) {
                Remove-Item $unzippedFile -Recurse -Force -ErrorAction Stop
            }
        }
        Catch {
            Write-Host "There was an error renaming unzipped Filebeat dir: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
            throw "There was an error renaming unzipped Filebeat dir: $_.Exception"
        }

        Write-Host "Retrieving installer script"
        Write-Log -LogPath $fullLogPath -Message "Retrieving installer script" -Severity 'Info'

        $serviceInstaller = "C:\Program Files\Filebeat\install-service-filebeat.ps1"
        Remove-Item $serviceInstaller -Force
        $wc = New-Object System.Net.WebClient
        $serviceInstallerUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/install-service-filebeat.ps1"
        Try {
            $wc.DownloadFile($serviceInstallerUri, $serviceInstaller) 
            if (-not (Test-Path $serviceInstaller)) {
                throw [System.IO.FileNotFoundException] "$serviceInstaller not found."
            }
        }
        Catch {
            Write-Host "There was an error downloading the filebeats config: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
            throw [System.IO.Exception] $_.Exception
        }

        Write-Host "Attempting to install Filebeats"
        Write-Log -LogPath $fullLogPath -Message "Attempting to install Filebeats" -Severity 'Info'

        Write-Host "Humio Token is $HumioIngestToken"
        Try {
            cd 'C:\Program Files\Filebeat'
            custom-filebeat-install -HumioIngestToken '$HumioIngestToken' -ErrorAction Stop 
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
            throw [System.IO.Exception] $_.Exception
        } 

    }

    Write-Host "Retrieving filebeats config"
    Write-Log -LogPath $fullLogPath -Message "Retrieving filebeats config" -Severity 'Info'
    
    $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
    Remove-Item $filebeatYaml -Force
    $wc = New-Object System.Net.WebClient
    $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"
    Try {
        $wc.DownloadFile($configUri, $filebeatYaml) 
        if (-not (Test-Path $filebeatYaml)) {
             throw [System.IO.FileNotFoundException] "$filebeatYaml not found."
        }
    }
    Catch {
        Write-Host "There was an error downloading the filebeats config: $_.Exception"
        Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
        throw $_.Exception
        break
    }

    Try {
        Write-Host "Trying to start Filebeat service"
        Write-Log -LogPath $fullLogPath -Message "Trying to start Filebeat service" -Severity 'Info'
        Start-Service filebeat -ErrorAction Stop
    }
    Catch {
        cd $beforeCd
        Write-Host "There was an exception starting the Filebeat service: $_.Exception"
        Write-Log -LogPath $fullLogPath -Message "There was an exception starting the Filebeat service: $_.Exception" -Severity 'Error'
        throw "There was an exception starting the Filebeat service: $_.Exception"
        break
    }

    $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
    if ($service.State -eq "Running") {
        Write-Host "Filebeat Service started successfully"
        Write-Log -LogPath $fullLogPath -Message "Filebeat Service started successfully" -Severity 'Info'
    }
    else {
        Write-Host "Filebeats service is not running correctly"
        Write-Log -LogPath $fullLogPath -Message "Filebeats service is not running correctly" -Severity 'Error'
        cd $beforeCd
        throw "Filebeats service is not running correctly"
        break
    }

    cd $beforeCd
}

function custom-filebeat-install {
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

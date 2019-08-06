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
        [ValidateSet("Info",'Warn',"Error")]
        [string]$Severity = "Info"
    )

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $logString = "$now $Severity message='$Message' env='Dev' timeStamp=$now level=$Severity pcName=$env:computername"
    Try {
        Add-Content -Path $LogPath -Value $logString -Force
    }
    Catch {
        Write-Host "There was an error writing a log to $LogPath"
        Throw "There was an error creating {$LogPath}: $_.Exception"
    }
}

function Download-File {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FullLogPath,

        [Parameter(Mandatory=$true)]
        [string] $Url,

        [Parameter(Mandatory=$true)]
        [string] $OutPath
    )

    Write-Host "Attempting to download: $Url, to: $OutPath"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download: $Url, to: $OutPath" -Severity "Info"

    $client = New-Object System.Net.WebClient
    $client.DownloadFile($Url, $OutPath)

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
    Write-Log -LogPath $FullLogPath -Message "Attempting to download from $url" -Severity "Info"
    $filebeatZipName = "filebeat.zip"
    $downloadedZip = Join-Path -Path $DownloadPath -ChildPath $filebeatZipName
    if (Test-Path -Path $downloadedZip) {
        Write-Host "Found previously downloaded filebeat at: $downloadedZip Deleting the file now"
        Write-Log -LogPath $FullLogPath -Message "Found previously downloaded filebeat at: $downloadedZip Deleting the file now" -Severity "Info"
        Remove-Item -Path $downloadedZip -Recurse
    }
    Write-Host "Attempting to download filebeat to: $downloadedZip"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download filebeat to: $downloadedZip" -Severity "Info"
    
    Download-File -FullLogPath $FullLogPath -Url $url -OutPath $downloadedZip

    Write-Host "Expanding archive $downloadedZip"
    Write-Log -LogPath $FullLogPath -Message "Expanding archive $downloadedZip" -Severity "Info"
    
    $programFileDir = "C:\Program Files"
    Expand-Archive -Path $downloadedZip -DestinationPath $programFileDir -Force

    $expandedFilebeat = Join-Path -Path $programFileDir -ChildPath "filebeat-$FilebeatVersion-windows-x86"
    Rename-Item -Path $expandedFilebeat -NewName 'Filebeat' -Force -ErrorAction Stop
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
    Write-Log -LogPath $FullLogPath -Message "Removing existing filebeat config from: $filebeatYaml" -Severity "Info"
    Remove-Item -Path $filebeatYaml -Force

    $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"
    Write-Host "Attempting to download filebeat config from: $configUri"
    Write-Log -LogPath $FullLogPath -Message "Attempting to download filebeat config from: $configUri" -Severity "Info"
    
    Download-File -FullLogPath $FullLogPath -Url $configUri -OutPath $filebeatYaml
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
        Write-Log -LogPath $FullLogPath -Message "Filebeat Service started successfully" -Severity "Info"
        return $true
    }
    else {
        Write-Host "Filebeat service is not running correctly"
        Write-Log -LogPath $FullLogPath -Message "Filebeat service is not running correctly" -Severity "Error"
        return $false
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
        Write-Log -LogPath $FullLogPath -Message "Item $unzippedFile existed, removing now" -Severity "Info"
        Remove-Item -Path $unzippedFile -Recurse -Force
    }
    $programFileFilebeat = "C:\Program Files\Filebeat"
    If (Test-Path -Path $programFileFilebeat) {
        Write-Host "Item $programFileFilebeat existed, removing now"
        Write-Log -LogPath $FullLogPath -Message "Item $programFileFilebeat existed, removing now" -Severity "Info"
        Remove-Item -Path $programFileFilebeat -Recurse -Force
    }
}

function Start-FilebeatService {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FullLogPath
    )

    Write-Host "Trying to start Filebeat service"
    Write-Log -LogPath $FullLogPath -Message "Trying to start Filebeat service" -Severity "Info"
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
    Write-Log -LogPath $FullLogPath -Message "Trying to install filebeat version: $FilebeatVersion" -Severity "Info"

    $filebeatService = Get-FilebeatService
    If ($filebeatService) {
        Write-Host "Filebeat service already installed, attempting to stop service"
        Write-Log -LogPath $FullLogPath -Message "Filebeat service already installed, attempting to stop service" -Severity "Info"
        Try {
            Stop-FilebeatService -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an exception stopping Filebeat service: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity "Error"
            Break
        } 
    }
    Else {
        Write-Host "No Filebeat service existed"
        Write-Log -LogPath $FullLogPath -Message "No Filebeat service existed" -Severity "Info"
        
        Try {
            Write-Host "Removing old Filebeat folders if they exist"
            Write-Log -LogPath $FullLogPath -Message "Removing old Filebeat folders if they exist" -Severity "Info"
            Remove-OldFilebeatFolders -FullLogPath $FullLogPath -FilebeatVersion $FilebeatVersion -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an exception deleting old Filebeat folders: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message "There was an exception deleting old Filebeat folders: $_.Exception" -Severity "Error"
            throw "There was an exception deleting old Filebeat folders: $_.Exception"
            break
        }

        Try {
            Write-Host "Attempting to retrieve and unzip Filebeat zip"
            Write-Log -LogPath $FullLogPath -Message "Attempting to retrieve and unzip Filebeat zip" -Severity "Info"
            Get-FilebeatZip -FullLogPath $FullLogPath -DownloadPath $DownloadPath -FilebeatVersion $FilebeatVersion -ErrorAction Stop
        }
        Catch {
            Write-Host "There was an exception retrieving/expanding filebeat zip: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message "There was an exception retrieving/expanding filebeat zip: $_.Exception" -Severity "Error"
            throw "There was an exception retrieving/expanding filebeat zip: $_.Exception"
            break
        }

        Write-Host "Attempting to install Filebeat"
        Write-Log -LogPath $FullLogPath -Message "Attempting to install Filebeat" -Severity "Info"

        Write-Host "Humio Token is $HumioIngestToken"
        Write-Log -LogPath $FullLogPath -Message "Humio Token is $HumioIngestToken" -Severity "Info"
        
        $filebeatLocation = 'C:\Program Files\Filebeat'
        cd $filebeatLocation
        Try {
            Write-Host "Running custom filebeat installation function"
            Write-Log -LogPath $FullLogPath -Message "Running custom filebeat installation function" -Severity "Info"
            Install-CustomFilebeat -HumioIngestToken "$HumioIngestToken" -FullLogPath $FullLogPath -FilebeatLocation $FilebeatLocation -ErrorAction Stop 
            cd $beforeCd
        }
        Catch {
            cd $beforeCd
            Write-Host "There was an exception installing Filebeat: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message $_.Exception -Severity "Error"
            throw "There was an exception installing Filebeat: $_.Exception"
            break
        }
    }

    Write-Host "Retrieving filebeat config"
    Write-Log -LogPath $FullLogPath -Message "Retrieving filebeat config" -Severity "Info"

    Write-Host "Attempting to retrieve filebeat config"
    Write-Log -LogPath $FullLogPath -Message "Attempting to retrieve filebeat config" -Severity "Info"
    Try {
        Get-FilebeatConfig -FullLogPath $FullLogPath -ErrorAction Stop
    }
    Catch {
        Write-Host "There was an exception retrieving the filebeat config: $_.Exception"
        Write-Log -LogPath $FullLogPath -Message "There was an exception retrieving the filebeat config: $_.Exception" -Severity "Error"
        throw "There was an exception retrieving the filebeat config: $_.Exception"
        break
    }

    Write-Host "Attempting to start filebeat service if it's not running"
    Write-Log -LogPath $FullLogPath -Message "Attempting to start filebeat service if it's not running" -Severity "Info"
    # If ((Get-Service -Name filebeat).Status -ne "Running") {
    #     Try {
    #         Write-Host "Filebeats service was not running, trying to start it now"
    #         Write-Log -LogPath $FullLogPath -Message "Filebeats service was not running, trying to start it now" -Severity "Info"
    #         Start-FilebeatService -FullLogPath $FullLogPath -ErrorAction Stop
    #     }
    #     Catch {
    #         Write-Host "There was an exception starting the filebeat service: $_.Exception"
    #         # Write-Log -LogPath $FullLogPath -Message "There was an exception starting the filebeat service: $_.Exception" -Severity "Error"
    #         throw "There was an exception starting the filebeat service: $_.Exception"
    #         break
    #     }
    # }
    # Else {
    # Write-Host "Filebeat service was running, "
    # Write-Log -LogPath $FullLogPath -Message "Filebeat service was running, " -Severity "Info"
    # }

    Write-Host "Confirming filebeat service is running"
    Write-Log -LogPath $FullLogPath -Message "Confirming filebeat service is running" -Severity "Info"
    If (!(Confirm-FilebeatServiceRunning -FullLogPath $FullLogPath)) {
        Try {
            Write-Host "Filebeats service was not running, trying to start it now"
            Write-Log -LogPath $FullLogPath -Message "Filebeats service was not running, trying to start it now" -Severity "Info"
            Start-FilebeatService -FullLogPath $FullLogPath -ErrorAction Stop
            If (!(Confirm-FilebeatServiceRunning -FullLogPath $FullLogPath -ErrorAction Stop)) {
                throw 'Filebeat service still not running after attempting to start it.'
                break
            }
        }
        Catch {
            Write-Host "There was an exception confirming the running of the filebeat service: $_.Exception"
            Write-Log -LogPath $FullLogPath -Message "There was an exception confirming the running of the filebeat service: $_.Exception" -Severity "Error"
            throw "There was an exception confirming the running of the filebeat service: $_.Exception"
            break
        }
    }
    Else {
        Write-Host "Filebeats service is running, exiting script now"
        Write-Log -LogPath $FullLogPath -Message "Filebeats service is running, exiting script now" -Severity "Info"
    }

    Write-Host "$MyInvocation.MyCommand.Name finished without throwing error"
    Write-Log -LogPath $FullLogPath -Message "$MyInvocation.MyCommand.Name finished without throwing error" -Severity "Info"
}

function Install-CustomFilebeat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken,

        [Parameter(Mandatory = $true)]
        [string] $FullLogPath,

        [Parameter(Mandatory = $true)]
        [string] $FilebeatLocation
    )

    # Delete and stop the service if it already exists.
    Write-Host "Checking for existing Filebeat service again."
    Write-Log -LogPath $FullLogPath -Message "Checking for existing Filebeat service again." -Severity "Info"

    if (Get-Service filebeat -ErrorAction SilentlyContinue) {
        Write-Host "Filebeat service existed"
        Write-Log -LogPath $FullLogPath -Message "Filebeat service existed" -Severity "Info"
        $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
        $service.StopService()
        Start-Sleep -s 1
        $service.delete()
    }

    Write-Host "Trying to get workdir"
    $elasticToken = "output.elasticsearch.password=$HumioIngestToken"
    Write-Host "Elastic setting is $elasticToken"
    # Create the new service.
    New-Service -name filebeat `
    -displayName Filebeat `
    -binaryPathName "`"$FilebeatLocation\filebeat.exe`" -c `"$FilebeatLocation\filebeat.yml`" -path.home `"$FilebeatLocation`" -path.data `"C:\ProgramData\filebeat`" -path.logs `"C:\ProgramData\filebeat\logs`" -E `"$elasticToken`""

    # Attempt to set the service to delayed start using sc config.
    Try {
        Start-Process -FilePath sc.exe -ArgumentList 'config filebeat start=delayed-auto'
    }
    Catch { 
        throw "There was an exception starting filebeat process: $_.Exception"
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
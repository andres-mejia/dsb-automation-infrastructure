function Start-Log {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LogName,

        [Parameter(Mandatory=$true)]
        [string]$ScriptVersion
    )

    If (-Not (Test-Path $LogPath)) {
        Write-Host "There was no directory at $LogPath, trying to create it now"
        Try {
            New-Item -ItemType Directory -Path $LogPath -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Host "There was an error creating $LogPath"
            Throw "There was an error creating $LogPath: $_.Exception"
        }
    }
    $logFullPath = Join-Path -Path $LogPath -ChildPath $LogName
    #Check if file exists and delete if it does
    If(-Not (Test-Path -Path $logFullPath)){
        Write-Host "There was no logfile at $logFullPath, trying to create it now"
        Try {
            New-Item -Path $LogPath -Name $LogName -ItemType File
        }
        Catch {
            Write-Host "There was an error creating $logFullPath"
            Throw "There was an error creating $logFullPath: $_.Exception"
        }
    }
}

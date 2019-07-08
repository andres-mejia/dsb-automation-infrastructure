function Log-Start {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [Parameter(Mandatory=$true)]
        [string]$LogName,

        [Parameter(Mandatory=$true)]
        [string]$ScriptVersion
    )

    Process{
      $logFullPath = Join-Path -Path $LogPath -ChildPath $LogName
      #Check if file exists and delete if it does
      If(!(Test-Path -Path $logFullPath)){
        New-Item -Path $LogPath -Value $LogName -ItemType File
      }

      Write-Log -LogPath $logFullPath -Message "Connect-RobotOrchestrator started for $env:computername" -Severity "Info"
    }
}

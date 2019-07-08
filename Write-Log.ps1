<#
  .SYNOPSIS
    Writes to a log file
  .DESCRIPTION
    Appends a new line to the end of the specified log file
  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write to. Example: C:\Windows\Temp\Test_Script.log
  .PARAMETER LineValue
    Mandatory. The string that you want to write to the log
  .INPUTS
    Parameters above
  .OUTPUTS
    None
#>
function Write-Log
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('Info','Warn','Error')]
        [string]$Severity = 'Info',

        [Parameter()]
        [boolean]$ExitGracefully
    )

    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $logString = "$now $Severity message='$Message' env=$Environment timeStamp=$now level=$Severity pcName=$env:computername"
    Add-Content -Path $LogPath -Value $logString

    If ($ExitGracefully -eq $True){
        Log-Finish -LogPath $LogPath
        Break
    }
}
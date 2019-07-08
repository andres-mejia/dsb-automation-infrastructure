<#
  .SYNOPSIS
    Write closing logging data & exit
  .DESCRIPTION
    Writes finishing logging data to specified log and then exits the calling script
  .PARAMETER LogPath
    Mandatory. Full path of the log file you want to write finishing data to. Example: C:\Windows\Temp\Script.log
  .PARAMETER NoExit
    Optional. If this is set to True, then the function will not exit the calling script, so that further execution can occur
  .INPUTS
    Parameters above
  .OUTPUTS
    None
#>
function Log-Finish {

    [CmdletBinding()]

    param (
        [Parameter(Mandatory=$false)]
        [string]$NoExit
    )

    Process{
      #Exit calling script if NoExit has not been specified or is set to False
      If(!($NoExit) -or ($NoExit -eq $False)){
        Exit
      }
    }
}

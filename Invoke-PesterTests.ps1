<#
    Invoke Pester Test from VSTS Release Task
#>

#region call Pester script
Write-Host "Calling Pester tests"
#Invoke-Pester -Script $TestScript -PassThru
$result = Invoke-Pester -PassThru
if ($result.failedCount -ne 0) { 
    Write-Error "Pester returned errors"
}
#endregion
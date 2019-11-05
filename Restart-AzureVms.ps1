$VmsToRestart = Get-AutomationVariable -Name 'VmsToRestart'
$Environment = Get-AutomationVariable -Name 'Environment'
$AzureSubscriptionId = Get-AutomationVariable -Name 'AzureSubscriptionId'

$ErrorActionPreference = "stop"

try {
    $currentTime = (Get-Date).ToUniversalTime()

    Write-Verbose "Authenticating to Azure with service principal and certificate" -Verbose
    $ConnectionAssetName = "AzureRunAsConnection"
    Write-Verbose "Get connection asset: $ConnectionAssetName" -Verbose
    $Conn = Get-AutomationConnection -Name $ConnectionAssetName
    if (!$Conn)
    {
        Write-Verbose "Runasconnection was null" -Verbose
        throw "Could not retrieve connection asset: $ConnectionAssetName. Check that this asset exists in the Automation account."
        break
    }
    else {
        Write-Verbose "Runasconnection was not null" -Verbose
        Write-Verbose "Automation Connection is $Conn" -Verbose
    }
    Write-Verbose "Authenticating to Azure with service principal." -Verbose

    Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint | Write-Verbose
    Write-Verbose "Setting subscription to work against: $AzureSubscriptionId" -Verbose
    Set-AzureRmContext -SubscriptionId $AzureSubscriptionId -ErrorAction Stop

    $ResourceGroupName = "ROBOTICS-ROBOT-MACHINES-$Environment"
    Write-Verbose "Resource Group is: $ResourceGroupName" -Verbose

    $SplitVms = $VmsToRestart.Split(",")

    Write-Verbose "Processing [$($SplitVms.length)] virtual machines found in subscription" -Verbose
    for ($i=0; $i -lt $SplitVms.length; $i++) {
        $VmName = $SplitVms[$i]

        Write-Verbose "Attempting to shutdown Azure machine: $VmName in resource group: $ResourceGroupName" -Verbose
        $StopMachineCommand = Stop-AzureRmVM -Name $VmName -ResourceGroupName $ResourceGroupName -Force
        $IsSuccess = $StopMachineCommand.IsSuccessStatusCode
        Write-Verbose "Status code is $IsSuccess" -Verbose
        if (!($StopMachineCommand.IsSuccessStatusCode)) {
            Write-Verbose "Stop-AzureRmVm failed for machine $VmName with error: $($StopMachineCommand.Error)"
            throw "Stop-AzureRmVm failed for machine $VmName with error: $($StopMachineCommand.Error)"
            break
        }
        Write-Verbose "Successfully shutdown Azure machine: $VmName" -Verbose

        Write-Verbose "Trying to start Azure Machine: $VmName" -Verbose

        $StartMachineCommand = Start-AzureRmVM -Name $VmName -ResourceGroupName $ResourceGroupName
        $IsSuccess = $StartMachineCommand.IsSuccessStatusCode
        Write-Verbose "Status code is $IsSuccess" -Verbose
        if (!($StartMachineCommand.IsSuccessStatusCode)) {
            Write-Verbose "Start-AzureRmVm failed for machine $VmName with error: $($StartMachineCommand.Error)"
            throw "Start-AzureRmVm failed for machine $VmName with error: $($StartMachineCommand.Error)"
            break
        }
    }
}
catch
{
    $errorMessage = $_.Exception.Message
    Write-Verbose "There was an error, message: $errorMessage" -Verbose
    throw "Unexpected exception: $errorMessage"
}
finally
{
    Write-Verbose "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))" -Verbose
}
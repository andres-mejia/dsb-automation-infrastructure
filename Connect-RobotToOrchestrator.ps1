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

[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $RobotKey,

        [Parameter(Mandatory = $true)]
        [string] $Environment
    )

$robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
Write-Host "Robot exe is $robotExePath"
Write-Log -LogPath $LogFile -Message "Robot exe is $robotExePath" -Severity 'Info'

if(!(Test-Path $robotExePath)) {
    Throw "No robot exe was found on the $env:computername"
} else {
    Write-Host "Robot exe found at $robotExePath"
    Write-Log -LogPath $LogFile -Message "Robot exe found at $robotExePath" -Severity 'Info'
}

Try {
    # $orchMachines = "$machineKeysUrl/api/v1/machines/$tenant"
    # Write-Host "Url for retrieving machine keys is $orchMachines"
    # $wc = New-Object System.Net.WebClient
    # $machineString = $wc.DownloadString($orchMachines)
    # Write-Host "Machines are $machineString"
    # $machines =  $machineString | ConvertFrom-Json

    # $RobotKey = $null
    # ForEach ($machine in $machines) {
    #     If ($env:computername -eq $machine.name) {
    #         $RobotKey = $machine.key
    #     }
    # $RobotKey

    # If ($RobotKey -eq $null) {
    #     Throw ('No license key found for machine: $env:computername')
    # }

    Write-Log -LogPath $LogFile -Message "License key for $env:computername is: $RobotKey" -Severity 'Info'
    Write-Host "License key for $env:computername is: $RobotKey"

    # Starting Robot
    Start-Process -filepath $robotExePath -verb runas

    $waitForRobotSVC = waitForService "UiPath Robot*" "Running"

    $env = "dev"
    $orchestratorUrl = "https://orchestrator-app-${Environment}.azure.dsb.dk"
    # if ($waitForRobotSVC -eq "Running") {
    # connect Robot to Orchestrator with Robot key
    Write-Log -LogPath $LogFile -Message "Orchestrator URL to connect to is: $orchestratorUrl" -Severity 'Info'
    Write-Host "Orchestrator URL to connect to is: $orchestratorUrl"
    # if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
    Try {
        $connectRobot = Start-Process -FilePath $robotExePath -Verb runAs -ArgumentList "--connect -url $orchestratorUrl -key $RobotKey"
    }
    Catch {
        if ($_.Exception) {
            Write-Host "There was an error running the robot.exe connect command, exception: $_.Exception"
            Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
        }
        else {
            Write-Host "There was an error running the robot.exe connect command, but the exception was empty"
            Write-Log -LogPath $LogFile -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
        }
        Break
    }
}
Catch {
    if ($_.Exception) {
        Write-Host "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
        Write-Log -LogPath $LogFile -Message $_.Exception -Severity 'Error' -ExitGracefully $True
    }
    else {
        Write-Host "There was an error connecting the machine to $orchMachines, but the exception was empty"
        Write-Log -LogPath $LogFile -Message "There was an error, but it was blank" -Severity 'Error' -ExitGracefully $True
    }
    Break
}

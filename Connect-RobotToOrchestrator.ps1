Param (
    [Parameter(Mandatory = $true)]
    [string] $LogPath,

    [Parameter(Mandatory = $true)]
    [string] $LogName,

    [Parameter(Mandatory = $true)]
    [string] $RobotKey,

    [Parameter(Mandatory = $true)]
    [string] $Environment
)

$p = [Environment]::GetEnvironmentVariable("PSModulePath")
$p += ";C:\Program Files\WindowsPowerShell\Modules\"
[Environment]::SetEnvironmentVariable("PSModulePath", $p)

Import-Module Dsb.RobotOrchestration

$fullLogPath = Join-Path -Path $LogPath -ChildPath $LogName
Start-Log -LogPath $LogPath -LogName $LogName

$robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
Write-Host "Robot exe is $robotExePath"
Write-Log -LogPath $fullLogPath -Message "Robot exe is $robotExePath" -Severity 'Info'

If (-Not (Test-Path $robotExePath)) {
    Throw "No robot exe was found on the $env:computername"
} else {
    Write-Host "Robot exe found at $robotExePath"
    Write-Log -LogPath $fullLogPath -Message "Robot exe found at $robotExePath" -Severity 'Info'
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
    Write-Log -LogPath $fullLogPath -Message "License key for $env:computername is: $RobotKey" -Severity 'Info'
    Write-Host "License key for $env:computername is: $RobotKey"

    $service = Get-Service -DisplayName 'UiPath Robot*'
    If ($service.Status -eq "Running") {
        $service | Stop-Service
    }

    Start-Process -filepath $robotExePath -verb runas
    $waitForRobotSVC = waitForService "UiPath Robot*" "Running"

    $orchestratorUrl = "https://orchestrator-app-${Environment}.azure.dsb.dk"
    # if ($waitForRobotSVC -eq "Running") {
    # connect Robot to Orchestrator with Robot key
    Write-Log -LogPath $fullLogPath -Message "Orchestrator URL to connect to is: $orchestratorUrl" -Severity 'Info'
    Write-Host "Orchestrator URL to connect to is: $orchestratorUrl"
    # if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }
    Write-Log -LogPath $fullLogPath -Message "Running robot.exe connection command" -Severity 'Info'
    Write-Host "Running robot.exe connection command"
    Start-Process -FilePath $robotExePath -Wait -Verb runAs -ArgumentList "--disconnect"
    $cmdArgList = @(
        "--connect",
        "-url", "$orchestratorUrl",
        "-key", "$RobotKey"
    )
    $connectOutput = cmd /c $robotExePath $cmdArgList '2>&1'
    If (-Not (($connectOutput -eq $null) -Or ($connectOutput -like "*Orchestrator already connected!*"))) {
        Throw $connectOutput
    }
    Write-Host "Connect robot output is: $connectOutput"
    Write-Log -LogPath $fullLogPath -Message "Connect robot output is: $connectOutput" -Severity 'Info'
}
Catch {
    if ($_.Exception) {
        Write-Host "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
        Write-Log -LogPath $fullLogPath -Message $_.Exception -Severity 'Error'
        Throw "There was an error connecting the machine to $orchMachines, exception: $_.Exception"
    }
    else {
        Write-Host "There was an error connecting the machine to $orchMachines, but the exception was empty"
        Write-Log -LogPath $fullLogPath -Message "There was an error, but it was blank" -Severity 'Error'
        Throw "There was an error connecting the machine to $orchMachines, but the exception was empty"
    }
    Break
}

Write-Log -LogPath $fullLogPath -Message "Robot was connected correctly" -Severity "Info"
Write-Host "Robot was connected correctly"

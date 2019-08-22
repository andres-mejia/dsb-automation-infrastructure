$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDirectory = (Get-Item $here).parent.FullName
$moduleName = "Dsb.RobotOrchestration"

If (Get-Module $moduleName) {
    Remove-Module $moduleName -Force
}
Write-Host "Module is " + "$parentDirectory\$moduleName.psm1"
Import-Module "$parentDirectory\$moduleName.psm1" -Force

Describe "Connection to Orchestrator script" {
    BeforeEach {
        $logName = "connect-robot.log"
        $logPath = "c:/logpath"
        $fullLogPath = Join-Path -Path $logPath -ChildPath $logName

        $orchestratorUrl = "https://my-orchestrator.com"
        $orchestratorApiUrl = "https://my-api.com"
        $myTenant = "my-tenant"
        $apiUrl =  "$orchestratorApiUrl/api/v1/machines/$myTenant"

        Mock -Verifiable -CommandName Start-Log
        Mock -Verifiable -CommandName Write-Log
        Mock -Verifiable -CommandName Wait-ForService
    }

    Context "Correct parameters" {
        It "Correctly makes request for machine keys from dev api" {

            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"
            
            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Running"}
            } -Verifiable
            Mock -Verifiable -CommandName cmd
            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled Download-String -Exactly 1 { $Url -eq $apiUrl -and $FullLogPath -eq $fullLogPath }
        }
    }

    Context "No robot exe found" {
        It "Throws an error when no robot exe is found" {
            
            Mock -Verifiable -CommandName Test-Path -MockWith { return $false }
            Mock -Verifiable -CommandName Write-Log

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Throw
        }
    }
    
    Context "Machine is added correctly to Orchestrator" {
        It "Does not throw error" {

            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Running"}
            } -Verifiable
            Mock -Verifiable -CommandName cmd
            Mock -Verifiable -CommandName Start-Process
            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Not -Throw
        }
    }

    Context "Machine is not added correctly to Orchestrator" {
        It "Throws an error" {

            $machineKeyString = "[{`"name`": `"NotThisPC`", `"key`": `"blah-blah`"}]"
            
            Mock -Verifiable -CommandName cmd
            Mock Get-Service {
                [PSCustomObject]@{Status = "Running"}
            } -Verifiable
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Throw
        }
    }

    Context "Robot exe exists, but service is running" {
        It "Does not try to start service if it is running" {

            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"

            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Running"}
            } -Verifiable
            Mock -Verifiable -CommandName cmd
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled Start-Process -Exactly 0
        }
    }

    Context "Robot exe exists, but service is not running" {
        It "Tries starting robot service if it is not running" {

            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"
            
            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Stopped"}
            } -Verifiable
            Mock -Verifiable -CommandName cmd
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled Start-Process -Exactly 1
            Assert-VerifiableMock
        }
    }

    Context "Tries to connect robot but is unsuccessful" {
        It "Throws an error if connection command does not return expected value" {

            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"
            
            Mock -Verifiable -CommandName cmd -MockWith { return "failed" }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Stopped"}
            } -Verifiable
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Throw
        }
    }

    Context "Tries to connect robot and is successful" {
        It "Does not throw error" {

            $machineKeyString = "[{`"name`": `"$env:computername`", `"key`": `"blah-blah`"}]"
            $machineConnected = " Orchestrator already connected! (Fault Detail is equal to An ExceptionDetail, likely created by IncludeExceptionDetailInFaults=true, whose value is"
            
            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock Get-Service {
                [PSCustomObject]@{Status = "Stopped"}
            } -Verifiable
            Mock -Verifiable -CommandName cmd -MockWith { return $machineConnected }
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -CommandName Download-String -MockWith { return $machineKeyString }

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Not -Throw
        }
    }
}
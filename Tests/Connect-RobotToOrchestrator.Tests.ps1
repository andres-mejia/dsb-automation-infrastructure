$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDirectory = (Get-Item $here).parent.FullName

Describe "Connection to Orchestrator script" {
    BeforeEach {
        $logName = "connect-robot.log"
        $logPath = "c:/logpath"
        $fullLogPath = Join-Path -Path $logPath -ChildPath $logName

        $orchestratorUrl = "https://my-orchestrator.com"
        $orchestratorApiUrl = "https://my-api.com"
        $myTenant = "my-tenant"
        $apiUrl =  "$orchestratorApiUrl/api/v1/machines/$myTenant"

    }
    Context "Correct parameters" {
        It "Correctly makes request for machine keys from dev api" {

            Mock -Verifiable -CommandName Test-Path -MockWith { return $true }
            Mock -Verifiable -ModuleName $moduleName -CommandName Write-Log
            Mock -Verifiable -ModuleName $moduleName -CommandName Wait-ForService
            Mock -Verifiable -CommandName cmd
            Mock -Verifiable -ModuleName $moduleName -CommandName Download-String

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled -ModuleName $moduleName Download-String -Exactly 1 { $Url -eq $apiUrl -and $FullLogPath -eq $fullLogPath }
        }
    }

    Context "No robot exe found" {
        It "Throws an error when no robot exe is found" {
            
            Mock -Verifiable -CommandName Test-Path -MockWith { return $false }
            Mock -Verifiable -ModuleName $moduleName -CommandName Write-Log

            { & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant } | Should -Throw
        }
    }
    # Throws error if machine key not found
    Context "Robot exe exists, but service is running" {
        It "Does not try to start service if it is running" {

            Mock -Verifiable -CommandName cmd
            Mock Get-Service {
                [PSCustomObject]@{Status = "Running"}
            } -Verifiable
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -ModuleName $moduleName -CommandName Write-Log
            Mock -Verifiable -ModuleName $moduleName -CommandName Wait-ForService
            Mock -Verifiable -ModuleName $moduleName -CommandName Download-String

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled Start-Process -Exactly 0
        }
    }

    Context "Robot exe exists, but service is not running" {
        It "Tries starting robot service if it is not running" {

            Mock -Verifiable -CommandName cmd
            Mock Get-Service {
                [PSCustomObject]@{Status = "Stopped"}
            } -Verifiable
            Mock -Verifiable -CommandName Start-Process

            Mock -Verifiable -ModuleName $moduleName -CommandName Write-Log
            Mock -Verifiable -ModuleName $moduleName -CommandName Wait-ForService
            Mock -Verifiable -ModuleName $moduleName -CommandName Download-String

            & $parentDirectory\Connect-RobotToOrchestrator.ps1 -LogPath $logPath -LogName $logName -OrchestratorUrl $orchestratorUrl -OrchestratorApiUrl $orchestratorApiUrl -OrchestratorTenant $myTenant

            Assert-MockCalled Start-Process -Exactly 1
        }
    }
}
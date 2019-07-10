$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDirectory = (Get-Item $here).parent.FullName

$moduleName = "Dsb.RobotOrchestration"
If (Get-Module $moduleName) {
    Remove-Module $moduleName
} 
Import-Module "$parentDirectory/$moduleName.psm1"

Describe 'Write-Log' {

    It 'Creates new directory if logpath does not exist' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -CommandName Test-Path -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName Test-Path { return $true } -ModuleName $moduleName -ParameterFilter { $Path -eq $joinedPath }
        Mock -CommandName New-Item -ModuleName $moduleName

        Start-Log -LogPath $logPath -LogName $logName
        Assert-MockCalled New-Item 1 -ParameterFilter { $ItemType -eq "Directory" } -ModuleName $moduleName
    }
}
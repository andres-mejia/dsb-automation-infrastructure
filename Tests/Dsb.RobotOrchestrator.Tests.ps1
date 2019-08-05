$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDirectory = (Get-Item $here).parent.FullName
$moduleName = "Dsb.RobotOrchestration"

If (Get-Module $moduleName) {
    Remove-Module $moduleName -Force
}
Import-Module "$parentDirectory\$moduleName.psm1" -Force

Describe 'Start-Log' {

    It 'Creates new directory if logpath does not exist' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -Verifiable -CommandName Test-Path -ModuleName $moduleName -MockWith { return $false }
        Mock -Verifiable -CommandName Test-Path { return $true } -ModuleName $moduleName -ParameterFilter { $Path -eq $joinedPath }
        Mock -Verifiable -CommandName New-Item -ModuleName $moduleName

        Start-Log -LogPath $logPath -LogName $logName
        Assert-MockCalled New-Item 1 -ParameterFilter { $ItemType -eq "Directory" } -ModuleName $moduleName
    }

    It 'Creates file if file at file at logpath does not exist' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $logPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath } -MockWith { return $false } -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath -and $PSBoundParameters['Verbose'] -eq $true } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName New-Item -ModuleName $moduleName

        Start-Log -LogPath $logPath -LogName $logName
        Assert-MockCalled New-Item -Exactly 1 -ParameterFilter { $ItemType -eq "File" } -ModuleName $moduleName
    }

    It 'Throws error if logfile not found after created' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $logPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath } -MockWith { return $false } -ModuleName $moduleName
        Mock -Verifiable -CommandName New-Item -ModuleName $moduleName

        { Start-Log -LogPath $logPath -LogName $logName } | Should -Throw 
    }
}

Describe 'Remove-OldFilebeatFolders' {
    It 'Calls remove-item if original filebeats dirs exists' {
        $FilebeatVersion = "7.2.0"
        $unzippedFile = "C:\Program Files\filebeat-$FilebeatVersion-windows-x86"
        $programFileFilebeat = "C:\Program Files\Filebeat"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $unzippedFile -and $PSBoundParameters['Force'] -eq $true }
        
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $programFileFilebeat } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $programFileFilebeat -and $PSBoundParameters['Force'] -eq $true }

        Remove-OldFilebeatFolders -FullLogPath 'fakelog\path' -FilebeatVersion $FilebeatVersion
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq  $unzippedFile -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq  $programFileFilebeat -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
    }
}

Describe 'Get-FilebeatConfig' {

    It 'Calls remove-item for old filebeat config' {
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $true }

        Get-FilebeatConfig -FullLogPath 'fakelog\path'
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq  $filebeatYaml -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
    }

    It 'Calls invoke-webrequest with the correct params' {
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
        $configUri = "https://raw.githubusercontent.com/nkuik/dsb-automation-infrastructure/master/filebeat.yml"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName -ParameterFilter  { $Uri -eq $configUri -and $OutFile -eq $filebeatYaml }
        Mock -Verifiable -CommandName Test-Path -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $true }

        Get-FilebeatConfig -FullLogPath 'fakelog\path'
        Assert-MockCalled Invoke-WebRequest 1 { $Uri -eq $configUri -and $OutFile -eq $filebeatYaml } -ModuleName $moduleName
    }

    It 'Throws error if yaml file not found' {
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $false }

       { Get-FilebeatConfig -FullLogPath 'fakelog\path' } | Should -Throw
    }
}

Describe 'Get-Filebeat' {

    It 'Throws error when provided invalid filebeat version' {
        $logPath = "C:/fake/logpathfake-filebeat.log"
        $downloadPath = "C:/fake/installpath"
        $wrongVersion = "7.1.0"

        { Get-FilebeatZip -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $wrongVersion } | Should -Throw
    }

    It 'Removes previously downloaded filebeat if it exists' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\download"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $fullDownloadPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Expand-Archive -ModuleName $moduleName
        Mock -Verifiable -CommandName Rename-Item -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Get-FilebeatZip -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq $fullDownloadPath -and $PSBoundParameters['Recurse'] -eq $true } -ModuleName $moduleName
    }

    It 'Renames the original zip file to Filebeat' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\download"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"
        $unzippedFile = "C:\Program Files\filebeat-$correctVersion-windows-x86"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $fullDownloadPath } -ModuleName $moduleName
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Expand-Archive -ModuleName $moduleName
        Mock -Verifiable -CommandName Rename-Item -ModuleName $moduleName

        Get-FilebeatZip -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Rename-Item 1 { $Path -eq $fullDownloadPath -and $NewName -eq 'Filebeat' } -ModuleName $moduleName
    }

    It 'Correctly makes the invoke-webrequest request' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\invokeweb"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"
        $url = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-$correctVersion-windows-x86.zip"
        $unzippedFile = "C:\Program Files\filebeat-$correctVersion-windows-x86"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $downloadLocation } -MockWith { return $false } -ModuleName $moduleName
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Expand-Archive -ModuleName $moduleName
        Mock -Verifiable -CommandName Rename-Item -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Get-FilebeatZip -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Invoke-WebRequest -Exactly 1 { $Uri -eq $url -and $OutFile -eq $fullDownloadPath }  -ModuleName $moduleName
    }

    It 'Correctly makes the expand-archive request' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\expandarchive"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $newPath = Join-Path -Path $downloadPath -ChildPath 'Filebeat'
        $correctVersion = "7.2.0"

        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $downloadLocation } -MockWith { return $true } -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Expand-Archive -ModuleName $moduleName
        Mock -Verifiable -CommandName Rename-Item -ModuleName $moduleName
        Mock -Verifiable -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Get-FilebeatZip -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Expand-Archive -Exactly 1 { $Path -eq $newPath -and $DestinationPath -eq 'C:\Program Files' -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
    }
}

Describe 'Install-Filebeat logging' {

    It 'It calls Start-Log' {
        $downloadPath = "C:/fake/installpath"
        $programFileDir = "C:\Program Files\Filebeat"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"

        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $correctVersion = "7.2.0"
        
        Mock -Verifiable -CommandName Get-FilebeatService -ModuleName $moduleName -MockWith { return $true } 

        Mock -Verifiable -CommandName Start-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Stop-FilebeatService -ModuleName $moduleName
        Mock -Verifiable -CommandName Get-FilebeatConfig -ModuleName $moduleName
        Mock -Verifiable -CommandName Start-FilebeatService -ModuleName $moduleName
        Mock -Verifiable -CommandName Confirm-FilebeatServiceRunning -ModuleName $moduleName

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion -HumioIngestToken 'token'
        Assert-MockCalled Start-Log -Exactly 1 {$LogPath -eq $logPath -and $LogName -eq $logName} -ModuleName $moduleName
    }
}

Describe 'Install-Filebeat setup' {
    It 'Stops filebeat service if it exists' {
        $downloadPath = "C:\fake\installpath"
        $programFileDir = "C:\Program Files\Filebeat"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"

        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $correctVersion = "7.2.0"

        Mock -Verifiable -CommandName Get-FilebeatService -ModuleName $moduleName { return $true } 
        Mock -Verifiable -CommandName Start-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Stop-FilebeatService -ModuleName $moduleName
        Mock -Verifiable -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -Verifiable -CommandName Get-FilebeatConfig -ModuleName $moduleName
        Mock -Verifiable -CommandName Start-FilebeatService -ModuleName $moduleName
        Mock -Verifiable -CommandName Confirm-FilebeatServiceRunning -ModuleName $moduleName

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion -HumioIngestToken 'token'
        Assert-MockCalled Stop-FilebeatService -Exactly 1 -ModuleName $moduleName
    }

    It 'Calls Remove-OldFilebeatFolders, calls Install-Filebeat' { 
        $downloadPath = "C:/fake/installpath"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $correctVersion = "7.2.0"
        $programFileDir = "C:\Program Files\Filebeat"
        $unzippedFile = "C:\Program Files\filebeat-$correctVersion-windows-x86"

        Mock -Verifiable -CommandName Get-FilebeatService -ModuleName $moduleName { return $false } 
        Mock -Verifiable -CommandName Start-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName Write-Log -ModuleName $moduleName
        Mock -Verifiable -CommandName cd -ModuleName $moduleName
        Mock -Verifiable -CommandName Get-FilebeatZip -ModuleName $moduleName
        Mock -Verifiable -CommandName Install-CustomFilebeat -ModuleName $moduleName
        Mock -Verifiable -CommandName Get-FilebeatConfig -ModuleName $moduleName
        Mock -Verifiable -CommandName Start-FilebeatService -ModuleName $moduleName
        Mock -Verifiable -CommandName Confirm-FilebeatServiceRunning -ModuleName $moduleName

        Mock -Verifiable -CommandName Remove-OldFilebeatFolders -ModuleName $moduleName -MockWith { return $false }

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion -HumioIngestToken 'token'
        Assert-MockCalled Remove-OldFilebeatFolders -Exactly 1 { $FullLogPath -eq (Join-Path -Path $logPath -ChildPath $logName) -and $FilebeatVersion -eq $correctVersion } -ModuleName $moduleName
        Assert-MockCalled Get-FilebeatZip -Exactly 1 { $FullLogPath -eq (Join-Path -Path $logPath -ChildPath $logName) } -ModuleName $moduleName
    }

}
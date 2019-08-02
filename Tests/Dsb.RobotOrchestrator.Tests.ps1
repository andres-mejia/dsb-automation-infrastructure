$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDirectory = (Get-Item $here).parent.FullName

$moduleName = "Dsb.RobotOrchestration"
If (Get-Module $moduleName) {
    Remove-Module $moduleName
} 
Import-Module "$parentDirectory/$moduleName.psm1"

Describe 'Start-Log' {

    It 'Creates new directory if logpath does not exist' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -CommandName Test-Path -ModuleName $moduleName -MockWith { return $false }
        Mock -CommandName Test-Path { return $true } -ModuleName $moduleName -ParameterFilter { $Path -eq $joinedPath }
        Mock -CommandName New-Item -ModuleName $moduleName

        Start-Log -LogPath $logPath -LogName $logName
        Assert-MockCalled New-Item 1 -ParameterFilter { $ItemType -eq "Directory" } -ModuleName $moduleName
    }

    It 'Creates file if file at file at logpath does not exist' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $logPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath -and $PSBoundParameters['Verbose'] -eq $true } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName New-Item -ModuleName $moduleName

        Start-Log -LogPath $logPath -LogName $logName
        Assert-MockCalled New-Item -Exactly 1 -ParameterFilter { $ItemType -eq "File" } -ModuleName $moduleName
    }

    It 'Throws error if logfile not found after created' {
        $logPath = "C:/fake/path"
        $logName = "fake-logname.log"
        $joinedPath = Join-Path -Path $logPath -ChildPath $logName
        
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $logPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $joinedPath } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName New-Item -ModuleName $moduleName

        { Start-Log -LogPath $logPath -LogName $logName } | Should -Throw 
    }
}

Describe 'Download-Filebeat' {

    It 'Throws error when provided invalid filebeat version' {
        $logPath = "C:/fake/logpathfake-filebeat.log"
        $downloadPath = "C:/fake/installpath"
        $wrongVersion = "7.1.0"

        { Download-Filebeat -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $wrongVersion } | Should -Throw
    }

    It 'Removes previously downloaded filebeat if it exists' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\download"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"

        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $fullDownloadPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Expand-Archive -ModuleName $moduleName
        Mock -CommandName Rename-Item -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Download-Filebeat -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq $fullDownloadPath -and $PSBoundParameters['Recurse'] -eq $true } -ModuleName $moduleName
    }

    It 'Removes the original expanded zip filebeat folder if it exists' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\download"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"
        $unzippedFile = "C:\Program Files\filebeat-$correctVersion-windows-x86"

        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $fullDownloadPath } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Expand-Archive -ModuleName $moduleName
        Mock -CommandName Rename-Item -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $true } -ModuleName $moduleName

        Download-Filebeat -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq $unzippedFile -and $PSBoundParameters['Recurse'] -eq $true -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
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

        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $downloadLocation } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Expand-Archive -ModuleName $moduleName
        Mock -CommandName Rename-Item -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Download-Filebeat -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Invoke-WebRequest 1 { $Uri -eq $url -and $OutFile -eq $fullDownloadPath }  -ModuleName $moduleName
    }

    It 'Correctly makes the expand-archive request' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:\fake\expandarchive"
        $filebeatZip = "filebeat.zip"
        $fullDownloadPath = Join-Path -Path $downloadPath -ChildPath $filebeatZip
        $correctVersion = "7.2.0"

        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $downloadLocation } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Expand-Archive -ModuleName $moduleName
        Mock -CommandName Rename-Item -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $false } -ModuleName $moduleName

        Download-Filebeat -FullLogPath $logPath -DownloadPath $downloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Expand-Archive -Exactly 1 { $Path -eq $fullDownloadPath -and $DestinationPath -eq 'C:\Program Files' -and $PSBoundParameters['Force'] -eq $true } -ModuleName $moduleName
    }
}

Describe 'Install-Filebeat' {
    It 'It calls Start-Log' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:/fake/installpath"
        $correctVersion = "7.2.0"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
        $programFileDir = "C:\Program Files\Filebeat"

        Mock -CommandName Start-Log -ModuleName $moduleName
        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Get-Service -ModuleName $moduleName -MockWith { return $false }
        Mock -CommandName Get-WmiObject -ModuleName $moduleName { return @{State = "Running"}}
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $programFileDir } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq "$downloadPath\filebeat.zip" } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName cd -ModuleName $moduleName
        Mock -CommandName Download-Filebeat -ModuleName $moduleName
        Mock -CommandName Install-CustomFilebeat -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Start-Service -ModuleName $moduleName

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Start-Log -Exactly 1 {$LogPath -eq $logPath -and $LogName -eq $logName} -ModuleName $moduleName
    }

    It 'Stops filebeat service if it exists' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:/fake/installpath"
        $correctVersion = "7.2.0"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
        $programFileDir = "C:\Program Files\Filebeat"

        Mock -CommandName Start-Log -ModuleName $moduleName
        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Get-Service -ModuleName $moduleName -MockWith { return $true }
        Mock -CommandName Stop-FilebeatService -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $programFileDir } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq "$downloadPath\filebeat.zip" } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName cd -ModuleName $moduleName
        Mock -CommandName Download-Filebeat -ModuleName $moduleName
        Mock -CommandName Install-CustomFilebeat -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Start-Service -ModuleName $moduleName

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Stop-FilebeatService -Exactly 1 -ModuleName $moduleName
    }

    It 'Removes any filebeat dirs in program files if they exist and service does not exist' {
        $logPath = "C:/fake/logpath"
        $logName = "fake-filebeat.log"
        $downloadPath = "C:/fake/installpath"
        $correctVersion = "7.2.0"
        $filebeatYaml = "C:\Program Files\Filebeat\filebeat.yml"
        $unzippedFile = "C:\Program Files\filebeat-$correctVersion-windows-x86"
        $programFileDir = "C:\Program Files\Filebeat"

        Mock -CommandName Start-Log -ModuleName $moduleName
        Mock -CommandName Write-Log -ModuleName $moduleName
        Mock -CommandName Get-Service -ModuleName $moduleName -MockWith { return $false }
        
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $unzippedFile } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $unzippedFile }
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $programFileDir } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $programFileDir }

        Mock -CommandName Test-Path -ParameterFilter { $Path -eq "$downloadPath\filebeat.zip" } -MockWith { return $false } -ModuleName $moduleName
        Mock -CommandName cd -ModuleName $moduleName
        Mock -CommandName Download-Filebeat -ModuleName $moduleName
        Mock -CommandName Get-WmiObject -ModuleName $moduleName { return @{State = "Running"}}
        Mock -CommandName Install-CustomFilebeat -ModuleName $moduleName
        Mock -CommandName Remove-Item -ModuleName $moduleName -ParameterFilter { $Path -eq $filebeatYaml -and $PSBoundParameters['Force'] -eq $true }
        Mock -CommandName Invoke-WebRequest -ModuleName $moduleName
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq $filebeatYaml } -MockWith { return $true } -ModuleName $moduleName
        Mock -CommandName Start-Service -ModuleName $moduleName

        Install-Filebeat -LogPath $logPath -LogName $logName -DownloadPath $DownloadPath -FilebeatVersion $correctVersion
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq  $unzippedFile } -ModuleName $moduleName
        Assert-MockCalled Remove-Item -Exactly 1 { $Path -eq  $programFileDir } -ModuleName $moduleName
    }
}
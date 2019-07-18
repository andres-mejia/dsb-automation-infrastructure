[CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $HumioIngestToken
    )

# Delete and stop the service if it already exists.
if (Get-Service filebeat -ErrorAction SilentlyContinue) {
  $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat'"
  $service.StopService()
  Start-Sleep -s 1
  $service.delete()
}

$workdir = Split-Path $MyInvocation.MyCommand.Path
$elasticToken = "output.elasticsearch.password=$HumioIngestToken"
Write-Host "Elastic setting is $elasticToken"
# Create the new service.
New-Service -name filebeat `
  -displayName Filebeat `
  -binaryPathName "`"$workdir\filebeat.exe`" -c `"$workdir\filebeat.yml`" -path.home `"$workdir`" -path.data `"C:\ProgramData\filebeat`" -path.logs `"C:\ProgramData\filebeat\logs`" -E `"output.elasticsearch.password=AwhoOLTo8KsRv6S3IIbQvUxR4uyw3tvQY8YVmHIkqoCk`""

# Attempt to set the service to delayed start using sc config.
Try {
  Start-Process -FilePath sc.exe -ArgumentList 'config filebeat start=delayed-auto'
}
Catch { Write-Host "An error occured setting the service to delayed start." -ForegroundColor Red }

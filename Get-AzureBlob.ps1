add-type @"
  using System.Net;
  using System.Security.Cryptography.X509Certificates;
  public class TrustAllCertsPolicy : ICertificatePolicy {
      public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,
                                        WebRequest request, int certificateProblem) {
          return true;
      }
   }
"@
 
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

"https://roboticsrobovmstoredev.blob.core.windows.net/robotvmconfigblob/PR_SMS_UDSENDELSE.zip"
$storageAccount = "roboticsrobovmstoredev"
$storageContainer = "robotvmconfigblob"
$storageAccountKey = "nqduNPpXWwpUix1/aLjS11Z7G7JVZ8HKZIA9aMRfyc9drxknhj4X4faDKt0oZhuLtst2xpjsdRNIWYHo3hpEYA=="
$blobFile = "PR_SMS_UDSENDELSE.zip"

$blobUrl = "https://$storageAccount.blob.core.windows.net/$storageContainer/$blobFile"

$d = Get-Date
$formattedDate = $d.GetDateTimeFormats()[-29]

$verb = "GET"
$contentEncoding = ""   
$contentLanguage = ""
$contentLength = ""
$contentMd5 = ""
$contentType = ""
$date = ""
$ifModifiedSince = ""
$ifMatch = ""
$ifNoneMatch = ""  
$ifUnmodifiedSince = ""
$range = ""
$canonicalizedHeaders = "/$storageAccount /$storageContainer\ncomp:metadata\nrestype:container\ntimeout:20"
$canonicalizedResource = "x-ms-date:$formattedDate\nx-ms-version:2015-02-21\n"

$stringToSign = $verb + "\n" +  
               $contentEncoding + "\n" +  
               $contentLanguage + "\n" +  
               $contentLength+ "\n" +  
               $contentMd5 + "\n" +  
               $contentType + "\n" +  
               $date + "\n" +  
               $ifModifiedSince + "\n" +  
               $ifMatch + "\n" +  
               $ifNoneMatch + "\n" +  
               $ifUnmodifiedSince + "\n" +  
               $range + "\n" +  
               $canonicalizedHeaders +   
               $canonicalizedResource

$hmacsha = New-Object System.Security.Cryptography.HMACSHA256
$hmacsha.key = [Text.Encoding]::ASCII.GetBytes($storageAccountKey)
$signature = $hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($stringToSign))
$signature = [Convert]::ToBase64String($signature)

$sharedKey = "${storageAccount}:$signature"

Write-Host $blobUrl
Write-Host $signature
Write-Host $sharedKey

$headers = @{ Authorization = "SharedKey $sharedKey" }
$responseData = Invoke-WebRequest -Uri $blobUrl -Method Get -Headers $headers -UseBasicParsing
 

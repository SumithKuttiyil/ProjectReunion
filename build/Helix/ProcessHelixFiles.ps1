Param(
    [string]$AccessToken = $env:SYSTEM_ACCESSTOKEN,
    [string]$HelixAccessToken = $env:HelixAccessToken,
    [string]$CollectionUri = $env:SYSTEM_COLLECTIONURI,
    [string]$TeamProject = $env:SYSTEM_TEAMPROJECT,
    [string]$BuildUri = $env:BUILD_BUILDURI,
    [string]$OutputFolder = "HelixOutput"
)

$helixLinkFile = "$OutputFolder\LinksToHelixTestFiles.html"
$visualTreeVerificationFolder = "$OutputFolder\UpdatedVisualTreeVerificationFiles"

$accessTokenParam = ""
if($HelixAccessToken)
{
    Write-Host "!!!!helix access token is present!!!!"
    $accessTokenParam = "?access_token=$HelixAccessToken"
}

function Generate-File-Links
{
    Param ([Array[]]$files,[string]$sectionName)
    if($files.Count -gt 0)
    {
        Out-File -FilePath $helixLinkFile -Append -InputObject "<div class=$sectionName>"
        Out-File -FilePath $helixLinkFile -Append -InputObject "<h4>$sectionName</h4>"
        Out-File -FilePath $helixLinkFile -Append -InputObject "<ul>"
        foreach($file in $files)
        {
            Out-File -FilePath $helixLinkFile -Append -InputObject "<li><a href=$($file.Link)>$($file.Name)</a></li>"
        }
        Out-File -FilePath $helixLinkFile -Append -InputObject "</ul>"
        Out-File -FilePath $helixLinkFile -Append -InputObject "</div>"
    }
}

#Create output directory
New-Item $OutputFolder -ItemType Directory

$azureDevOpsRestApiHeaders = @{
    "Accept"="application/json"
    "Authorization"="Basic $([System.Convert]::ToBase64String([System.Text.ASCIIEncoding]::ASCII.GetBytes(":$AccessToken")))"
}

. "$PSScriptRoot/AzurePipelinesHelperScripts.ps1"

$queryUri = GetQueryTestRunsUri -CollectionUri $CollectionUri -TeamProject $TeamProject -BuildUri $BuildUri -IncludeRunDetails
Write-Host "queryUri = $queryUri"

$testRuns = Invoke-RestMethod -Uri $queryUri -Method Get -Headers $azureDevOpsRestApiHeaders
$webClient = New-Object System.Net.WebClient
[System.Collections.Generic.List[string]]$workItems = @()

foreach ($testRun in $testRuns.value)
{
    $testResults = Invoke-RestMethod -Uri "$($testRun.url)/results?api-version=5.1" -Method Get -Headers $azureDevOpsRestApiHeaders
    foreach ($testResult in $testResults.value)
    {
        if ($testResult.comment -ne $null)
        {
            $info = ConvertFrom-Json $testResult.comment
            $helixJobId = $info.HelixJobId
            $helixWorkItemName = $info.HelixWorkItemName
            $workItem = $Configuration + "_" + $Platform + "_" + $helixJobId + "_" + $helixWorkItemName
            if (-not $workItems.Contains($workItem))
            {
                $workItems.Add($workItem)
                $filesQueryUri = "https://helix.dot.net/api/2019-06-17/jobs/$helixJobId/workitems/$helixWorkItemName/files$accessTokenParam"
                Write-Host "files query uri = $filesQueryUri"
                $files = Invoke-RestMethod -Uri $filesQueryUri -Method Get
                Write-Host "files = $files"
                $screenShots = $files | where { $_.Name.EndsWith(".jpg") }
                Write-Host "screenshots = $screenShots"
                $dumps = $files | where { $_.Name.EndsWith(".dmp") }
                $logs = $files | where { $_.Name.EndsWith(".log") }
                $visualTreeVerificationFiles = $files | where { $_.Name.EndsWith(".xml") -And (-Not $_.Name.Contains('testResults')) }
                $pgcFiles = $files | where { $_.Name.EndsWith(".pgc") }
                if ($screenShots.Count + $dumps.Count + $visualTreeVerificationFiles.Count + $pgcFiles.Count -gt 0)
                {
                    Write-Host "we got files"
                    if(-Not $isTestRunNameShown)
                    {
                        Write-Host "not isTestRunNameSHown"
                        Out-File -FilePath $helixLinkFile -Append -InputObject "<h2>$($testRun.name)</h2>"
                        $isTestRunNameShown = $true
                    }
                    Out-File -FilePath $helixLinkFile -Append -InputObject "<h3>$helixWorkItemName</h3>"
                    Generate-File-Links $screenShots "Screenshots"
                    Generate-File-Links $dumps "CrashDumps"
                    Generate-File-Links $logs "Logs"
                    Generate-File-Links $visualTreeVerificationFiles "visualTreeVerificationFiles"
                    Generate-File-Links $pgcFiles "PGC files"
                    $misc = $files | where { ($screenShots -NotContains $_) -And ($dumps -NotContains $_) -And ($visualTreeVerificationFiles -NotContains $_) -And ($pgcFiles -NotContains $_) }
                    Generate-File-Links $misc "Misc"

                    if( -Not (Test-Path $visualTreeVerificationFolder) )
                    {
                        New-Item $visualTreeVerificationFolder -ItemType Directory
                    }
                    foreach($screenShot in $screenShots)
                    {
                        $destination = "$OutputFolder\screenshots\$($screenShot.Name)"
                        Write-Host "Copying $($screenShot.Name) to $destination"
                        $link = "$($screenShot.Link)$accessTokenParam"
                        $webClient.DownloadFile($link, $destination)
                    }
                    foreach($log in $logs)
                    {
                        $destination = "$OutputFolder\screenshots\$($log.Name)"
                        Write-Host "Copying $($log.Name) to $destination"
                        $link = "$($log.Link)$accessTokenParam"
                        $webClient.DownloadFile($link, $destination)
                    }
                    foreach($verificationFile in $visualTreeVerificationFiles)
                    {

                        $destination = "$visualTreeVerificationFolder\$($verificationFile.Name)"
                        Write-Host "Copying $($verificationFile.Name) to $destination"
                        $link = "$($verificationFile.Link)$accessTokenParam"
                        $webClient.DownloadFile($link, $destination)
                    }

                    foreach($pgcFile in $pgcFiles)
                    {
                        $flavorPath = $pgcFile.Name.Split('.')[0]
                        $archPath = $pgcFile.Name.Split('.')[1]
                        $fileName = $pgcFile.Name.Remove(0, $flavorPath.length + $archPath.length + 2)
                        $fullPath = "$OutputFolder\PGO\$flavorPath\$archPath"
                        $destination = "$fullPath\$fileName"

                        Write-Host "Copying $($pgcFile.Name) to $destination"

                        if (-Not (Test-Path $fullPath))
                        {
                            New-Item $fullPath -ItemType Directory
                        }

                        $link = "$($pgcFile.Link)$accessTokenParam"
                        $webClient.DownloadFile($link, $destination)
                    }
                }
            }
        }
    }
}

if(Test-Path $visualTreeVerificationFolder)
{
    $verificationFiles = Get-ChildItem $visualTreeVerificationFolder
    $prefixList = @()

    foreach($file in $verificationFiles)
    {
        Write-Host "Copying $($file.Name) to $visualTreeVerificationFolder"
        Move-Item $file.FullName "$visualTreeVerificationFolder\$($file.Name)" -Force
    }
}
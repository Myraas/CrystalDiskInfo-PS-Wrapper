Clear-Host

$sendAlertOnPass = $true
$setNinjaSmartStatus = $true
$enableVersionCheck = $true
$predictiveFailureEvent = $true

$desiredVersion = "CrystalDiskInfo 9.2.3"
$webhookUrl = "Your webhook URL here"
$CrystalUrl = "CrystalDiskInfo EXE Installer URL Here"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Set-Location C:\

function Format-SMARTInfo {
    param (
        $hostname,
        $cautionCount,
        $badCount
    )

    $formattedSMARTInfo = @"
$hostname : CrystalDiskInfo SMART test is reporting 'Caution' or 'Bad' indicators.

Number of 'Caution' indicators: $cautionCount

Number of 'Bad' indicators: $badCount
"@
    return $formattedSMARTInfo
}

function Format-PassInfo {
    param (
        $hostname
    )

    $formattedPassInfo = @"
$hostname : CrystalDiskInfo SMART test is reporting a pass.
"@
    return $formattedPassInfo
}

function Send-WebhookMessage {
    param (
        $webhookUrl,
        $message
    )

    $payload = @{
        text = $message
    }

    try {
        Invoke-WebRequest -Uri $webhookUrl -Method POST -Body (ConvertTo-Json $payload) -ContentType "application/json" -UseBasicParsing
        Write-Host "Webhook message sent successfully."
    } catch {
        Write-Error "Failed to send webhook message. Error: $_"
    }
}

function Set-NinjaSmartStatus {
    param (
        $status
    )

    try {
        Ninja-Property-Set smart $status
        Write-Host "Ninja smart status set to $status."
    } catch {
        Write-Output "Error: Ninja-Property-Set command not found. Please ensure it is installed and available in the PATH."
    }
}

function Install-CrystalDiskInfo {
    param (
        $installerUrl
    )

    $installerPath = "C:\temp\CrystalDiskInfoInstaller.exe"

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        Write-Host "CrystalDiskInfo installer downloaded successfully."
    } catch {
        Write-Error "Failed to download CrystalDiskInfo installer. Error: $_"
        Stop-Transcript
        exit 1
    }
    try {
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /NORESTART" -NoNewWindow -Wait
        Start-Sleep -Seconds 10
        Write-Host "CrystalDiskInfo installed successfully."
    } catch {
        Write-Error "Failed to install CrystalDiskInfo. Error: $_"
        Stop-Transcript
        exit 1
    }
}

function Check-CrystalDiskInfoVersion {
    param (
        $filePath,
        $desiredVersion
    )

    try {
        $diskInfoContent = Get-Content -Path $filePath -TotalCount 10
        $versionLine = $diskInfoContent | Select-String -Pattern $desiredVersion

        if ($versionLine -ne $null) {
            Write-Host "CrystalDiskInfo version is correct: $desiredVersion."
            return $true
        } else {
            Write-Host "CrystalDiskInfo version is incorrect. Expected: $desiredVersion."
            return $false
        }
    } catch {
        Write-Error "Failed to read CrystalDiskInfo version. Error: $_"
        return $false
    }
}

function Log-PredictiveFailureEvent {
    param (
        $message
    )

    try {
        $eventID = 2094
        $source = "PredictiveFailure"

        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
            Write-Host "Event source '$source' created."
        }

        Write-EventLog -LogName Application -Source $source -EventID $eventID -EntryType Warning -Message $message
        Write-Host "Predictive failure event logged successfully."
    } catch {
        Write-Error "Failed to log predictive failure event. Error: $_"
    }
}

Write-Host "Checking if C:\temp directory exists."
if (Test-Path -Path C:\temp) {
    Write-Host "C:\temp directory exists. Cleaning up old SMART files."
    Get-ChildItem -Path "C:\temp\SMART*.txt" -Force | Remove-Item -Force -ErrorAction SilentlyContinue

    $SpecificFiles = @("CrystalDiskInfo*")

    foreach ($File in $SpecificFiles) {
        $FilePath = Join-Path -Path C:\temp -ChildPath $File
        if (Test-Path -Path $FilePath) {
            Remove-Item -Path $FilePath -Force -ErrorAction SilentlyContinue
            Write-Host "Removed file: $FilePath"
        }
    }
} else {
    Write-Host "C:\temp directory does not exist. Creating directory."
    New-Item -Path C:\temp -ItemType Directory
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_THHmmss"
Write-Host "Starting transcript logging to C:\temp\SMART_$Timestamp.txt"
Start-Transcript -Path "C:\temp\SMART_$Timestamp.txt"
[System.DateTime]::Now

$diskInfoExePath = "$($Env:ProgramFiles)\CrystalDiskInfo\DiskInfo64.exe"
$diskInfoFilePath = "$($Env:ProgramFiles)\CrystalDiskInfo\DiskInfo.txt"

if ($enableVersionCheck) {
    Write-Host "Version check enabled. Verifying CrystalDiskInfo version."
    if (!(Test-Path -Path $diskInfoExePath) -or !(Test-Path -Path $diskInfoFilePath) -or !(Check-CrystalDiskInfoVersion -filePath $diskInfoFilePath -desiredVersion $desiredVersion)) {
        Write-Host "CrystalDiskInfo version is incorrect or missing. Reinstalling."
        if (Test-Path -Path "C:\Program Files\CrystalDiskInfo") {
            Remove-Item -Path "C:\Program Files\CrystalDiskInfo" -Recurse -Force
            Write-Host "Removed existing CrystalDiskInfo installation."
        }
        Install-CrystalDiskInfo -installerUrl $CrystalUrl
    }
}

Write-Host "Checking if CrystalDiskInfo executable exists."
if (Test-Path -Path $diskInfoExePath) {
    Write-Host "Running CrystalDiskInfo to generate SMART report."
    try {
        Start-Process $diskInfoExePath -ArgumentList "/CopyExit" -Wait
    } catch {
        Write-Error "Failed to run CrystalDiskInfo. Error: $_"
        Stop-Transcript
        exit 1
    }

    Write-Host "Reading CrystalDiskInfo output file."
    try {
        $diskInfoContent = Get-Content $diskInfoFilePath
    } catch {
        Write-Error "Failed to read CrystalDiskInfo output file. Error: $_"
        Stop-Transcript
        exit 1
    }

    $cautionCount = 0
    $badCount = 0
    $predictiveFailureDetected = $false

    foreach ($line in $diskInfoContent) {
        if ($line -match "Health Status :.*Caution") {
            $cautionCount++
            $predictiveFailureDetected = $true
        }
        if ($line -match "Health Status :.*Bad") {
            $badCount++
            $predictiveFailureDetected = $true
        }
    }

    $hostname = $env:COMPUTERNAME

    if ($badCount -gt 0) {
        $smartstatus = 'Bad'
    } elseif ($cautionCount -gt 0) {
        $smartstatus = 'Caution'
    } else {
        $smartstatus = 'Good'
    }

    if ($setNinjaSmartStatus) {
        Write-Host "Setting NinjaRMM smart status to $smartstatus."
        Set-NinjaSmartStatus -status $smartstatus
    }

    if ($predictiveFailureDetected -and $predictiveFailureEvent) {
        Write-Host "Predictive failure detected. Logging event."
        $eventTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        $predictiveFailureMessage = "EventId: 2094, EventTime: $eventTime, Source: Server Administrator, Message: Predictive Failure reported by CrystalDiskInfo-PS-Wrapper."
        Log-PredictiveFailureEvent -message $predictiveFailureMessage
    }

    if ($cautionCount -gt 0 -or $badCount -gt 0) {
        Write-Host "SMART test reported issues. Sending alert."
        $formattedSMARTInfo = Format-SMARTInfo -hostname $hostname -cautionCount $cautionCount -badCount $badCount
        Send-WebhookMessage -webhookUrl $webhookUrl -message $formattedSMARTInfo
    } elseif ($sendAlertOnPass) {
        Write-Host "SMART test passed. Sending pass alert."
        $formattedPassInfo = Format-PassInfo -hostname $hostname
        Send-WebhookMessage -webhookUrl $webhookUrl -message $formattedPassInfo
    } else {
        Write-Output "$hostname : CrystalDiskInfo SMART test is reporting a pass."
    }
} else {
    Write-Output "Error: CrystalDiskInfo executable not found. Please check the installation."
}

Write-Host "Stopping transcript logging."
Stop-Transcript

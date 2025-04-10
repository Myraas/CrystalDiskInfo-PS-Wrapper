Clear-Host

$sendAlertOnPass = $false
$setNinjaSmartStatus = $true
$enableVersionCheck = $true
$predictiveFailureEvent = $false

$desiredVersion = "CrystalDiskInfo 9.2.3"
$webhookUrl = "Your webhook URL here"
$CrystalUrl = "Your CrystalDiskInfo .exe installer URL here"

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

function Stop-CrystalDiskInfo {
    Write-Host "Checking for running CrystalDiskInfo processes..."
    $processes = @("DiskInfo", "DiskInfo32", "DiskInfo64", "CrystalDiskInfo")
    
    foreach ($processName in $processes) {
        $runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($runningProcesses) {
            Write-Host "Found running process: $processName. Attempting to close..."
            try {
                $runningProcesses | ForEach-Object {
                    $_ | Stop-Process -Force
                    Write-Host "Successfully stopped process $($_.Name) (PID: $($_.Id))"
                }
                Start-Sleep -Seconds 2
            } catch {
                Write-Error "Failed to stop process $processName. Error: $_"
            }
        }
    }
    
    $stillRunning = $false
    foreach ($processName in $processes) {
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            $stillRunning = $true
            Write-Error "Process $processName is still running. Unable to terminate."
        }
    }
    
    return !$stillRunning
}

function Install-CrystalDiskInfo {
    param (
        $installerUrl
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $installerPath = "C:\temp\CrystalDiskInfoInstaller_$Timestamp.exe"

    $maxRetries = 3
    $retryCount = 0
    $success = $false

    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
            if (Test-Path -Path $installerPath) {
                Remove-Item -Path $installerPath -Force
                Write-Host "Removed existing installer."
            }

            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            Write-Host "CrystalDiskInfo installer downloaded successfully."
            Start-Sleep -Seconds 5
            $success = $true
        } catch {
            Write-Error "Failed to download CrystalDiskInfo installer. Error: $_"
            if ($_.Exception.Message -match "being used by another process") {
                Write-Host "Installer file is being used by another process. Retrying..."
                Start-Sleep -Seconds 5
                $retryCount++
            } else {
                Stop-Transcript
                exit 1
            }
        }
    }

    if (-not $success) {
        Write-Error "Failed to download installer after multiple retries."
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
            Write-Host "CrystalDiskInfo version is correct: $desiredVersion"
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
    Write-Host "Version check enabled. Verifying $desiredVersion"
    if (!(Test-Path -Path $diskInfoExePath) -or !(Test-Path -Path $diskInfoFilePath) -or !(Check-CrystalDiskInfoVersion -filePath $diskInfoFilePath -desiredVersion $desiredVersion)) {
        Write-Host "CrystalDiskInfo version is incorrect or missing. Reinstalling."
        
        $processesStopped = Stop-CrystalDiskInfo
        if (!$processesStopped) {
            Write-Warning "Could not stop all CrystalDiskInfo processes. Attempting to continue anyway."
        }
        
        if (Test-Path -Path "C:\Program Files\CrystalDiskInfo") {
            Remove-Item -Path "C:\Program Files\CrystalDiskInfo" -Recurse -Force
            Write-Host "Removed existing CrystalDiskInfo installation."
        }
        Install-CrystalDiskInfo -installerUrl $CrystalUrl
    }
}

Write-Host "Checking if CrystalDiskInfo executable exists."
if (Test-Path -Path $diskInfoExePath) {
    Stop-CrystalDiskInfo | Out-Null
    
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
        $smartstatus = 'bad'
    } elseif ($cautionCount -gt 0) {
        $smartstatus = 'caution'
    } else {
        $smartstatus = 'good'
    }

    if ($setNinjaSmartStatus) {
        Write-Host "Setting NinjaRMM smart status to $smartstatus."
        Set-NinjaSmartStatus -status $smartstatus
    }

    if ($predictiveFailureDetected -and $predictiveFailureEvent) {
        Write-Host "Predictive failure detected. Logging event."
        $eventTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        $predictiveFailureMessage = "EventId: 2094, EventTime: $eventTime, Source: Server Administrator, Message: Predictive Failure reported by CrystalDiskInfo."
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

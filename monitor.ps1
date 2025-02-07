# Set working directory and basic config
$workingDir = "D:\software\aios-cli"
$currentDir = $PSScriptRoot
$logsDir = Join-Path $currentDir "logs"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $logsDir "output_${timestamp}.txt"

# Critical error patterns that should trigger restart
$criticalErrors = @(
    "Another instance is already running",
    "Failed to authenticate",
    "Failed to connect", 
    "Internal server error",
    "Service Unavailable",
    "Failed to register models for inference",
    "panicked at aios-cli"
)

# Check working directory
if (-not (Test-Path $workingDir)) {
    Write-Error "Error: Working directory $workingDir does not exist"
    exit 1
}

# Create logs directory if not exists
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir | Out-Null
}

Set-Location $workingDir

# Add logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"  # INFO, ERROR, WARN
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] $Message"
    Write-Host $logMessage
    try {
        $logMessage | Out-File -FilePath $outputFile -Append -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

# Main loop
while ($true) {
    try {
        # Kill existing instance if running
        Write-Log "Checking daemon status..."
        $status = & .\aios-cli status
        Write-Log "Status check result: $status"
        
        if ($status -match "Daemon running") {
            Write-Log "Found running instance, killing..." "WARN"
            $killResult = & .\aios-cli kill
            Write-Log "Kill command result: $killResult"
            Start-Sleep -Seconds 15
        }

        # Start process and monitor
        Write-Log "Starting aios-cli daemon..."
        $job = Start-Job -ScriptBlock {
            Set-Location $using:workingDir
            # 直接返回输出而不是写入文件
            .\aios-cli start --connect 2>&1
        }
        
        # Monitor job output
        while ($job.State -eq 'Running') {
            Receive-Job -Job $job | ForEach-Object {
                $line = $_
                # 写入日志
                Write-Log $line
                
                # Check for critical errors
                foreach($error in $criticalErrors) {
                    if($line -match [regex]::Escape($error)) {
                        Write-Log "Critical error detected: $error" "ERROR"
                        
                        # Stop the job first
                        if ($job.State -eq 'Running') {
                            Stop-Job -Job $job
                            Remove-Job -Job $job
                            Write-Log "Stopped monitoring job" "INFO"
                        }

                        # Kill the process and verify it's stopped
                        Write-Log "Executing kill command..." "WARN"
                        $killResult = & .\aios-cli kill 2>&1
                        Write-Log "Kill command result: $killResult"
                        
                        # Wait to ensure process is fully terminated
                        Start-Sleep -Seconds 15
                        
                        # Handle panic error with extra care
                        if ($error -eq "panicked at aios-cli") {
                            Write-Log "Panic detected, waiting additional time before restart..." "WARN"
                            Start-Sleep -Seconds 15
                        }
                        
                        return
                    }
                }
            }
            Start-Sleep -Seconds 15
        }

        # Cleanup only if job still exists and is running
        if ($job -and $job.State -eq 'Running') {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Error occurred: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Start-Sleep -Seconds 15
    }
}

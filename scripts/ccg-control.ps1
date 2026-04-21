param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$Profile = "cloudcostguard",

    [Parameter(Mandatory = $false)]
    [string]$Regions = "us-east-1,ap-south-1",

    [Parameter(Mandatory = $false)]
    [string]$LambdaFunctionName = "cloud-cost-guard-scanner",

    [Parameter(Mandatory = $false)]
    [string]$SchedulerName = "cloud-cost-guard-hourly",

    [Parameter(Mandatory = $false)]
    [switch]$HardStop
)

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-AwsCli {
    $fromPath = Get-Command aws -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $candidates = @(
        "C:\Program Files\Amazon\AWSCLIV2\aws.exe",
        "C:\Program Files\Amazon\AWSCLI\bin\aws.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "AWS CLI not found. Install with: winget install -e --id Amazon.AWSCLI"
}

$script:AwsCliPath = Resolve-AwsCli

function Invoke-Aws {
    param(
        [string]$Region,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    $allArgs = @("--profile", $Profile, "--region", $Region) + $Args
    $output = & $script:AwsCliPath @allArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "AWS CLI failed in ${Region}: aws $($allArgs -join ' ')`n$message"
    }

    return $output
}

function Try-GetSchedule {
    param([string]$Region)
    try {
        $raw = Invoke-Aws -Region $Region -Args "scheduler", "get-schedule", "--name", $SchedulerName, "--output", "json"
        return ($raw | Out-String | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Try-GetLambdaConfig {
    param([string]$Region)
    try {
        $raw = Invoke-Aws -Region $Region -Args "lambda", "get-function-configuration", "--function-name", $LambdaFunctionName, "--output", "json"
        return ($raw | Out-String | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Try-GetLambdaConcurrency {
    param([string]$Region)
    try {
        $raw = Invoke-Aws -Region $Region -Args "lambda", "get-function-concurrency", "--function-name", $LambdaFunctionName, "--output", "json"
        return ($raw | Out-String | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-Mode {
    param(
        [string]$ScheduleState,
        [string]$PerformActions,
        [Nullable[int]]$ReservedConcurrency
    )

    $enabled = $ScheduleState -eq "ENABLED"
    $actionsOn = $PerformActions -eq "true"
    $hardStopped = ($ReservedConcurrency -ne $null -and $ReservedConcurrency -eq 0)

    if ($hardStopped -or ((-not $enabled) -and (-not $actionsOn))) {
        return "STOPPED"
    }
    if ($enabled -and $actionsOn -and (-not $hardStopped)) {
        return "ACTIVE"
    }
    return "MIXED"
}

function Set-ScheduleState {
    param(
        [string]$Region,
        [string]$State,
        [object]$Schedule
    )

    $targetPath = Join-Path $env:TEMP "ccg-control-target-$Region.json"
    ($Schedule.Target | ConvertTo-Json -Compress) | Set-Content -Path $targetPath -Encoding ascii

    $updateArgs = @(
        "scheduler", "update-schedule",
        "--name", $SchedulerName,
        "--state", $State,
        "--schedule-expression", $Schedule.ScheduleExpression,
        "--flexible-time-window", "Mode=$($Schedule.FlexibleTimeWindow.Mode)",
        "--target", "file://$targetPath"
    )

    if ($Schedule.ScheduleExpressionTimezone) {
        $updateArgs += @("--schedule-expression-timezone", $Schedule.ScheduleExpressionTimezone)
    }

    Invoke-Aws -Region $Region -Args $updateArgs | Out-Null
}

function Set-LambdaMode {
    param(
        [string]$Region,
        [object]$Lambda,
        [bool]$PerformActions
    )

    $vars = @{}
    if ($Lambda.Environment -and $Lambda.Environment.Variables) {
        $Lambda.Environment.Variables.PSObject.Properties | ForEach-Object {
            $vars[$_.Name] = [string]$_.Value
        }
    }
    $vars["PERFORM_ACTIONS"] = $PerformActions.ToString().ToLower()

    $envDoc = @{ Variables = $vars }
    $envPath = Join-Path $env:TEMP "ccg-control-env-$Region.json"
    ($envDoc | ConvertTo-Json -Depth 5) | Set-Content -Path $envPath -Encoding ascii

    Invoke-Aws -Region $Region -Args "lambda", "update-function-configuration", "--function-name", $LambdaFunctionName, "--environment", "file://$envPath" | Out-Null
    Invoke-Aws -Region $Region -Args "lambda", "wait", "function-updated-v2", "--function-name", $LambdaFunctionName | Out-Null
}

$targetState = if ($Action -eq "stop") { "DISABLED" } else { "ENABLED" }
$performActions = $Action -eq "start"
$regionList = $Regions.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }

foreach ($region in $regionList) {
    Write-Host "Processing region: $region"

    $schedule = Try-GetSchedule -Region $region
    if ($Action -ne "status") {
        if ($null -eq $schedule) {
            Write-Host "- Scheduler '$SchedulerName' not found in $region (skipping)."
        }
        else {
            Set-ScheduleState -Region $region -State $targetState -Schedule $schedule
            Write-Host "- Scheduler state set to $targetState"
        }
    }

    $lambda = Try-GetLambdaConfig -Region $region
    if ($null -eq $lambda) {
        Write-Host "- Lambda '$LambdaFunctionName' not found in $region (skipping)."
        continue
    }

    if ($Action -eq "status") {
        $scheduleState = if ($schedule -eq $null) { "MISSING" } else { [string]$schedule.State }
        $perform = "false"
        if ($lambda.Environment -and $lambda.Environment.Variables -and $lambda.Environment.Variables.PERFORM_ACTIONS) {
            $perform = [string]$lambda.Environment.Variables.PERFORM_ACTIONS
        }

        $concurrency = Try-GetLambdaConcurrency -Region $region
        $reserved = $null
        if ($concurrency -and $concurrency.ReservedConcurrentExecutions -ne $null) {
            $reserved = [int]$concurrency.ReservedConcurrentExecutions
        }

        $mode = Get-Mode -ScheduleState $scheduleState -PerformActions $perform.ToLower() -ReservedConcurrency $reserved
        $reservedText = if ($reserved -eq $null) { "UNSET" } else { [string]$reserved }

        Write-Host "- MODE=$mode"
        Write-Host "- SchedulerState=$scheduleState"
        Write-Host "- PERFORM_ACTIONS=$perform"
        Write-Host "- ReservedConcurrency=$reservedText"
        continue
    }

    Set-LambdaMode -Region $region -Lambda $lambda -PerformActions $performActions
    Write-Host "- Lambda PERFORM_ACTIONS set to $($performActions.ToString().ToLower())"

    if ($HardStop) {
        if ($Action -eq "stop") {
            Invoke-Aws -Region $region -Args "lambda", "put-function-concurrency", "--function-name", $LambdaFunctionName, "--reserved-concurrent-executions", "0" | Out-Null
            Write-Host "- Lambda hard-stop concurrency applied (0)."
        }
        else {
            try {
                Invoke-Aws -Region $region -Args "lambda", "delete-function-concurrency", "--function-name", $LambdaFunctionName | Out-Null
                Write-Host "- Lambda hard-stop concurrency removed."
            }
            catch {
                Write-Host "- No hard-stop concurrency found (continuing)."
            }
        }
    }
}

Write-Host "Done. Action '$Action' completed."

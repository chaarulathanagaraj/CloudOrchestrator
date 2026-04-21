param(
    [Parameter(Mandatory = $false)]
    [string]$Profile = "default",

    [Parameter(Mandatory = $false)]
    [string]$Region = "ap-south-1",

    [Parameter(Mandatory = $true)]
    [string]$AlertEmail,

    [Parameter(Mandatory = $false)]
    [string]$BudgetAmountUsd = "5",

    [Parameter(Mandatory = $false)]
    [string]$LambdaFunctionName = "cloud-cost-guard-scanner",

    [Parameter(Mandatory = $false)]
    [string]$SchedulerName = "cloud-cost-guard-hourly",

    [Parameter(Mandatory = $false)]
    [string]$ScheduleExpression = "rate(3 hours)",

    [Parameter(Mandatory = $false)]
    [switch]$EnableActions
)

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
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

    throw "AWS CLI not found. Install it with: winget install -e --id Amazon.AWSCLI"
}

function Invoke-Aws {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    $allArgs = @("--profile", $Profile, "--region", $Region) + $Args
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $script:AwsCliPath @allArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "AWS CLI command failed: aws $($allArgs -join ' ')`n$message"
    }
    return $output
}

function Invoke-AwsNoRegion {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    $allArgs = @("--profile", $Profile) + $Args
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $script:AwsCliPath @allArgs 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "AWS CLI command failed: aws $($allArgs -join ' ')`n$message"
    }
    return $output
}

function Ensure-IamRole {
    param(
        [string]$RoleName,
        [string]$TrustPolicyFile
    )

    try {
        Invoke-AwsNoRegion -Args @("iam", "get-role", "--role-name", $RoleName) | Out-Null
        Write-Host "IAM role exists: $RoleName"
    }
    catch {
        Write-Host "Creating IAM role: $RoleName"
        Invoke-AwsNoRegion -Args @("iam", "create-role", "--role-name", $RoleName, "--assume-role-policy-document", "file://$TrustPolicyFile") | Out-Null
    }
}

function Ensure-SnsEmailSubscription {
    param(
        [string]$TopicArn,
        [string]$Email
    )

    $query = "Subscriptions[?Protocol=='email' && Endpoint=='$Email'].SubscriptionArn"
    $subscriptionArn = Invoke-Aws -Args @("sns", "list-subscriptions-by-topic", "--topic-arn", $TopicArn, "--query", $query, "--output", "text")
    $normalized = ($subscriptionArn | Out-String).Trim()

    if ($normalized -and $normalized -ne "None") {
        Write-Host "SNS email subscription already exists: $Email"
        return
    }

    Write-Host "Creating SNS email subscription: $Email"
    Invoke-Aws -Args @("sns", "subscribe", "--topic-arn", $TopicArn, "--protocol", "email", "--notification-endpoint", $Email) | Out-Null
}

function Ensure-Lambda {
    param(
        [string]$FunctionName,
        [string]$RoleArn,
        [string]$JarPath,
        [string]$SnsTopicArn,
        [bool]$PerformActions
    )

    $envObject = @{
        Variables = @{
            SNS_TOPIC_ARN = $SnsTopicArn
            AUDIT_TABLE_NAME = "resource_audit_log"
            PERFORM_ACTIONS = $PerformActions.ToString().ToLower()
            AUTO_STOP_ENVS = "dev,test,sandbox"
            AUTO_TERMINATE_ENVS = "sandbox"
            REQUIRED_TAGS = "Owner,Environment,TTL"
            IDLE_CPU_MAX = "5.0"
            IDLE_NETWORK_BYTES_MAX = "1048576"
            IDLE_LOOKBACK_HOURS = "6"
            SET_ASG_MIN_TO_ZERO = "true"
        }
    }
    $envPath = Join-Path $env:TEMP "ccg-lambda-env.json"
    ($envObject | ConvertTo-Json -Depth 4) | Set-Content -Path $envPath -Encoding ascii

    $exists = $true
    try {
        Invoke-Aws -Args @("lambda", "get-function", "--function-name", $FunctionName) | Out-Null
    }
    catch {
        $exists = $false
    }

    if ($exists) {
        Write-Host "Updating Lambda code: $FunctionName"
        Invoke-Aws -Args @("lambda", "update-function-code", "--function-name", $FunctionName, "--zip-file", "fileb://$JarPath") | Out-Null
        Invoke-Aws -Args @("lambda", "wait", "function-updated-v2", "--function-name", $FunctionName) | Out-Null

        Write-Host "Updating Lambda configuration: $FunctionName"
        Invoke-Aws -Args @("lambda", "update-function-configuration", "--function-name", $FunctionName, "--handler", "com.cloudcostguardian.Handler::handleRequest", "--runtime", "java17", "--role", $RoleArn, "--timeout", "300", "--memory-size", "512", "--environment", "file://$envPath") | Out-Null
        Invoke-Aws -Args @("lambda", "wait", "function-updated-v2", "--function-name", $FunctionName) | Out-Null
    }
    else {
        Write-Host "Creating Lambda function: $FunctionName"
        Invoke-Aws -Args @("lambda", "create-function", "--function-name", $FunctionName, "--runtime", "java17", "--role", $RoleArn, "--handler", "com.cloudcostguardian.Handler::handleRequest", "--zip-file", "fileb://$JarPath", "--timeout", "300", "--memory-size", "512", "--environment", "file://$envPath") | Out-Null
        Invoke-Aws -Args @("lambda", "wait", "function-active-v2", "--function-name", $FunctionName) | Out-Null
    }
}

function Ensure-Schedule {
    param(
        [string]$Name,
        [string]$Expression,
        [string]$TargetArn,
        [string]$RoleArn
    )

    $targetObject = [ordered]@{
        Arn = $TargetArn
        RoleArn = $RoleArn
        Input = '{"trigger":"eventbridge-scheduler"}'
    }
    $targetPath = Join-Path $env:TEMP "ccg-scheduler-target.json"
    ($targetObject | ConvertTo-Json -Compress) | Set-Content -Path $targetPath -Encoding ascii

    $exists = $true
    try {
        Invoke-Aws -Args @("scheduler", "get-schedule", "--name", $Name) | Out-Null
    }
    catch {
        $exists = $false
    }

    if ($exists) {
        Write-Host "Updating scheduler: $Name"
        Invoke-Aws -Args @("scheduler", "update-schedule", "--name", $Name, "--schedule-expression", $Expression, "--flexible-time-window", "Mode=OFF", "--target", "file://$targetPath", "--state", "ENABLED") | Out-Null
    }
    else {
        Write-Host "Creating scheduler: $Name"
        Invoke-Aws -Args @("scheduler", "create-schedule", "--name", $Name, "--schedule-expression", $Expression, "--flexible-time-window", "Mode=OFF", "--target", "file://$targetPath", "--state", "ENABLED") | Out-Null
    }
}

$script:AwsCliPath = Resolve-AwsCli
Require-Command mvn

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $root

Write-Host "Validating AWS identity..."
$accountIdRaw = $null
try {
    $accountIdRaw = Invoke-AwsNoRegion -Args @("sts", "get-caller-identity", "--query", "Account", "--output", "text")
}
catch {
    throw "Unable to access AWS using profile '$Profile'. Configure it first with: aws configure --profile $Profile"
}

if (-not $accountIdRaw) {
    throw "Unable to resolve account id for profile '$Profile'. Run: aws configure --profile $Profile"
}

$accountId = $accountIdRaw.Trim()
Write-Host "Using account: $accountId"

Write-Host "Building Java Lambda artifact..."
& mvn -f "lambda/pom.xml" -DskipTests clean package

$jarPath = Join-Path $root "lambda\target\cloudcost-guardian-lambda.jar"
if (-not (Test-Path $jarPath)) {
    throw "Build completed but JAR not found at: $jarPath"
}

Write-Host "Deploying DynamoDB stack..."
Invoke-Aws -Args @("cloudformation", "deploy", "--stack-name", "ccg-dynamodb", "--template-file", (Join-Path $root "infra\dynamodb-table.json")) | Out-Null

Write-Host "Ensuring SNS topic and email subscription..."
$topicArn = (Invoke-Aws -Args @("sns", "create-topic", "--name", "alerts", "--query", "TopicArn", "--output", "text")).Trim()
Ensure-SnsEmailSubscription -TopicArn $topicArn -Email $AlertEmail

$lambdaTrustPath = Join-Path $env:TEMP "ccg-lambda-trust.json"
@"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@ | Set-Content -Path $lambdaTrustPath -Encoding ascii

$lambdaRoleName = "CloudCostGuardianLambdaRole"
Ensure-IamRole -RoleName $lambdaRoleName -TrustPolicyFile $lambdaTrustPath

Write-Host "Applying Lambda execution permissions..."
Invoke-AwsNoRegion -Args @("iam", "put-role-policy", "--role-name", $lambdaRoleName, "--policy-name", "CloudCostGuardianInlinePolicy", "--policy-document", "file://$(Join-Path $root "infra\iam-policy.json")") | Out-Null

$lambdaRoleArn = "arn:aws:iam::${accountId}:role/$lambdaRoleName"
Ensure-Lambda -FunctionName $LambdaFunctionName -RoleArn $lambdaRoleArn -JarPath $jarPath -SnsTopicArn $topicArn -PerformActions $EnableActions.IsPresent

$schedulerTrustPath = Join-Path $env:TEMP "ccg-scheduler-trust.json"
@"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "scheduler.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@ | Set-Content -Path $schedulerTrustPath -Encoding ascii

$schedulerRoleName = "EventBridgeInvokeLambdaRole"
Ensure-IamRole -RoleName $schedulerRoleName -TrustPolicyFile $schedulerTrustPath

$invokePolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
    "Resource": "arn:aws:lambda:${Region}:${accountId}:function:$LambdaFunctionName"
    }
  ]
}
"@
$invokePolicyPath = Join-Path $env:TEMP "ccg-scheduler-invoke-policy.json"
$invokePolicy | Set-Content -Path $invokePolicyPath -Encoding ascii
Invoke-AwsNoRegion -Args @("iam", "put-role-policy", "--role-name", $schedulerRoleName, "--policy-name", "CloudCostGuardianSchedulerInvoke", "--policy-document", "file://$invokePolicyPath") | Out-Null

$lambdaArn = "arn:aws:lambda:${Region}:${accountId}:function:$LambdaFunctionName"
$schedulerRoleArn = "arn:aws:iam::${accountId}:role/$schedulerRoleName"
Ensure-Schedule -Name $SchedulerName -Expression $ScheduleExpression -TargetArn $lambdaArn -RoleArn $schedulerRoleArn

Write-Host "Ensuring budget exists..."
try {
    $budgetName = "cloud-cost-guard-dev-cap"
    $budgetJson = @"
{
  "BudgetName": "$budgetName",
  "BudgetLimit": { "Amount": "$BudgetAmountUsd", "Unit": "USD" },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
"@
    $budgetPath = Join-Path $env:TEMP "ccg-budget.json"
    $budgetJson | Set-Content -Path $budgetPath -Encoding ascii

    $notificationJson = @"
{
  "NotificationType": "ACTUAL",
  "ComparisonOperator": "GREATER_THAN",
  "Threshold": 80,
  "ThresholdType": "PERCENTAGE"
}
"@
    $notificationPath = Join-Path $env:TEMP "ccg-budget-notification.json"
    $notificationJson | Set-Content -Path $notificationPath -Encoding ascii

    $subscriberJson = @"
[
  { "SubscriptionType": "EMAIL", "Address": "$AlertEmail" }
]
"@
    $subscriberPath = Join-Path $env:TEMP "ccg-budget-subscribers.json"
    $subscriberJson | Set-Content -Path $subscriberPath -Encoding ascii

    $budgetExists = $true
    try {
        Invoke-Aws -Args @("budgets", "describe-budget", "--account-id", $accountId, "--budget-name", $budgetName) | Out-Null
    }
    catch {
        $budgetExists = $false
    }

    if (-not $budgetExists) {
        Invoke-Aws -Args @("budgets", "create-budget", "--account-id", $accountId, "--budget", "file://$budgetPath") | Out-Null
    }

    try {
        Invoke-Aws -Args @("budgets", "create-notification", "--account-id", $accountId, "--budget-name", $budgetName, "--notification", "file://$notificationPath", "--subscribers", "file://$subscriberPath") | Out-Null
    }
    catch {
        Write-Host "Budget notification may already exist. Continuing."
    }
}
catch {
    Write-Host "Budget setup skipped: $($_.Exception.Message)"
}

Write-Host "Running initial dry invocation..."
$outputPath = Join-Path $env:TEMP "ccg-lambda-output.json"
Invoke-Aws -Args @("lambda", "invoke", "--function-name", $LambdaFunctionName, $outputPath) | Out-Null
Write-Host "Lambda output: $outputPath"

Write-Host "Done."
Write-Host "SNS topic: $topicArn"
Write-Host "Lambda: $LambdaFunctionName"
Write-Host "Scheduler: $SchedulerName ($ScheduleExpression)"
Write-Host "PERFORM_ACTIONS: $($EnableActions.IsPresent.ToString().ToLower())"
Write-Host "IMPORTANT: Confirm SNS email subscription in your inbox to receive alerts."

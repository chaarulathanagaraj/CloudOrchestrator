# Cloud Orchestrator

Automated AWS cost-governance for non-production workloads.

Cloud Orchestrator continuously scans EC2 instances and Auto Scaling Groups, evaluates policy compliance (TTL, tags, environment, utilization), alerts through SNS, and writes a full audit trail to DynamoDB. Remediation can run in safe dry-run mode or active mode.

## Why This Project

- Reduce avoidable cloud spend from forgotten or idle non-prod resources.
- Keep remediation explainable with reason codes and immutable audit records.
- Enforce safety first with environment and protection-tag guardrails.
- Operate serverlessly with low management overhead.

## Key Capabilities

- Resource discovery:
  - EC2 instances in `running` state.
  - All Auto Scaling Groups.
- Policy checks:
  - Required tags (`Owner`, `Environment`, `TTL` by default).
  - Environment-aware remediation rules (`dev`, `test`, `sandbox`, `prod`).
  - Protection tags (`KeepAlive`, `DoNotDelete`).
  - TTL expiration.
  - EC2 idle detection from CloudWatch CPU + network metrics.
- Actions (configurable):
  - EC2: stop or terminate.
  - ASG: scale desired capacity to zero (optionally min size as well).
- Notifications:
  - WARN alerts for violations.
  - ACTION alerts when remediation executes.
- Auditing:
  - Every scan/action written to DynamoDB with resource, reason, outcome, timestamp.




```mermaid
flowchart LR
		A[AWS Resources\nEC2 + ASG] --> B[EventBridge Scheduler\nrate(3 hours)]
		B --> C[Lambda Scanner\ncom.cloudcostguardian.Handler]

		C --> C1[Discover Resources]
		C1 --> C2[Fetch Metrics\nCloudWatch]
		C2 --> C3[Evaluate Policy\nTags + Environment + TTL + Idle]
		C3 --> C4{Decision}

		C4 -->|Compliant| O1[No Action\nAudit SCANNED]
		C4 -->|Non-compliant| N1[SNS WARN]
		C4 -->|Action allowed + PERFORM_ACTIONS=true| R1[Remediate\nStop/Terminate/Scale-to-zero]
		C4 -->|Action allowed + PERFORM_ACTIONS=false| D1[Dry Run\nAudit SKIPPED_DRY_RUN]

		R1 --> N2[SNS ACTION]

		C --> L1[DynamoDB Audit Log\nresource_audit_log]
		O1 --> L1
		N1 --> L1
		R1 --> L1
		D1 --> L1

		X[AWS Budgets Safety Layer] --> N1
```

## Repository Layout

```text
.
|-- docs/
|   |-- architecture.md
|   |-- build-checklist.md
|   |-- demo-script.md
|   |-- policy.md
|   \-- policy-matrix.md
|-- infra/
|   |-- budget-config.json
|   |-- dynamodb-table.json
|   |-- iam-policy.json
|   |-- scheduler-config.json
|   \-- sns-topic.json
|-- lambda/
|   |-- pom.xml
|   \-- src/main/java/com/cloudcostguardian/
|       |-- Handler.java
|       |-- PolicyEngine.java
|       |-- CloudWatchUtilization.java
|       |-- Notifier.java
|       |-- AuditLogger.java
|       |-- AwsClients.java
|       |-- Settings.java
|       \-- EvaluationResult.java
\-- scripts/
		|-- deploy-aws.ps1
		\-- ccg-control.ps1
```

## Tech Stack

- Java 17 Lambda runtime
- AWS SDK for Java v2
- AWS Lambda + EventBridge Scheduler
- EC2 + Auto Scaling + CloudWatch
- SNS for alerting
- DynamoDB for audit logs
- AWS Budgets as account-level safety layer
- PowerShell automation scripts for deployment and operations

## Policy Model

### Environment behavior

- `prod`: never auto-remediate.
- `dev`, `test`, `sandbox`: eligible for stop/scale actions.
- `sandbox` (default): eligible for terminate actions.

### Required tags (default)

- `Owner`
- `Environment`
- `TTL` (ISO 8601 UTC timestamp)

### Protection tags

- `KeepAlive=true`: skip remediation.
- `DoNotDelete=true`: skip remediation.

### Default thresholds

- Idle CPU max: `5.0`
- Idle network max (avg in+out): `1048576` bytes
- Idle lookback window: `6` hours

### Decision hierarchy

1. Missing required tags -> alert only.
2. `Environment=prod` -> skip remediation.
3. Protected tags set -> skip remediation.
4. TTL expired -> notify + remediate by policy.
5. Else if idle EC2 -> notify + stop (eligible envs).

## Quick Start (Recommended)

Use the one-command deployment script.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-aws.ps1 `
	-Profile cloudcostguard `
	-Region ap-south-1 `
	-AlertEmail you@example.com
```

Optional: enable live remediation at deploy time.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-aws.ps1 `
	-Profile cloudcostguard `
	-Region ap-south-1 `
	-AlertEmail you@example.com `
	-EnableActions
```

What this script does:

- Builds Lambda JAR (`mvn clean package`).
- Deploys DynamoDB table.
- Creates/uses SNS topic and subscribes email.
- Creates/updates IAM roles and policies.
- Creates/updates Lambda function.
- Creates/updates EventBridge schedule.
- Creates/updates budget + notification (best effort).
- Executes an initial Lambda invocation.

## Manual Build and Deploy

### Build Lambda artifact

```powershell
mvn -f .\lambda\pom.xml -DskipTests clean package
```

Artifact output:

- `lambda\target\cloudcost-guardian-lambda.jar`

### Handler entrypoint

- `com.cloudcostguardian.Handler::handleRequest`

## Runtime Configuration

Set these as Lambda environment variables.

| Variable                 | Default                 | Purpose                                          |
| ------------------------ | ----------------------- | ------------------------------------------------ |
| `SNS_TOPIC_ARN`          | empty                   | SNS destination for alerts                       |
| `AUDIT_TABLE_NAME`       | `resource_audit_log`    | DynamoDB audit table                             |
| `PERFORM_ACTIONS`        | `false`                 | Dry-run (`false`) vs active remediation (`true`) |
| `AUTO_STOP_ENVS`         | `dev,test,sandbox`      | Environments eligible for stop/scale actions     |
| `AUTO_TERMINATE_ENVS`    | `sandbox`               | Environments eligible for terminate action       |
| `REQUIRED_TAGS`          | `Owner,Environment,TTL` | Required compliance tags                         |
| `IDLE_CPU_MAX`           | `5.0`                   | EC2 idle CPU threshold                           |
| `IDLE_NETWORK_BYTES_MAX` | `1048576`               | EC2 idle network threshold                       |
| `IDLE_LOOKBACK_HOURS`    | `6`                     | CloudWatch lookback window                       |
| `SET_ASG_MIN_TO_ZERO`    | `true`                  | Also set ASG min size to 0 when scaling down     |

## Operations

Use the control script to toggle behavior safely.

### Status

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action status -Profile cloudcostguard
```

### Stop automation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action stop -Profile cloudcostguard
```

### Start automation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action start -Profile cloudcostguard
```

### Hard stop (optional)

Set Lambda reserved concurrency to `0` on stop.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action stop -Profile cloudcostguard -HardStop
```

## Audit and Alert Evidence

### DynamoDB record pattern

- Partition key: `pk` = resource id
- Sort key: `sk` = ISO timestamp
- Attributes include:
  - `resource_type`, `resource_name`
  - `action`, `reason`, `outcome`
  - `environment`, `owner`, `details`

### SNS message pattern

- Subject:
  - `[CloudCostGuard][WARN] ...`
  - `[CloudCostGuard][ACTION] ...`
- Message includes resource metadata, action, reason, and details.

## Tagging Examples

### EC2 / ASG tags for managed non-prod resources

```text
Owner=team-alpha
Environment=dev
TTL=2026-04-30T14:00:00Z
KeepAlive=false
DoNotDelete=false
Project=cloud-orchestrator
```

## Safety and Production Guardrails

- `prod` is always excluded from automated remediation by policy.
- Missing required tags never triggers destructive action.
- `PERFORM_ACTIONS=false` enables full dry-run behavior with audit evidence.
- Protection tags provide explicit opt-out at resource level.

## Validation Flow

1. Deploy with `PERFORM_ACTIONS=false`.
2. Create test EC2/ASG with required tags and near-future TTL.
3. Trigger Lambda manually or wait for schedule.
4. Verify SNS WARN + DynamoDB `FLAGGED_NON_COMPLIANT` or `SKIPPED_DRY_RUN`.
5. Enable actions and rerun.
6. Verify expected stop/terminate/scale behavior and audit `SUCCESS` outcomes.

## Documentation

- `docs/architecture.md` for architecture rationale.
- `docs/policy.md` and `docs/policy-matrix.md` for policy details.
- `docs/build-checklist.md` for day-by-day implementation checklist.
- `docs/demo-script.md` for demo narrative.

## Notes

- Confirm SNS email subscription from your inbox after deployment.
- Scheduler default cadence is `rate(3 hours)`.
- The scanner only evaluates EC2 instances in `running` state.



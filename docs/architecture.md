# Architecture

## Core Flow

EventBridge Scheduler -> Lambda scanner -> EC2 / ASG / CloudWatch APIs -> policy evaluation -> SNS notification -> DynamoDB audit log

Parallel safety layer:

AWS Budgets -> email/SNS alert

## Why this architecture

- The control plane is serverless and scales to low-usage workloads with minimal cost.
- Governance decisions are deterministic and traceable through DynamoDB records.
- Production safety is enforced by policy and tag-based exclusions.

## Components

- EventBridge Scheduler: invokes Lambda on `rate(3 hours)`.
- Lambda (`com.cloudcostguardian.Handler::handleRequest`): orchestrates scans, policy evaluation, notifications, and actions.
- CloudWatch metrics: pulled on-demand for CPU and network utilization.
- SNS topic `alerts`: sends warning and action status emails.
- DynamoDB table `resource_audit_log`: immutable audit trail for scan and action events.
- SSM Parameter Store: runtime policy/config storage.
- AWS Budgets: account-level warning fallback.

## Safety gates before remediation

- `Environment` must not be `prod`.
- `DoNotDelete=true` skips remediation.
- `KeepAlive=true` skips remediation.
- Missing required tags triggers alert-only mode.
- `PERFORM_ACTIONS=false` allows safe dry-run testing.

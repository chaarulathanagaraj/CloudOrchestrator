# Demo Script

## Goal

Show auditable non-production cost governance using serverless AWS services.

## Demo steps

1. Show architecture and explain two safety layers:
   - resource-level automation
   - account-level budget alerts
2. Create one dev EC2 and one test ASG with tags:
   - `Owner=demo`
   - `Environment=dev` or `test`
   - `TTL=<near-future UTC timestamp>`
3. Run Lambda manually in dry-run (`PERFORM_ACTIONS=false`):
   - show SNS warning
   - show DynamoDB audit rows (`action=SCAN`, and `SKIPPED_DRY_RUN`)
4. Enable real actions (`PERFORM_ACTIONS=true`) and run again:
   - EC2 gets stopped or terminated based on environment
   - ASG desired capacity moves to 0
5. Show DynamoDB evidence:
   - `pk` = resource id
   - `sk` timestamp
   - `reason`, `action`, `outcome`, `details`
6. Show non-compliance guardrail:
   - remove required tag and re-run
   - show alert-only behavior, no destructive action
7. Show AWS Budget threshold notifications configured for monthly cap.

## Interview soundbite

Every scan and remediation is auditable by timestamp, resource, reason, and outcome, so governance behavior is explainable and reviewable.

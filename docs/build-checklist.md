# Day-by-Day Build Checklist

## Day 1: Policy and guardrails

- Finalize environment action policy (`dev/test/sandbox` vs `prod`)
- Finalize required tags and protection tags
- Confirm idle thresholds, TTL defaults, and grace period
- Review [policy.md](policy.md) and [policy-matrix.md](policy-matrix.md)

## Day 2: Infrastructure setup

- Create DynamoDB table from [infra/dynamodb-table.json](../infra/dynamodb-table.json)
- Create SNS topic from [infra/sns-topic.json](../infra/sns-topic.json)
- Create Lambda IAM role using [infra/iam-policy.json](../infra/iam-policy.json)
- Create initial budget using [infra/budget-config.json](../infra/budget-config.json)

## Day 3: Lambda deployment

- Build JAR with `mvn -f lambda/pom.xml clean package`
- Deploy Lambda handler `com.cloudcostguardian.Handler::handleRequest`
- Configure environment variables (`SNS_TOPIC_ARN`, `AUDIT_TABLE_NAME`, `PERFORM_ACTIONS`)
- Optional: add SSM parameter-based config
- Or run one-command automation: `./scripts/deploy-aws.ps1 -Profile <profile> -Region <region> -AlertEmail <email>`

## Day 4: Scheduler and integration

- Create EventBridge schedule using [infra/scheduler-config.json](../infra/scheduler-config.json)
- Validate scheduler invokes Lambda on expected cadence
- Confirm SNS email subscription is active

## Day 5: Validation and evidence

- Test with one tagged EC2 and one tagged ASG
- Run dry-run first (`PERFORM_ACTIONS=false`), then real action mode
- Verify DynamoDB audit records include scan and action outcomes
- Capture screenshots for architecture, alerts, metrics, and audit table
- Rehearse demo narrative using [demo-script.md](demo-script.md)

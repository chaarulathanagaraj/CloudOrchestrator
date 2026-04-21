# Policy Matrix

## Tag matrix

| Tag | Required | Example | Used for |
|---|---|---|---|
| Owner | Yes | team-alpha | Alert routing and accountability |
| Environment | Yes | dev/test/sandbox/prod | Remediation eligibility |
| TTL | Yes | 2026-04-18T09:30:00Z | Expiry-based action |
| KeepAlive | No | true/false | Opt-out from automation |
| DoNotDelete | No | true/false | Protection against destructive actions |
| Project | No | cloudcost-guardian | Grouping and reporting |

## Action matrix

| Condition | Notification | Auto action | Reason code |
|---|---|---|---|
| Missing required tags | Yes | No | MISSING_REQUIRED_TAGS |
| Environment is prod | No | No | PRODUCTION_SKIPPED |
| KeepAlive=true or DoNotDelete=true | No | No | PROTECTED_BY_TAG |
| TTL expired in dev/test | Yes | Stop EC2 / Scale ASG to 0 | TTL_EXPIRED |
| TTL expired in sandbox | Yes | Terminate EC2 / Scale ASG to 0 | TTL_EXPIRED |
| EC2 idle in dev/test/sandbox | Yes | Stop EC2 | IDLE_THRESHOLD_BREACH |
| No policy violation | No | No | NO_ACTION |

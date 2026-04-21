# Policy Definition

## Environment policy

- Auto-stop allowed: `dev`, `test`, `sandbox`
- Auto-terminate allowed: `sandbox` only
- Never auto-remediate: `prod`

## Required tags

- `Owner`
- `Environment`
- `TTL` (ISO 8601 UTC timestamp)
- Recommended: `Project`, `KeepAlive`, `DoNotDelete`

## Defaults

- Default TTL: `72` hours
- Grace period before remediation: `4` hours
- Idle CPU threshold: `<= 5%`
- Idle network threshold: `<= 1048576` bytes average (in + out)
- Idle lookback window: `6` hours

## Protection tags

- `KeepAlive=true`: no auto remediation
- `DoNotDelete=true`: no auto remediation

## Decision hierarchy

1. If required tags are missing -> alert only
2. If `Environment=prod` -> skip remediation
3. If protected by tag -> skip remediation
4. If `TTL` expired -> notify + remediate by environment policy
5. Else if idle threshold breached -> notify + stop (non-prod)

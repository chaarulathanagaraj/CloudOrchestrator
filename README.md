# CloudCost Guardian Control Commands

```powershell
# Check status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action status -Profile cloudcostguard

# Stop monitoring and actions
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action stop -Profile cloudcostguard

# Start monitoring and actions
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ccg-control.ps1 -Action start -Profile cloudcostguard
```
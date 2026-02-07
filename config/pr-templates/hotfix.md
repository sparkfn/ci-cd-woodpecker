## 🚨 Hotfix

This is an urgent fix for a production issue.

### Issue Summary

<!-- Brief description of the production issue -->

### Impact

| Aspect | Details |
|--------|---------|
| **Severity** | 🔴 Critical / 🟠 High |
| **Users Affected** | <!-- Estimated number or percentage --> |
| **Services Affected** | <!-- List affected services --> |
| **Downtime** | <!-- Yes/No, duration if yes --> |

### Root Cause

<!-- What caused this issue -->

### Fix Description

<!-- What was done to fix it -->

### Changes Made

- <!-- List specific changes -->

### Testing

Given the urgency, the following minimal testing was performed:

- [ ] Fix verified in development environment
- [ ] Critical path tested
- [ ] No obvious regressions

### Deployment Plan

- [ ] Ready for immediate deployment
- [ ] Deployment order: <!-- staging → production or direct to production -->
- [ ] Rollback plan documented

### Rollback Instructions

If the hotfix causes issues:

```bash
# Rollback commands here
git revert <commit-sha>
# or
kubectl rollout undo deployment/<name>
```

### Post-Deployment Verification

- [ ] Monitor error rates
- [ ] Check affected functionality
- [ ] Verify no new issues introduced

### Follow-up Tasks

- [ ] Root cause analysis document
- [ ] Preventive measures identified
- [ ] Monitoring/alerting improvements

---

**Related Issue:** {{issue_number}}

**⏰ Created:** {{timestamp}}

*This is a hotfix PR requiring expedited review.*

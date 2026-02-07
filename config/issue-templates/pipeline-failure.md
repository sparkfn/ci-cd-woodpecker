# 🚨 Pipeline Failure: ${CI_COMMIT_BRANCH}

The CI/CD pipeline has failed and requires attention.

## 📋 Pipeline Details

| Field | Value |
|-------|-------|
| **Repository** | ${CI_REPO} |
| **Branch** | ${CI_COMMIT_BRANCH} |
| **Commit** | \`${CI_COMMIT_SHA}\` |
| **Author** | ${CI_COMMIT_AUTHOR} |
| **Pipeline** | #${CI_PIPELINE_NUMBER} |
| **Event** | ${CI_PIPELINE_EVENT} |

## 🔗 Links

- [View Pipeline](${CI_PIPELINE_URL})
- [View Commit](https://github.com/${CI_REPO}/commit/${CI_COMMIT_SHA})

## 📝 Commit Message

```
${CI_COMMIT_MESSAGE}
```

## 🔍 Failure Information

Please check the pipeline logs for detailed error information.

### Common Causes

- [ ] Test failures
- [ ] Build errors
- [ ] Linting issues
- [ ] Dependency problems
- [ ] Configuration errors

## 🛠️ Action Required

1. Review the pipeline logs linked above
2. Identify the root cause of the failure
3. Create a fix and push to the branch
4. Verify the pipeline passes
5. Close this issue when resolved

## 📌 Labels

This issue has been automatically labeled with:
- `ci-failure` - Indicates a CI/CD pipeline failure
- `automated` - Created by automation

---

*This issue was automatically created by the CI/CD pipeline.*

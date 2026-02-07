# 🧪 Test Failure: ${CI_COMMIT_BRANCH}

One or more tests have failed in the CI/CD pipeline.

## 📋 Test Details

| Field | Value |
|-------|-------|
| **Repository** | ${CI_REPO} |
| **Branch** | ${CI_COMMIT_BRANCH} |
| **Commit** | \`${CI_COMMIT_SHA}\` |
| **Author** | ${CI_COMMIT_AUTHOR} |
| **Pipeline** | #${CI_PIPELINE_NUMBER} |

## 🔗 Links

- [View Pipeline](${CI_PIPELINE_URL})
- [View Commit](https://github.com/${CI_REPO}/commit/${CI_COMMIT_SHA})

## 📝 Commit Message

```
${CI_COMMIT_MESSAGE}
```

## 🔍 Test Failure Summary

${TEST_SUMMARY:-Please check the pipeline logs for detailed test results.}

### Failed Tests

${FAILED_TESTS:-Check the pipeline logs for the list of failed tests.}

## 🛠️ Debugging Steps

1. **Review the test output** in the pipeline logs
2. **Run tests locally** to reproduce:
   ```bash
   npm test
   # or with verbose output
   npm test -- --verbose
   ```
3. **Check recent changes** that might have caused the failure
4. **Fix the tests** or the underlying code
5. **Verify locally** before pushing

### Common Causes

- [ ] **Assertion failures** - Expected vs actual mismatch
- [ ] **Timeout errors** - Test took too long
- [ ] **Setup/teardown issues** - Test environment problems
- [ ] **Flaky tests** - Intermittent failures
- [ ] **Missing mocks** - External dependencies not mocked

### Quick Commands

```bash
# Run specific test file
npm test -- path/to/test.spec.ts

# Run with coverage
npm test -- --coverage

# Run in watch mode for debugging
npm test -- --watch

# Update snapshots if needed
npm test -- -u
```

## 📌 Labels

- `ci-failure` - CI/CD pipeline failure
- `tests` - Test-related issue
- `automated` - Created by automation

---

*This issue was automatically created by the CI/CD pipeline.*

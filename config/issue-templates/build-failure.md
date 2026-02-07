# 🏗️ Build Failure: ${CI_COMMIT_BRANCH}

The build step has failed in the CI/CD pipeline.

## 📋 Build Details

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

## 🔍 Build Error

${BUILD_ERROR:-Please check the pipeline logs for the build error details.}

### Common Build Failures

- [ ] **TypeScript errors** - Type checking failures
- [ ] **Syntax errors** - Invalid JavaScript/TypeScript
- [ ] **Missing dependencies** - Package not installed
- [ ] **Import errors** - Incorrect import paths
- [ ] **Environment issues** - Missing env variables

## 🛠️ Troubleshooting Steps

1. **Check the build logs** for specific error messages
2. **Run locally** to reproduce:
   ```bash
   npm install
   npm run build
   ```
3. **Fix the issue** in your code
4. **Test locally** before pushing
5. **Push the fix** and verify CI passes

### Quick Fixes

```bash
# Clear cache and reinstall
rm -rf node_modules package-lock.json
npm install

# Check TypeScript errors
npx tsc --noEmit

# Run build locally
npm run build
```

## 📌 Labels

- `ci-failure` - CI/CD pipeline failure
- `build` - Build-related issue
- `automated` - Created by automation

---

*This issue was automatically created by the CI/CD pipeline.*

# AI Auto-fix Documentation

> Automatically fix CI/CD failures using AI coding agents

## Overview

The AI Auto-fix system automatically attempts to fix code issues when CI/CD pipelines fail. It supports multiple AI providers and can handle various types of failures including test failures, security vulnerabilities, and build errors.

## Table of Contents

- [How It Works](#how-it-works)
- [Supported AI Providers](#supported-ai-providers)
- [Configuration](#configuration)
- [Usage](#usage)
- [Fix Strategies](#fix-strategies)
- [Safety Features](#safety-features)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                        CI/CD Pipeline                            │
│                              │                                   │
│                              ▼                                   │
│                    Tests / Security Scan                         │
│                              │                                   │
│              ┌───────────────┴───────────────┐                   │
│              ▼                               ▼                   │
│          [PASS]                          [FAIL]                  │
│              │                               │                   │
│              ▼                               ▼                   │
│         Continue                    Extract Error Context        │
│                                              │                   │
│                                              ▼                   │
│                                    ┌─────────────────┐           │
│                                    │  AI Auto-fix    │           │
│                                    │    Pipeline     │           │
│                                    └────────┬────────┘           │
│                                              │                   │
│                               ┌──────────────┼──────────────┐    │
│                               ▼              ▼              ▼    │
│                          Attempt 1      Attempt 2      Attempt 3 │
│                               │              │              │    │
│                               └──────────────┴──────────────┘    │
│                                              │                   │
│                              ┌───────────────┴───────────────┐   │
│                              ▼                               ▼   │
│                        [FIX SUCCESS]                   [FIX FAIL]│
│                              │                               │   │
│                              ▼                               ▼   │
│                      Create Fix Branch              Notify Team  │
│                              │                     Create Issue  │
│                              ▼                                   │
│                       Trigger Auto-PR                            │
└──────────────────────────────────────────────────────────────────┘
```

### Flow Summary

1. **Failure Detection**: Pipeline fails (tests, security scan, build)
2. **Error Extraction**: Error output is captured and formatted
3. **AI Fix Trigger**: AI fix pipeline is triggered with error context
4. **Fix Attempt**: AI agent analyzes error and makes code changes
5. **Verification**: Tests are run to verify the fix works
6. **Branch Creation**: Changes are committed to a fix branch
7. **Auto-PR**: Pull request is automatically created for review

## Supported AI Providers

### Claude Code (Recommended)

```yaml
provider: claude-code
```

**Features:**
- Best overall code understanding and fix quality
- Supports Claude Code CLI for direct file modifications
- Falls back to API mode if CLI unavailable

**Requirements:**
- `ANTHROPIC_API_KEY` environment variable
- (Optional) Claude Code CLI installed

**Best For:**
- Complex logic fixes
- Security vulnerability patches
- Test failure resolution

### OpenAI Codex / GPT-4

```yaml
provider: codex
```

**Features:**
- Good general-purpose code fixing
- Fast response times
- Wide language support

**Requirements:**
- `OPENAI_API_KEY` environment variable

**Best For:**
- Syntax errors
- Lint fixes
- Documentation updates

### OpenHands

```yaml
provider: openhands
```

**Features:**
- Full development environment simulation
- Can run shell commands
- Good for complex multi-step fixes

**Requirements:**
- Docker (for containerized mode)
- Or OpenHands CLI installed locally

**Best For:**
- Build configuration issues
- Dependency problems
- Multi-file refactoring

### OpenCode

```yaml
provider: opencode
```

**Features:**
- Lightweight CLI-based agent
- Local model support
- Fast iteration

**Requirements:**
- OpenCode CLI installed

**Best For:**
- Quick fixes
- Simple code changes

## Configuration

### Environment Variables

```bash
# Required: AI Provider API Keys
ANTHROPIC_API_KEY=sk-ant-xxx     # For Claude Code
OPENAI_API_KEY=sk-xxx            # For Codex

# Required: GitHub Token (for branch/PR operations)
GITHUB_TOKEN=ghp_xxx

# Optional: AI Fix Settings
AI_FIX_PROVIDER=claude-code      # Default provider
AI_FIX_MAX_ATTEMPTS=3            # Max fix attempts
AI_FIX_TIMEOUT=300               # Timeout per attempt (seconds)
AI_FIX_ENABLED=true              # Enable/disable
```

### Configuration File

Edit `config/ai-fix.yaml` to customize behavior:

```yaml
general:
  enabled: true
  max_attempts: 3
  timeout: 300
  verify_before_commit: true

providers:
  claude-code:
    enabled: true
    priority: 1
    model: "claude-sonnet-4-20250514"
    temperature: 0.1

strategies:
  test_failure:
    providers:
      - claude-code
      - codex
    prompt_additions: |
      Focus on fixing the failing tests...
```

See `config/ai-fix.yaml` for full configuration options.

## Usage

### Manual Trigger

```bash
# Basic usage
./scripts/ai-fix.sh \
  --error-file ./test-output.log \
  --repo /path/to/repo

# With specific provider
./scripts/ai-fix.sh \
  --error-file ./errors.txt \
  --repo . \
  --provider codex

# With issue reference
./scripts/ai-fix.sh \
  --error-file ./security-scan.log \
  --repo . \
  --issue-number 42

# Dry run (see what would happen)
./scripts/ai-fix.sh \
  --error-file ./errors.txt \
  --repo . \
  --dry-run \
  --verbose
```

### Pipeline Trigger

The AI fix pipeline can be triggered:

1. **Manually** via Woodpecker UI
2. **Automatically** from failed pipelines
3. **Via API** with custom event

```bash
# Trigger via API
curl -X POST "https://woodpecker.example.com/api/repos/org/repo/pipelines" \
  -H "Authorization: Bearer ${CI_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "branch": "main",
    "variables": {
      "PIPELINE_EVENT": "ai-fix",
      "ERROR_CONTEXT": "Error: Test failed...",
      "ISSUE_NUMBER": "42"
    }
  }'
```

### Script Options

```
Usage: ai-fix.sh [OPTIONS]

Required:
  --error-file <path>     Path to error output file
  --repo <path>           Path to repository

Options:
  --provider <name>       AI provider (claude-code, codex, openhands, opencode)
  --branch <name>         Fix branch name
  --max-attempts <n>      Maximum fix attempts
  --timeout <seconds>     Timeout per attempt
  --issue-number <n>      Related GitHub issue
  --dry-run               Show actions without executing
  --verbose               Enable verbose output
  --help                  Show help
```

## Fix Strategies

Different failure types use different fix strategies:

### Test Failures

```yaml
strategy: test_failure
```

- Focuses on fixing implementation, not tests
- Includes test files in context
- Higher success rate for unit tests

### Security Vulnerabilities

```yaml
strategy: security_scan
```

- Prioritizes security best practices
- Can update dependencies
- Limited to high/critical severity by default

### Lint Errors

```yaml
strategy: lint_error
```

- Respects project style guides
- Fast fixes for formatting issues
- High success rate

### Build Failures

```yaml
strategy: build_failure
```

- Analyzes build configuration
- Fixes import/dependency issues
- Handles type errors

## Safety Features

### Protected Files

The following files are never modified automatically:

- `.env` and environment files
- Secret/credential files
- Private keys (`.pem`, `.key`)

### Change Limits

```yaml
safety:
  max_files_changed: 20
  max_lines_changed: 500
  require_approval_threshold:
    files: 10
    lines: 200
```

Large changes require human approval.

### Automatic Rollback

If verification fails after a fix:

1. All changes are discarded
2. Next attempt starts fresh
3. After max attempts, manual intervention is requested

### Backup Branches

Before applying fixes:

```yaml
git:
  create_backup: true
  backup_branch_pattern: "backup/{branch}/{timestamp}"
```

## Troubleshooting

### Fix Not Triggering

1. Check AI fix is enabled: `AI_FIX_ENABLED=true`
2. Verify API keys are set correctly
3. Check pipeline logs for errors

### Fix Failing Verification

1. Review the AI's changes in the fix branch
2. Check if tests are flaky
3. Try a different provider

### API Rate Limits

```
Error: API rate limit exceeded
```

- Increase `cooldown` between attempts
- Consider using a different provider
- Check API quota

### Claude Code CLI Not Found

```
Warning: claude CLI not found, will attempt to use API directly
```

Install Claude Code CLI:

```bash
npm install -g @anthropic-ai/claude-code
```

### Large Context Errors

```
Error: Context too large for model
```

Adjust context limits:

```yaml
context:
  max_files: 30
  max_context_size: 50000
```

## Best Practices

### 1. Start with Conservative Settings

```yaml
general:
  max_attempts: 2
  verify_before_commit: true

safety:
  max_files_changed: 10
  auto_rollback_on_test_failure: true
```

### 2. Provide Good Error Context

Include:
- Full error output
- Stack traces
- Relevant log lines

```bash
./scripts/ai-fix.sh \
  --error-file ./full-test-output.log \  # Not just summary
  --repo .
```

### 3. Use Provider Strengths

| Failure Type | Recommended Provider |
|--------------|---------------------|
| Complex logic bugs | claude-code |
| Security fixes | claude-code |
| Lint/format | codex |
| Build config | openhands |

### 4. Review AI Changes

Always review the generated PR:
- Check for unintended side effects
- Verify the fix addresses root cause
- Look for potential security issues

### 5. Iterate on Prompts

Customize strategy prompts for your project:

```yaml
strategies:
  test_failure:
    prompt_additions: |
      Our project uses Jest with React Testing Library.
      Prefer using getByRole over getByTestId.
      Mock external APIs using MSW.
```

### 6. Monitor Success Rates

Track metrics:
- Fix success rate by provider
- Average attempts needed
- Types of failures fixed

### 7. Human in the Loop

For critical fixes:

```yaml
safety:
  require_approval_threshold:
    files: 5
    lines: 100
```

## Appendix

### Error File Format

The error file can contain any text output from failed tests or scans:

```
FAIL  src/utils/parser.test.ts
  ● Parser › should handle empty input

    expect(received).toEqual(expected)

    Expected: []
    Received: null

      15 |   it('should handle empty input', () => {
      16 |     const result = parse('');
    > 17 |     expect(result).toEqual([]);
         |                    ^
      18 |   });
```

### Result JSON Format

The fix script outputs results to `/tmp/ai-fix-result.json`:

```json
{
  "status": "success",
  "message": "Fix applied successfully",
  "provider": "claude-code",
  "branch": "ai-fix/20240207-123456",
  "repo": "/path/to/repo",
  "attempts": 1,
  "max_attempts": 3,
  "timestamp": "2024-02-07T12:34:56Z"
}
```

### Supported Languages

The AI providers can fix code in:

- JavaScript / TypeScript
- Python
- Go
- Rust
- Java / Kotlin
- Ruby
- PHP
- C / C++
- C#
- Swift
- And most other popular languages

---

## See Also

- [Auto-PR Documentation](./AUTO_PR.md)
- [Pipeline Documentation](./PIPELINES.md)
- [Configuration Reference](../config/ai-fix.yaml)

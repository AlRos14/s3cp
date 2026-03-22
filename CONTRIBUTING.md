# Contributing to s3cp

Thank you for considering a contribution! This is a small, focused tool — contributions that keep it simple and dependency-free are most welcome.

---

## Getting started

1. **Fork** the repository on GitHub
2. **Clone** your fork:
   ```bash
   git clone https://github.com/YOUR-USERNAME/s3cp.git
   cd s3cp
   ```
3. **Create a branch** for your change:
   ```bash
   git checkout -b feat/my-improvement
   ```
4. **Make your changes**, then test them
5. **Commit** following the [commit message convention](#commit-messages)
6. **Push** and open a **Pull Request**

---

## Development

The script has no build step. To test locally:

```bash
# Run the test suite (no AWS credentials needed)
bash tests/s3cp_test.sh

# Verbose output (shows passing tests too)
bash tests/s3cp_test.sh -v

# Syntax check only
bash -n s3cp

# Run against real AWS (requires configured credentials and a test bucket)
S3CP_BUCKET=my-test-bucket S3CP_REGION=eu-south-2 bash s3cp file.txt MyInstance:/tmp/
```

**All tests must pass before submitting a PR.**

---

## Commit messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

**Types:**

| Type | When to use |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Build, tooling, or dependency changes |

**Examples:**

```
feat: add --recursive flag for directory transfers
fix: resolve instance name search returning empty on multi-reservation accounts
docs: add contributing guide
refactor: extract aws_opts helper to deduplicate CLI flag building
```

---

## Pull request guidelines

- **One concern per PR** — don't bundle unrelated changes
- **Update CHANGELOG.md** under `[Unreleased]` with your change
- **Keep it shell** — no Python, no Node, no compiled dependencies; the script must run with `bash`, `aws`, and `jq` only
- **Run `bash tests/s3cp_test.sh`** — all tests must pass
- **Test with real AWS** if possible, or describe how you tested
- **Update README.md** if you add or change user-facing behaviour

---

## Reporting issues

Please include:
- OS and shell version (`uname -a`, `bash --version`)
- AWS CLI version (`aws --version`)
- The exact command you ran
- The full error output
- Whether it's reproducible

---

## Code style

- Use `local` for all function variables
- Prefer `[[ ]]` over `[ ]`
- Functions use `snake_case`
- Keep lines under 100 characters where practical
- Add a comment only when the *why* isn't obvious from the code

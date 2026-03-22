# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Test suite (`tests/s3cp_test.sh`) — 75 tests covering argument parsing, input validation, config loading, security hardening, and IAM policy; runs without AWS credentials

### Changed
- Refactored `aws_opts()` from echo-based function to array (`AWS_OPTS`) for safe word splitting
- Replaced per-function `trap` with cumulative cleanup function to prevent trap overwrite
- Config file now written with `chmod 600` permissions
- S3 cleanup failures now emit a warning instead of silent suppression
- IAM policy (`iam/policy-user.json`) trimmed: removed unused `s3:ListBucket`

### Fixed
- Command injection via SSM commands: added `validate_shell_safe()` to reject dangerous characters in filenames, remote paths, and usernames
- Tar path traversal (zip-slip): added `--no-absolute-names` to all `tar -xzf` calls
- `build_aws_opts` silently exiting when no AWS profile is set (`set -e` + short-circuit return)
- Missing value guards on `--bucket`, `--region`, `--profile`, `--user`, `--timeout` flags
- Numeric validation for `timeout` and `presign_expiry` parameters
- Early validation when S3 bucket is not configured
- Empty remote path on pull now defaults to `/home/<user>/`
- Instance ID regex tightened to match real EC2 format (8 or 17 hex chars)
- `configure` now rejects empty bucket name
- Added `--` separator on `aws s3 cp` source arguments to protect against filenames starting with `-`

### Security
- Documented presigned URL CloudTrail visibility in README

## [1.0.1] - 2026-03-04

### Changed
- Switched CLI flow to scp-like syntax: `s3cp <source> <destination>` with remote paths as `instance:/path`
- Replaced instance-side AWS CLI dependency with presigned URLs and `curl`

### Fixed
- Made remote path optional on push (`instance:` defaults to `/home/<user>/`)
- Improved transfer error guidance for curl exit 23 when destination is a directory (trailing slash hint)
- Handled instance name resolution edge case when no matches are returned
- Corrected ANSI color escape quoting for reliable terminal rendering
- Grep failure in resolve_instance function
- Updated `s3cp configure` usage instructions
- Updated README license author name



## [1.0.0] - 2026-03-02

### Added
- `push` command: transfer files from local machine to EC2 instance
- `pull` command: transfer files from EC2 instance to local machine
- `configure` command: interactive setup wizard for `~/.config/s3cp/config`
- `--recursive` / `-r` flag: directory transfers via auto tar/untar
- Instance resolution by Name tag (partial, case-insensitive) or Instance ID
- Interactive instance picker when multiple instances match a name
- Config file support (`~/.config/s3cp/config`) with priority chain:
  flag → env var → config file → built-in default
- `--no-cleanup` flag to keep the S3 object after transfer
- Auto-cleanup of S3 temp objects after successful transfer
- Color output with auto-detection (disabled when piped)
- IAM policy templates for EC2 instances and local users

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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

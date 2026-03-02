# s3cp

**Transfer files between your local machine and EC2 instances — no SSH required.**

`s3cp` is a single-file Bash script that replaces `scp` in environments where SSH has been removed from EC2 instances. It uses **S3 as an ephemeral intermediary** and **SSM `send-command`** to orchestrate both sides of the transfer from a single command.

```
local machine                    S3 (temp)                  EC2 instance
─────────────  ── upload ──▶  ──────────────  ── download ──▶  ──────────────
s3cp file.sql server:/home/ubuntu/            auto-deleted

─────────────  ◀─ download ──  ──────────────  ◀── upload ──  ──────────────
s3cp server:/var/log/app.log ./               auto-deleted
```

---

## Why?

| Feature | `scp` | `s3cp` |
|---|---|---|
| Requires SSH (port 22) | ✅ | ❌ |
| Works with SSM-only instances | ❌ | ✅ |
| Encrypted in transit | ✅ | ✅ (TLS) |
| Encrypted at rest | ❌ | ✅ (SSE-S3) |
| Auditable (CloudTrail) | ❌ | ✅ |
| Survives broken connection | ❌ | ✅ |
| Instance lookup by name | ❌ | ✅ |

---

## Requirements

**Local machine:**
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials + MFA
- [`jq`](https://stedolan.github.io/jq/) (`apt install jq` / `brew install jq`)

**EC2 instances:**
- [SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html) installed and running
- `curl` installed (typically pre-installed on most Linux distributions)

---

## Installation

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/AlRos14/s3cp/main/install.sh | bash
```

### Manual

```bash
curl -fsSL https://raw.githubusercontent.com/AlRos14/s3cp/main/s3cp -o /usr/local/bin/s3cp
chmod +x /usr/local/bin/s3cp
```

### From source

```bash
git clone https://github.com/AlRos14/s3cp.git
sudo cp s3cp/s3cp /usr/local/bin/s3cp
```

---

## Setup

### 1. Create the S3 bucket

```bash
aws s3api create-bucket \
  --bucket YOUR-BUCKET-NAME \
  --region YOUR-REGION \
  --create-bucket-configuration LocationConstraint=YOUR-REGION

# Block public access
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET-NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket YOUR-BUCKET-NAME \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}, "BucketKeyEnabled": true}]
  }'

# Auto-delete objects after 7 days (safety net)
aws s3api put-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME \
  --lifecycle-configuration '{
    "Rules": [{"ID": "auto-cleanup-7d", "Status": "Enabled", "Filter": {"Prefix": ""},
    "Expiration": {"Days": 7}, "NoncurrentVersionExpiration": {"NoncurrentDays": 1}}]
  }'
```

### 2. Configure AWS credentials on your local machine

Ensure your AWS CLI has `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `ssm:SendCommand`, `ssm:GetCommandInvocation`, and `ec2:DescribeInstances` permissions (see `iam/policy-user.json` for reference).

### 3. Configure s3cp

```bash
s3cp configure
```

This creates `~/.config/s3cp/config`:

```ini
bucket=your-bucket-name
region=your-region
user=ubuntu
timeout=300
presign_expiry=300
# profile=myprofile
```

---

## Usage

```bash
s3cp configure                               # interactive setup (run once)
s3cp <local-path> <instance>:<remote-path>   # push: local → instance
s3cp <instance>:<remote-path> <local-path>   # pull: instance → local
```

`<instance>` can be an **Instance ID** (`i-0abc123...`) or a **Name tag** (partial, case-insensitive).  
`<remote-path>` can be omitted to default to `/home/<user>/` — e.g. `my-server:`.

### Examples

```bash
# Send a file to an instance (by name tag)
s3cp backup.sql my-server:/home/ubuntu/

# Download a log file from an instance
s3cp my-server:/var/log/app.log ./

# Transfer a directory
s3cp -r ./my-app my-server:/home/ubuntu/

# Use by instance ID
s3cp data.csv i-052c8baf8bbe98f2f:/tmp/

# Omit remote path — defaults to /home/ubuntu/
s3cp file.txt my-server:

# One-off with different bucket/region (no config change)
s3cp -b my-other-bucket -R us-east-1 file.txt my-server:/tmp/
```

### Options

```
-r, --recursive     Transfer directories (auto tar/untar)
-b, --bucket NAME   S3 bucket override
-R, --region REGION AWS region override
-p, --profile NAME  AWS CLI profile override
-u, --user USER     OS user on instance override
-t, --timeout SECS  SSM command timeout override (default: 300)
--no-cleanup        Keep the S3 temp object after transfer
-V, --version       Show version
-h, --help          Show help
```

### Configuration priority

```
CLI flag  →  environment variable  →  config file  →  built-in default
```

| Config key | Flag | Env var |
|---|---|---|
| `bucket` | `-b` / `--bucket` | `S3CP_BUCKET` |
| `region` | `-R` / `--region` | `S3CP_REGION` |
| `profile` | `-p` / `--profile` | `S3CP_PROFILE` |
| `user` | `-u` / `--user` | `SSM_USER` |
| `timeout` | `-t` / `--timeout` | `S3CP_TIMEOUT` |
| `presign_expiry` | — | `S3CP_PRESIGN_EXPIRY` |

---

## How it works

### Push (local → instance)

1. Uploads the local file to `s3://BUCKET/transfers/<uuid>/filename` (server-side encrypted)
2. Generates a presigned URL (time-limited, single-use credentials)
3. Sends `curl` download command via `ssm:SendCommand` to the instance
4. Polls `ssm:GetCommandInvocation` until complete
5. Deletes the S3 object

### Pull (instance → local)

1. Generates a presigned PUT URL with temporary credentials
2. Sends `curl` upload command via `ssm:SendCommand` to the instance
3. Polls `ssm:GetCommandInvocation` until complete
4. Downloads from S3 to the local path
5. Deletes the S3 object

**Security note:** Presigned URLs are time-limited and contain temporary credentials. EC2 instances never store permanent AWS credentials. S3 objects are deleted immediately after each transfer. The 7-day lifecycle rule is a safety net in case of interrupted transfers.

---

## IAM reference

### Local user IAM policy

Your AWS IAM user needs the following permissions:
- `s3:GetObject` - download files from S3
- `s3:PutObject` - upload files to S3  
- `s3:DeleteObject` - clean up temporary transfer objects
- `ssm:SendCommand` - send remote commands to instances via SSM
- `ssm:GetCommandInvocation` - poll command status
- `ec2:DescribeInstances` - resolve instance names to IDs

See [`iam/policy-user.json`](iam/policy-user.json) for a complete policy definition.

### EC2 instance requirements

EC2 instances **do not need S3 permissions** or AWS credentials. They only need:
- **SSM Agent** - to receive and execute commands
- **curl** - to download/upload files via presigned URLs (pre-installed on most Linux distributions)

Presigned URLs are generated on the local machine with temporary credentials and contain an expiration time (default: 5 minutes).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

[MIT](LICENSE) © Alejandro Ros

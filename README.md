# s3cp

**Transfer files between your local machine and EC2 instances — no SSH required.**

`s3cp` is a single-file Bash script that replaces `scp` in environments where SSH has been removed from EC2 instances. It uses **S3 as an ephemeral intermediary** and **SSM `send-command`** to orchestrate both sides of the transfer from a single command.

```
local machine                    S3 (temp)                  EC2 instance
─────────────  ── upload ──▶  ──────────────  ── download ──▶  ──────────────
s3cp push                       auto-deleted                  /home/ubuntu/

─────────────  ◀─ download ──  ──────────────  ◀── upload ──  ──────────────
s3cp pull                       auto-deleted                  /var/log/app.log
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
- IAM role with [`iam/policy-ec2.json`](iam/policy-ec2.json) attached

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

### 2. Attach IAM policy to your EC2 instance roles

```bash
aws iam put-role-policy \
  --role-name YOUR-INSTANCE-ROLE \
  --policy-name s3cp-access \
  --policy-document file://iam/policy-ec2.json
```

Replace `nutraliascp` in [`iam/policy-ec2.json`](iam/policy-ec2.json) with your bucket name.

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
# profile=myprofile
```

---

## Usage

```bash
s3cp configure                                   # interactive setup (run once)
s3cp push <local-path> <instance> <remote-path>  # local → instance
s3cp pull <instance> <remote-path> [local-path]  # instance → local
```

`<instance>` can be an **Instance ID** (`i-0abc123...`) or a **Name tag** (partial, case-insensitive).

### Examples

```bash
# Send a file to an instance (by name)
s3cp push backup.sql OdooFire /home/ubuntu/

# Download a log file from an instance
s3cp pull NutriaServer /var/log/app.log ./

# Transfer a directory
s3cp push -r ./my-app OdooFire /home/ubuntu/

# Use by instance ID
s3cp push data.csv i-052c8baf8bbe98f2f /tmp/

# One-off with different bucket/region (no config change)
s3cp push -b my-other-bucket -R us-east-1 file.txt MyServer /tmp/
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

---

## How it works

### Push (local → instance)

1. Uploads the local file to `s3://BUCKET/transfers/<uuid>/filename`
2. Sends `aws s3 cp` via `ssm:SendCommand` to the instance
3. Polls `ssm:GetCommandInvocation` until complete
4. Deletes the S3 object

### Pull (instance → local)

1. Sends `aws s3 cp` via `ssm:SendCommand` to upload from the instance to S3
2. Polls `ssm:GetCommandInvocation` until complete
3. Downloads from S3 to the local path
4. Deletes the S3 object

S3 objects are deleted immediately after each transfer. The 7-day lifecycle rule is a safety net in case of interrupted transfers.

---

## IAM reference

### EC2 instance role (`iam/policy-ec2.json`)

Allows the instance to read/write/delete from the S3 bucket.

### Local user policy

Your AWS IAM user needs `ssm:SendCommand`, `ssm:GetCommandInvocation`, and S3 read/write permissions on the bucket. Example in [`iam/policy-user.json`](iam/policy-user.json).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

[MIT](LICENSE) © Alejandro Ros

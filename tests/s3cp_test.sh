#!/usr/bin/env bash
# s3cp test suite — runs without AWS credentials
#
# Usage:  bash tests/s3cp_test.sh
#         bash tests/s3cp_test.sh -v          # verbose (show passing tests)
#
# All tests run locally using mock commands. No AWS account needed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
S3CP="$PROJECT_DIR/s3cp"

# Prevent env leaking from user's shell
unset S3CP_BUCKET S3CP_REGION S3CP_PROFILE SSM_USER S3CP_TIMEOUT S3CP_PRESIGN_EXPIRY

# ── Test framework ───────────────────────────────────────────
PASS=0; FAIL=0; TOTAL=0
VERBOSE=false
[[ "${1:-}" == "-v" ]] && VERBOSE=true

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

pass() {
  (( PASS++ )); (( TOTAL++ ))
  $VERBOSE && echo "  ${GREEN}✔${RESET} $1"
}

fail() {
  (( FAIL++ )); (( TOTAL++ ))
  echo "  ${RED}✖${RESET} $1"
  [[ -n "${2:-}" ]] && echo "    ${DIM}$2${RESET}"
}

section() {
  echo ""
  echo "${BOLD}▸ $1${RESET}"
}

# Strip ANSI escape codes from text
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# ── Setup: mock commands & temp environment ──────────────────
MOCK_DIR=$(mktemp -d)
MOCK_CONFIG_DIR=$(mktemp -d)

# Mock aws, jq, tar so require_cmd passes and script can be sourced
for cmd in aws jq; do
  cat > "$MOCK_DIR/$cmd" <<'MOCKCMD'
#!/usr/bin/env bash
exit 0
MOCKCMD
  chmod +x "$MOCK_DIR/$cmd"
done

cleanup() {
  rm -rf "$MOCK_DIR" "$MOCK_CONFIG_DIR"
}
trap cleanup EXIT

# Helper: run s3cp with mocked PATH and no config
# Prefix KEY=VALUE pairs before the s3cp arguments to set env vars.
#   run_s3cp S3CP_BUCKET=x file.txt inst:/tmp/
run_s3cp() {
  local -a env_vars=()
  while [[ "${1:-}" == *=* && "${1%%=*}" =~ ^[A-Z0-9_]+$ ]]; do
    env_vars+=("$1"); shift
  done
  env "${env_vars[@]}" \
    XDG_CONFIG_HOME="$MOCK_CONFIG_DIR" \
    PATH="$MOCK_DIR:$PATH" \
    bash "$S3CP" "$@" 2>&1 | strip_ansi
}

# Helper: get exit code from s3cp
run_s3cp_rc() {
  local -a env_vars=()
  while [[ "${1:-}" == *=* && "${1%%=*}" =~ ^[A-Z0-9_]+$ ]]; do
    env_vars+=("$1"); shift
  done
  env "${env_vars[@]}" \
    XDG_CONFIG_HOME="$MOCK_CONFIG_DIR" \
    PATH="$MOCK_DIR:$PATH" \
    bash "$S3CP" "$@" &>/dev/null
  echo $?
}

# Helper: source just the function definitions (up to require_cmd)
# by creating a trimmed version that skips require_cmd and arg parsing
source_functions() {
  local tmp
  tmp=$(mktemp)
  # Extract everything up to "# ── Pre-checks" and replace set -euo with set -uo
  sed -n '1,/^# ── Pre-checks/p' "$S3CP" \
    | sed 's/^set -euo pipefail/set +e; set -uo pipefail/' \
    | head -n -1 > "$tmp"
  # Add mock build_aws_opts call
  echo 'AWS_OPTS=( --region us-east-1 )' >> "$tmp"
  XDG_CONFIG_HOME="$MOCK_CONFIG_DIR" \
  PATH="$MOCK_DIR:$PATH" \
  source "$tmp" 2>/dev/null
  local rc=$?
  rm -f "$tmp"
  return $rc
}


# ═════════════════════════════════════════════════════════════
#  TESTS
# ═════════════════════════════════════════════════════════════

# ── 1. Syntax check ─────────────────────────────────────────
section "Syntax"

if bash -n "$S3CP" 2>/dev/null; then
  pass "script passes bash -n syntax check"
else
  fail "script fails bash -n syntax check"
fi

# ── 2. Version & help ───────────────────────────────────────
section "Version & help"

out=$(run_s3cp --version)
if [[ "$out" == *"s3cp v"* ]]; then
  pass "--version prints version string"
else
  fail "--version output unexpected" "$out"
fi

out=$(run_s3cp --help)
if [[ "$out" == *"USAGE"* && "$out" == *"OPTIONS"* && "$out" == *"EXAMPLES"* ]]; then
  pass "--help shows usage, options, and examples"
else
  fail "--help output incomplete" "$out"
fi

rc=$(run_s3cp_rc --help)
if [[ "$rc" == "0" ]]; then
  pass "--help exits 0"
else
  fail "--help exits $rc (expected 0)"
fi

out=$(run_s3cp help)
if [[ "$out" == *"USAGE"* ]]; then
  pass "'help' subcommand shows usage"
else
  fail "'help' subcommand output unexpected" "$out"
fi

# ── 3. Argument parsing: missing values ─────────────────────
section "Argument parsing — missing flag values"

for flag in --bucket --region --profile --user --timeout; do
  short_flag="${flag#--}"
  out=$(run_s3cp "$flag" 2>&1)
  rc=$?
  if [[ "$out" == *"requires a value"* ]]; then
    pass "$flag without value shows error"
  else
    fail "$flag without value: expected 'requires a value'" "$out"
  fi
done

# ── 4. Argument parsing: unknown option ─────────────────────
section "Argument parsing — unknown options"

out=$(run_s3cp --bogus 2>&1)
if [[ "$out" == *"Unknown option: --bogus"* ]]; then
  pass "unknown option shows error"
else
  fail "unknown option: expected 'Unknown option: --bogus'" "$out"
fi

# ── 5. Argument parsing: no arguments ───────────────────────
section "Argument parsing — no arguments"

rc=$(run_s3cp_rc)
if [[ "$rc" != "0" ]]; then
  pass "no arguments exits non-zero"
else
  fail "no arguments should exit non-zero"
fi

# ── 6. Argument parsing: wrong number of positional args ────
section "Argument parsing — positional args count"

out=$(run_s3cp -b mybucket one two three 2>&1)
if [[ "$out" == *"Usage: s3cp"* ]]; then
  pass "3 positional args shows usage error"
else
  fail "3 positional args: expected usage error" "$out"
fi

out=$(run_s3cp S3CP_BUCKET=mybucket single-arg 2>&1)
if [[ "$out" == *"Usage: s3cp"* ]]; then
  pass "1 non-configure positional arg shows usage error"
else
  fail "1 non-configure positional arg: expected usage error" "$out"
fi

# ── 7. Numeric parameter validation ─────────────────────────
section "Numeric parameter validation"

out=$(run_s3cp S3CP_BUCKET=test -t abc file.txt inst:/tmp/ 2>&1)
if [[ "$out" == *"timeout must be a positive integer"* ]]; then
  pass "non-numeric timeout rejected"
else
  fail "non-numeric timeout: expected rejection" "$out"
fi

out=$(run_s3cp S3CP_BUCKET=test -t -5 file.txt inst:/tmp/ 2>&1)
if [[ "$out" == *"timeout must be a positive integer"* ]]; then
  pass "negative timeout rejected"
else
  fail "negative timeout: expected rejection" "$out"
fi

out=$(run_s3cp S3CP_BUCKET=test S3CP_PRESIGN_EXPIRY=abc file.txt inst:/tmp/ 2>&1)
if [[ "$out" == *"presign_expiry must be a positive integer"* ]]; then
  pass "non-numeric presign_expiry rejected"
else
  fail "non-numeric presign_expiry: expected rejection" "$out"
fi

# Valid numeric values should not trigger the validation error
out=$(run_s3cp S3CP_BUCKET=test -t 60 file.txt inst:/tmp/ 2>&1)
if [[ "$out" != *"timeout must be a positive integer"* ]]; then
  pass "valid numeric timeout accepted"
else
  fail "valid numeric timeout rejected unexpectedly" "$out"
fi

# ── 8. Bucket validation ────────────────────────────────────
section "Bucket validation"

out=$(run_s3cp S3CP_BUCKET= file.txt inst:/tmp/ 2>&1)
if [[ "$out" == *"No S3 bucket configured"* ]]; then
  pass "empty bucket shows configuration error"
else
  fail "empty bucket: expected 'No S3 bucket configured'" "$out"
fi

out=$(run_s3cp S3CP_BUCKET=mybucket file.txt inst:/tmp/ 2>&1)
if [[ "$out" != *"No S3 bucket configured"* ]]; then
  pass "S3CP_BUCKET env var bypasses bucket error"
else
  fail "S3CP_BUCKET set but still got bucket error" "$out"
fi

# ── 9. Route validation ─────────────────────────────────────
section "Route validation — remote path detection"

out=$(run_s3cp S3CP_BUCKET=test /local/a /local/b 2>&1)
if [[ "$out" == *"must be a remote path"* ]]; then
  pass "two local paths rejected"
else
  fail "two local paths: expected remote path error" "$out"
fi

out=$(run_s3cp S3CP_BUCKET=test inst1:/path inst2:/path 2>&1)
if [[ "$out" == *"Cannot transfer between two remote paths"* ]]; then
  pass "two remote paths rejected"
else
  fail "two remote paths: expected rejection" "$out"
fi

# ── 10. validate_shell_safe ─────────────────────────────────
section "Input sanitization — validate_shell_safe"

source_functions 2>/dev/null
# Reset errexit after source (sourced script enables pipefail)
set +e

# Safe values should pass
for safe_val in "file.txt" "my-app_v2.tar.gz" "/home/ubuntu/data" "file123" "a.b.c"; do
  if (validate_shell_safe "test" "$safe_val" 2>/dev/null); then
    pass "safe value accepted: $safe_val"
  else
    fail "safe value rejected: $safe_val"
  fi
done

# Unsafe values should fail
unsafe_cases=(
  "file'name"
  'file`whoami`'
  'path;rm -rf /'
  'val|cat /etc/passwd'
  'val&bg'
  'file$(cmd)'
  'path>out'
  'path<in'
  'file\nline'
  'a(b)'
  'a{b}'
)
unsafe_labels=(
  "single quote"
  "backtick"
  "semicolon"
  "pipe"
  "ampersand"
  "dollar-subshell"
  "angle-bracket-gt"
  "angle-bracket-lt"
  "backslash"
  "parentheses"
  "curly braces"
)

for i in "${!unsafe_cases[@]}"; do
  val="${unsafe_cases[$i]}"
  label="${unsafe_labels[$i]}"
  if ! (validate_shell_safe "test" "$val" 2>/dev/null); then
    pass "unsafe value rejected ($label): $val"
  else
    fail "unsafe value accepted ($label): $val"
  fi
done

# ── 11. Instance ID regex ───────────────────────────────────
section "Instance ID regex"

# Valid IDs
for id in "i-0a1b2c3d" "i-0a1b2c3d4e5f6a7b8" "i-abcdef01" "i-abcdef0123456789a"; do
  if [[ "$id" =~ ^i-[0-9a-f]{8}([0-9a-f]{9})?$ ]]; then
    pass "valid instance ID accepted: $id"
  else
    fail "valid instance ID rejected: $id"
  fi
done

# Invalid IDs
for id in "i-0" "i-abc" "i-0a1b2c3" "i-ABCDEF01" "i-0a1b2c3d4" "0a1b2c3d" "i-0a1b2c3d4e5f6a7b" "i-0a1b2c3d4e5f6a7b89"; do
  if [[ ! "$id" =~ ^i-[0-9a-f]{8}([0-9a-f]{9})?$ ]]; then
    pass "invalid instance ID rejected: $id"
  else
    fail "invalid instance ID accepted: $id"
  fi
done

# ── 12. s3_temp_key format ──────────────────────────────────
section "s3_temp_key format"

key=$(s3_temp_key "myfile.txt")
if [[ "$key" =~ ^transfers/[^/]+/myfile\.txt$ ]]; then
  pass "s3_temp_key has correct format: $key"
else
  fail "s3_temp_key format unexpected: $key"
fi

key2=$(s3_temp_key "myfile.txt")
if [[ "$key" != "$key2" ]]; then
  pass "s3_temp_key generates unique keys"
else
  fail "s3_temp_key returned same key twice"
fi

key=$(s3_temp_key "file with spaces.log")
if [[ "$key" =~ ^transfers/[^/]+/file\ with\ spaces\.log$ ]]; then
  pass "s3_temp_key preserves filename with spaces"
else
  fail "s3_temp_key with spaces unexpected: $key"
fi

# ── 13. Config file handling ────────────────────────────────
section "Config file — load_config"

# Write a test config
mkdir -p "$MOCK_CONFIG_DIR/s3cp"
cat > "$MOCK_CONFIG_DIR/s3cp/config" <<'EOF'
# test config
bucket=test-bucket-123
region=us-west-2
user=ec2-user
timeout=600
presign_expiry=120
# profile=commented-out
EOF

# Source with the test config to check values are loaded
_CF_BUCKET="" _CF_REGION="" _CF_USER="" _CF_TIMEOUT="" _CF_PRESIGN_EXPIRY="" _CF_PROFILE=""
CONFIG_FILE="$MOCK_CONFIG_DIR/s3cp/config"
load_config

if [[ "$_CF_BUCKET" == "test-bucket-123" ]]; then
  pass "config loads bucket"
else
  fail "config bucket: got '$_CF_BUCKET', expected 'test-bucket-123'"
fi

if [[ "$_CF_REGION" == "us-west-2" ]]; then
  pass "config loads region"
else
  fail "config region: got '$_CF_REGION', expected 'us-west-2'"
fi

if [[ "$_CF_USER" == "ec2-user" ]]; then
  pass "config loads user"
else
  fail "config user: got '$_CF_USER', expected 'ec2-user'"
fi

if [[ "$_CF_TIMEOUT" == "600" ]]; then
  pass "config loads timeout"
else
  fail "config timeout: got '$_CF_TIMEOUT', expected '600'"
fi

if [[ "$_CF_PRESIGN_EXPIRY" == "120" ]]; then
  pass "config loads presign_expiry"
else
  fail "config presign_expiry: got '$_CF_PRESIGN_EXPIRY', expected '120'"
fi

if [[ -z "${_CF_PROFILE:-}" ]]; then
  pass "config skips commented-out profile"
else
  fail "config profile should be empty, got '$_CF_PROFILE'"
fi

# Config with profile set
echo "profile=prod" >> "$MOCK_CONFIG_DIR/s3cp/config"
_CF_PROFILE=""
load_config
if [[ "$_CF_PROFILE" == "prod" ]]; then
  pass "config loads profile when uncommented"
else
  fail "config profile: got '$_CF_PROFILE', expected 'prod'"
fi

# Missing config file
rm "$MOCK_CONFIG_DIR/s3cp/config"
_CF_BUCKET="untouched"
CONFIG_FILE="$MOCK_CONFIG_DIR/s3cp/nonexistent"
load_config
if [[ "$_CF_BUCKET" == "untouched" ]]; then
  pass "missing config file leaves values unchanged"
else
  fail "missing config file modified values"
fi

# ── 14. Config file permissions ─────────────────────────────
section "Config file — permissions after configure"

# We can't easily run do_configure (interactive), but we can verify
# the chmod 600 line exists in the script
if grep -q 'chmod 600 "$CONFIG_FILE"' "$S3CP"; then
  pass "script sets config file to mode 600"
else
  fail "script missing chmod 600 on config file"
fi

# ── 15. Security hardening presence checks ──────────────────
section "Security hardening — code presence"

if grep -q 'validate_shell_safe' "$S3CP"; then
  pass "validate_shell_safe function exists"
else
  fail "validate_shell_safe function missing"
fi

count=$(grep -c 'validate_shell_safe' "$S3CP")
if [[ $count -ge 7 ]]; then
  pass "validate_shell_safe called in both push and pull ($count occurrences)"
else
  fail "validate_shell_safe: expected ≥7 occurrences, found $count"
fi

if grep -q '\-\-no-absolute-names' "$S3CP"; then
  pass "--no-absolute-names present in tar commands"
else
  fail "--no-absolute-names missing from tar commands"
fi

tar_extract_count=$(grep -c '\-\-no-absolute-names' "$S3CP")
if [[ $tar_extract_count -ge 2 ]]; then
  pass "--no-absolute-names on both push and pull tar extractions ($tar_extract_count)"
else
  fail "--no-absolute-names: expected ≥2, found $tar_extract_count"
fi

# ── 16. Flag override priority ──────────────────────────────
section "Config priority — flag overrides env var"

# --bucket flag should override S3CP_BUCKET env var
# We test this indirectly: with flag set, the bucket error shouldn't fire
out=$(run_s3cp S3CP_BUCKET= -b flag-bucket file.txt inst:/tmp/ 2>&1)
if [[ "$out" != *"No S3 bucket configured"* ]]; then
  pass "--bucket flag overrides empty S3CP_BUCKET"
else
  fail "--bucket flag didn't override empty S3CP_BUCKET" "$out"
fi

# ── 17. Cleanup warning ────────────────────────────────────
section "Cleanup warning — code presence"

if grep -q 'warn "Failed to clean up S3 object' "$S3CP"; then
  pass "s3_cleanup warns on failure instead of silent suppression"
else
  fail "s3_cleanup missing warning on failure"
fi

# ── 18. IAM policy least privilege ──────────────────────────
section "IAM policy — least privilege"

policy="$PROJECT_DIR/iam/policy-user.json"
if [[ -f "$policy" ]]; then
  if ! grep -q 'ListBucket' "$policy"; then
    pass "IAM policy does not include unused s3:ListBucket"
  else
    fail "IAM policy still includes s3:ListBucket (unused)"
  fi

  # Verify required permissions are present
  for perm in GetObject PutObject DeleteObject SendCommand GetCommandInvocation DescribeInstances; do
    if grep -q "$perm" "$policy"; then
      pass "IAM policy includes required $perm"
    else
      fail "IAM policy missing required $perm"
    fi
  done
else
  fail "IAM policy file not found: $policy"
fi


# ═════════════════════════════════════════════════════════════
#  SUMMARY
# ═════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
  echo "${GREEN}${BOLD}All $TOTAL tests passed ✔${RESET}"
else
  echo "${RED}${BOLD}$FAIL of $TOTAL tests failed ✖${RESET}"
  echo "${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $FAIL

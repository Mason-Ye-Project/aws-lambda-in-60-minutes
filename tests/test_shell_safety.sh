#!/usr/bin/env bash
set -euo pipefail

# Exercises deploy.sh and cleanup.sh against a fake "aws" on PATH, so
# it makes no real AWS calls. It confirms the scripts (1) treat a
# lookup permission error as a failure, not as "absent", (2) verify
# absence before reporting a clean result, and (3) refuse to touch a
# name-matching resource that lacks the lab ownership tag.

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

# Write a fake "aws". FAKE_AWS_MODE selects the behavior. Messages are
# short on purpose; only the presence or absence of the not-found
# marker (and the exit status) matters to the scripts under test.
mkdir -p "$temporary_dir/bin"
cat >"$temporary_dir/bin/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

arguments="$*"
mode="${FAKE_AWS_MODE:?}"
fake_arn="arn:aws:lambda:ap-southeast-2:ACCOUNT:function:lambda-60-lab"

if [[ "$mode" == "access-denied" ]]; then
  printf 'AccessDenied\n' >&2
  exit 254
fi

if [[ "$mode" == "nothing-exists" ]]; then
  if [[ "$arguments" == *"lambda get-function"* ]]; then
    printf 'ResourceNotFoundException\n' >&2
    exit 254
  fi
  if [[ "$arguments" == *"logs describe-log-groups"* ]]; then
    printf '0\n'
    exit 0
  fi
  if [[ "$arguments" == *"iam get-role"* ]]; then
    printf 'NoSuchEntity\n' >&2
    exit 254
  fi
fi

if [[ "$mode" == "untagged-function" ]]; then
  if [[ "$arguments" == *"--query Configuration.FunctionArn"* ]]; then
    printf '%s\n' "$fake_arn"
    exit 0
  fi
  if [[ "$arguments" == *"lambda get-function"* ]]; then
    printf '{}\n'
    exit 0
  fi
  if [[ "$arguments" == *"lambda list-tags"* ]]; then
    printf 'None\n'
    exit 0
  fi
fi

if [[ "$mode" == "deploy-untagged-function" ]]; then
  if [[ "$arguments" == *"iam get-role"* ]]; then
    printf 'NoSuchEntity\n' >&2
    exit 254
  fi
  if [[ "$arguments" == *"logs describe-log-groups"* ]]; then
    printf '0\n'
    exit 0
  fi
  if [[ "$arguments" == *"--query Configuration.FunctionArn"* ]]; then
    printf '%s\n' "$fake_arn"
    exit 0
  fi
  if [[ "$arguments" == *"lambda get-function"* ]]; then
    printf '{}\n'
    exit 0
  fi
  if [[ "$arguments" == *"lambda list-tags"* ]]; then
    printf 'None\n'
    exit 0
  fi
fi

printf 'Unexpected fake AWS call in mode %s: %s\n' \
  "$mode" "$arguments" >&2
exit 99
FAKE_AWS
chmod +x "$temporary_dir/bin/aws"

fake_path="$temporary_dir/bin:$PATH"

# 1. A lookup permission error must fail, not be read as "absent".
if PATH="$fake_path" FAKE_AWS_MODE=access-denied \
  "$project_dir/scripts/cleanup.sh" \
  >"$temporary_dir/access.out" 2>"$temporary_dir/access.err"; then
  printf 'cleanup.sh succeeded despite a lookup permission error.\n' >&2
  exit 1
fi
grep -q 'Unable to check Lambda function' \
  "$temporary_dir/access.err"

# 2. When nothing exists, cleanup verifies absence and reports success.
PATH="$fake_path" FAKE_AWS_MODE=nothing-exists \
  "$project_dir/scripts/cleanup.sh" \
  >"$temporary_dir/absent.out" 2>"$temporary_dir/absent.err"
grep -q 'Cleanup verified' "$temporary_dir/absent.out"

# 3. cleanup must not delete an unowned name-matching function.
if PATH="$fake_path" FAKE_AWS_MODE=untagged-function \
  "$project_dir/scripts/cleanup.sh" \
  >"$temporary_dir/tag.out" 2>"$temporary_dir/tag.err"; then
  printf 'cleanup.sh deleted an unowned name-matching function.\n' >&2
  exit 1
fi
grep -q 'ownership tag is absent' "$temporary_dir/tag.err"

# 4. deploy must not modify an unowned name-matching function.
if PATH="$fake_path" FAKE_AWS_MODE=deploy-untagged-function \
  "$project_dir/scripts/deploy.sh" \
  >"$temporary_dir/deploy.out" 2>"$temporary_dir/deploy.err"; then
  printf 'deploy.sh modified an unowned name-matching function.\n' >&2
  exit 1
fi
grep -q 'ownership tag is absent' "$temporary_dir/deploy.err"

printf 'Shell safety tests passed.\n'

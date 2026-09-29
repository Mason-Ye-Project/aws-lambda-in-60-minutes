#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin"
cat >"$temporary_dir/bin/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

arguments="$*"
mode="${FAKE_AWS_MODE:?}"

if [[ "$mode" == "access-denied" ]]; then
  printf 'An error occurred (AccessDeniedException) when calling the operation: denied\n' >&2
  exit 254
fi

if [[ "$mode" == "nothing-exists" ]]; then
  if [[ "$arguments" == *"lambda get-function"* ]]; then
    printf 'An error occurred (ResourceNotFoundException): missing\n' >&2
    exit 254
  fi
  if [[ "$arguments" == *"logs describe-log-groups"* ]]; then
    printf '0\n'
    exit 0
  fi
  if [[ "$arguments" == *"iam get-role"* ]]; then
    printf 'An error occurred (NoSuchEntity): missing\n' >&2
    exit 254
  fi
fi

if [[ "$mode" == "untagged-function" ]]; then
  if [[ "$arguments" == *"lambda get-function"* && "$arguments" == *"--query Configuration.FunctionArn"* ]]; then
    printf 'arn:aws:lambda:ap-southeast-2:000000000000:function:lambda-60-lab\n'
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
    printf 'An error occurred (NoSuchEntity): missing\n' >&2
    exit 254
  fi
  if [[ "$arguments" == *"logs describe-log-groups"* ]]; then
    printf '0\n'
    exit 0
  fi
  if [[ "$arguments" == *"lambda get-function"* && "$arguments" == *"--query Configuration.FunctionArn"* ]]; then
    printf 'arn:aws:lambda:ap-southeast-2:000000000000:function:lambda-60-lab\n'
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

printf 'Unexpected fake AWS call in mode %s: %s\n' "$mode" "$arguments" >&2
exit 99
FAKE_AWS
chmod +x "$temporary_dir/bin/aws"

if PATH="$temporary_dir/bin:$PATH" FAKE_AWS_MODE=access-denied \
  "$project_dir/scripts/cleanup.sh" >"$temporary_dir/access.out" 2>"$temporary_dir/access.err"; then
  printf 'cleanup.sh incorrectly succeeded when lookup permission was denied.\n' >&2
  exit 1
fi
grep -q 'Unable to check Lambda function' "$temporary_dir/access.err"

PATH="$temporary_dir/bin:$PATH" FAKE_AWS_MODE=nothing-exists \
  "$project_dir/scripts/cleanup.sh" >"$temporary_dir/absent.out" 2>"$temporary_dir/absent.err"
grep -q 'Cleanup verified' "$temporary_dir/absent.out"

if PATH="$temporary_dir/bin:$PATH" FAKE_AWS_MODE=untagged-function \
  "$project_dir/scripts/cleanup.sh" >"$temporary_dir/tag.out" 2>"$temporary_dir/tag.err"; then
  printf 'cleanup.sh incorrectly deleted an unowned name-matching function.\n' >&2
  exit 1
fi
grep -q 'ownership tag is absent' "$temporary_dir/tag.err"

if PATH="$temporary_dir/bin:$PATH" FAKE_AWS_MODE=deploy-untagged-function \
  "$project_dir/scripts/deploy.sh" >"$temporary_dir/deploy-tag.out" 2>"$temporary_dir/deploy-tag.err"; then
  printf 'deploy.sh incorrectly modified an unowned name-matching function.\n' >&2
  exit 1
fi
grep -q 'ownership tag is absent' "$temporary_dir/deploy-tag.err"

printf 'Shell safety tests passed.\n'

#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
region="${AWS_REGION:-ap-southeast-2}"
function_name="${FUNCTION_NAME:-lambda-60-lab}"
role_name="${ROLE_NAME:-lambda-60-lab-role}"
managed_policy="AWSLambdaBasicExecutionRole"
policy_arn="arn:aws:iam::aws:policy/service-role/$managed_policy"
log_group="/aws/lambda/$function_name"
owner_tag_key="lambda-60-lab"
owner_tag_value="true"
trust_policy="$project_dir/infra/lambda-trust-policy.json"

# lookup runs a read-only AWS call. It prints the output and returns 0
# on success, returns 3 when the output shows the explicit not-found
# marker, and otherwise reports the real error and returns its status
# (so a permission or network failure is never read as "absent").
lookup() {
  local not_found_marker="$1"
  local label="$2"
  shift 2
  local output
  local status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if ((status == 0)); then
    printf '%s' "$output"
    return 0
  fi
  if [[ "$output" == *"$not_found_marker"* ]]; then
    return 3
  fi

  printf 'Unable to check %s. AWS returned:\n%s\n' \
    "$label" "$output" >&2
  return "$status"
}

# require_value refuses to touch a resource whose ownership tag is
# absent.
require_value() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local reason
  if [[ "$actual" != "$expected" ]]; then
    reason='Refusing to modify %s because the expected'
    reason="$reason lab ownership tag is absent.\n"
    printf "$reason" "$label" >&2
    exit 1
  fi
}

"$project_dir/scripts/package.sh"

# Preflight every possible name collision before creating or
# changing anything.
role_exists=false
if role_output="$(lookup NoSuchEntity "IAM role $role_name" \
  aws iam get-role --role-name "$role_name" --output json)"; then
  role_exists=true
  role_tag="$(aws iam list-role-tags \
    --role-name "$role_name" \
    --query "Tags[?Key=='$owner_tag_key'].Value | [0]" \
    --output text)"
  require_value "$role_tag" "$owner_tag_value" \
    "IAM role $role_name"
else
  status=$?
  if ((status != 3)); then
    exit "$status"
  fi
fi

log_group_count="$(aws logs describe-log-groups \
  --region "$region" \
  --log-group-name-prefix "$log_group" \
  --query "length(logGroups[?logGroupName=='$log_group'])" \
  --output text)"
log_group_exists=false
if [[ "$log_group_count" == "1" ]]; then
  log_group_exists=true
  log_group_tag="$(aws logs list-tags-log-group \
    --region "$region" \
    --log-group-name "$log_group" \
    --query "tags.\"$owner_tag_key\"" \
    --output text)"
  require_value "$log_group_tag" "$owner_tag_value" \
    "CloudWatch log group $log_group"
elif [[ "$log_group_count" != "0" ]]; then
  printf 'Unexpected log-group lookup result for %s: %s\n' \
    "$log_group" "$log_group_count" >&2
  exit 1
fi

function_exists=false
if function_output="$(lookup ResourceNotFoundException \
  "Lambda function $function_name" \
  aws lambda get-function \
    --region "$region" \
    --function-name "$function_name" \
    --output json)"; then
  function_exists=true
  function_arn="$(aws lambda get-function \
    --region "$region" \
    --function-name "$function_name" \
    --query 'Configuration.FunctionArn' \
    --output text)"
  function_tag="$(aws lambda list-tags \
    --region "$region" \
    --resource "$function_arn" \
    --query "Tags.\"$owner_tag_key\"" \
    --output text)"
  require_value "$function_tag" "$owner_tag_value" \
    "Lambda function $function_name"
else
  status=$?
  if ((status != 3)); then
    exit "$status"
  fi
fi

if [[ "$role_exists" == false ]]; then
  aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "file://$trust_policy" \
    --tags Key="$owner_tag_key",Value="$owner_tag_value" \
    >/dev/null
fi

# Re-applying an attached managed policy is idempotent and repairs a
# partial first run.
aws iam attach-role-policy \
  --role-name "$role_name" \
  --policy-arn "$policy_arn"
role_arn="$(aws iam get-role \
  --role-name "$role_name" \
  --query 'Role.Arn' \
  --output text)"

if [[ "$log_group_exists" == false ]]; then
  aws logs create-log-group \
    --region "$region" \
    --log-group-name "$log_group"
  aws logs tag-log-group \
    --region "$region" \
    --log-group-name "$log_group" \
    --tags "$owner_tag_key=$owner_tag_value"
fi

if [[ "$function_exists" == true ]]; then
  aws lambda update-function-code \
    --region "$region" \
    --function-name "$function_name" \
    --zip-file "fileb://$project_dir/build/function.zip" \
    >/dev/null
  aws lambda wait function-updated-v2 \
    --region "$region" \
    --function-name "$function_name"
  aws lambda update-function-configuration \
    --region "$region" \
    --function-name "$function_name" \
    --runtime python3.14 \
    --handler lambda_function.lambda_handler \
    --role "$role_arn" \
    --timeout 3 \
    --memory-size 128 \
    --environment 'Variables={APP_ENV=lab}' \
    >/dev/null
  aws lambda wait function-updated-v2 \
    --region "$region" \
    --function-name "$function_name"
else
  printf 'Waiting briefly for the new IAM role to propagate...\n'
  sleep 10
  aws lambda create-function \
    --region "$region" \
    --function-name "$function_name" \
    --runtime python3.14 \
    --handler lambda_function.lambda_handler \
    --role "$role_arn" \
    --zip-file "fileb://$project_dir/build/function.zip" \
    --timeout 3 \
    --memory-size 128 \
    --environment 'Variables={APP_ENV=lab}' \
    --tags "$owner_tag_key=$owner_tag_value" \
    >/dev/null
  aws lambda wait function-active-v2 \
    --region "$region" \
    --function-name "$function_name"
fi

printf 'Function %s is ready in %s.\n' "$function_name" "$region"

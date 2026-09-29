#!/usr/bin/env bash
set -euo pipefail

region="${AWS_REGION:-ap-southeast-2}"
function_name="${FUNCTION_NAME:-lambda-60-lab}"
role_name="${ROLE_NAME:-lambda-60-lab-role}"
policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
log_group="/aws/lambda/$function_name"
owner_tag_key="lambda-60-lab"
owner_tag_value="true"

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

  printf 'Unable to check %s. AWS returned:\n%s\n' "$label" "$output" >&2
  return "$status"
}

require_value() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Refusing to delete %s because the expected lab ownership tag is absent.\n' "$label" >&2
    exit 1
  fi
}

# Validate ownership and policy boundaries for every resource before deleting any.
function_exists=false
if function_output="$(lookup ResourceNotFoundException "Lambda function $function_name" \
  aws lambda get-function --region "$region" --function-name "$function_name" --output json)"; then
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
  require_value "$function_tag" "$owner_tag_value" "Lambda function $function_name"
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
  require_value "$log_group_tag" "$owner_tag_value" "CloudWatch log group $log_group"
elif [[ "$log_group_count" != "0" ]]; then
  printf 'Unexpected log-group lookup result for %s: %s\n' "$log_group" "$log_group_count" >&2
  exit 1
fi

role_exists=false
expected_policy_count="0"
if role_output="$(lookup NoSuchEntity "IAM role $role_name" \
  aws iam get-role --role-name "$role_name" --output json)"; then
  role_exists=true
  role_tag="$(aws iam list-role-tags \
    --role-name "$role_name" \
    --query "Tags[?Key=='$owner_tag_key'].Value | [0]" \
    --output text)"
  require_value "$role_tag" "$owner_tag_value" "IAM role $role_name"

  unexpected_policies="$(aws iam list-attached-role-policies \
    --role-name "$role_name" \
    --query "AttachedPolicies[?PolicyArn!='${policy_arn}'].PolicyArn" \
    --output text)"
  inline_policies="$(aws iam list-role-policies \
    --role-name "$role_name" \
    --query 'PolicyNames' \
    --output text)"
  if [[ -n "$unexpected_policies" || -n "$inline_policies" ]]; then
    printf 'Refusing to delete IAM role %s because it has policies outside this lab.\n' "$role_name" >&2
    exit 1
  fi

  expected_policy_count="$(aws iam list-attached-role-policies \
    --role-name "$role_name" \
    --query "length(AttachedPolicies[?PolicyArn=='${policy_arn}'])" \
    --output text)"
else
  status=$?
  if ((status != 3)); then
    exit "$status"
  fi
fi

if [[ "$function_exists" == true ]]; then
  aws lambda delete-function --region "$region" --function-name "$function_name"
fi
if [[ "$log_group_exists" == true ]]; then
  aws logs delete-log-group --region "$region" --log-group-name "$log_group"
fi
if [[ "$role_exists" == true ]]; then
  if [[ "$expected_policy_count" == "1" ]]; then
    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
  fi
  aws iam delete-role --role-name "$role_name"
fi

if lookup ResourceNotFoundException "deleted Lambda function $function_name" \
  aws lambda get-function --region "$region" --function-name "$function_name" --output json \
  >/dev/null; then
  printf 'Lambda function %s still exists after the delete request.\n' "$function_name" >&2
  exit 1
else
  status=$?
  if ((status != 3)); then
    exit "$status"
  fi
fi

remaining_log_groups="$(aws logs describe-log-groups \
  --region "$region" \
  --log-group-name-prefix "$log_group" \
  --query "length(logGroups[?logGroupName=='$log_group'])" \
  --output text)"
if [[ "$remaining_log_groups" != "0" ]]; then
  printf 'CloudWatch log group %s still exists after the delete request.\n' "$log_group" >&2
  exit 1
fi

if lookup NoSuchEntity "deleted IAM role $role_name" \
  aws iam get-role --role-name "$role_name" --output json \
  >/dev/null; then
  printf 'IAM role %s still exists after the delete request.\n' "$role_name" >&2
  exit 1
else
  status=$?
  if ((status != 3)); then
    exit "$status"
  fi
fi

printf 'Cleanup verified for the function, log group, and role.\n'

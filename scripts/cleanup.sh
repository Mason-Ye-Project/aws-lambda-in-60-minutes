#!/usr/bin/env bash
set -euo pipefail

region="${AWS_REGION:-ap-southeast-2}"
function_name="${FUNCTION_NAME:-lambda-60-lab}"
role_name="${ROLE_NAME:-lambda-60-lab-role}"
policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
log_group="/aws/lambda/$function_name"

if aws lambda get-function --region "$region" --function-name "$function_name" >/dev/null 2>&1; then
  aws lambda delete-function --region "$region" --function-name "$function_name"
fi

if aws logs describe-log-groups \
  --region "$region" \
  --log-group-name-prefix "$log_group" \
  --query "length(logGroups[?logGroupName=='$log_group'])" \
  --output text | grep -qx '1'; then
  aws logs delete-log-group --region "$region" --log-group-name "$log_group"
fi

if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || true
  aws iam delete-role --role-name "$role_name"
fi

printf 'Cleanup requested for function, log group, and role.\n'

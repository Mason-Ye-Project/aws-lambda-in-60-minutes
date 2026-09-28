#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
region="${AWS_REGION:-ap-southeast-2}"
function_name="${FUNCTION_NAME:-lambda-60-lab}"
role_name="${ROLE_NAME:-lambda-60-lab-role}"
policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

"$project_dir/scripts/package.sh"

if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document file://"$project_dir/infra/lambda-trust-policy.json" \
    --tags Key=lambda-60-lab,Value=true \
    >/dev/null
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
fi

role_arn="$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)"

if aws lambda get-function --region "$region" --function-name "$function_name" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --region "$region" \
    --function-name "$function_name" \
    --zip-file fileb://"$project_dir/build/function.zip" \
    >/dev/null
  aws lambda wait function-updated --region "$region" --function-name "$function_name"
  aws lambda update-function-configuration \
    --region "$region" \
    --function-name "$function_name" \
    --runtime python3.14 \
    --handler lambda_function.lambda_handler \
    --timeout 3 \
    --memory-size 128 \
    --environment 'Variables={APP_ENV=lab}' \
    >/dev/null
else
  printf 'Waiting briefly for the new IAM role to propagate...\n'
  sleep 10
  aws lambda create-function \
    --region "$region" \
    --function-name "$function_name" \
    --runtime python3.14 \
    --handler lambda_function.lambda_handler \
    --role "$role_arn" \
    --zip-file fileb://"$project_dir/build/function.zip" \
    --timeout 3 \
    --memory-size 128 \
    --environment 'Variables={APP_ENV=lab}' \
    --tags lambda-60-lab=true \
    >/dev/null
fi

aws lambda wait function-active-v2 --region "$region" --function-name "$function_name"
printf 'Function %s is active in %s.\n' "$function_name" "$region"

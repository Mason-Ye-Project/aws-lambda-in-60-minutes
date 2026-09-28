#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
region="${AWS_REGION:-ap-southeast-2}"
function_name="${FUNCTION_NAME:-lambda-60-lab}"
event_file="${1:-$project_dir/events/hello.json}"
response_file="${2:-$project_dir/build/response.json}"
metadata_file="$project_dir/build/invoke-metadata.json"

mkdir -p "$project_dir/build"
aws lambda invoke \
  --region "$region" \
  --function-name "$function_name" \
  --payload fileb://"$event_file" \
  --cli-binary-format raw-in-base64-out \
  "$response_file" >"$metadata_file"

printf 'Invocation metadata:\n'
python3 -m json.tool "$metadata_file"
printf 'Function response:\n'
python3 -m json.tool "$response_file"

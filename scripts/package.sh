#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$project_dir/build"

mkdir -p "$build_dir"
rm -f "$build_dir/function.zip"

(
  cd "$project_dir/src"
  zip -q "$build_dir/function.zip" lambda_function.py
)

printf 'Created %s\n' "$build_dir/function.zip"

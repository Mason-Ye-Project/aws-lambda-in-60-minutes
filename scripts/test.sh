#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

PYTHONPATH=. python3 -m unittest discover -s tests -v
"$project_dir/tests/test_shell_safety.sh"

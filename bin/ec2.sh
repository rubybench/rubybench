#!/bin/bash
set -uxo pipefile

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

export RUBYBENCH_RESULTS_REPO="git@github-rubybench-data:rubybench/rubybench-data.git"
export RUBYBENCH_RESULTS_COMMIT_PREFIX="[ruby-kai1] "

# Ensure RUBYBENCH_RESULTS_REPO is set
if [[ -z "$RUBYBENCH_RESULTS_REPO" ]]; then
  echo "ERROR: RUBYBENCH_RESULTS_REPO environment variable is not set" >&2
  echo "This variable must be set to the git repository where results should be pushed" >&2
  exit 1
fi

# Prepare results repository (clean clone)
bin/prepare-results.rb

# Run ruby-bench
benchmark/ruby-bench.rb --results-root /home/ubuntu/rubybench-tmp


#!/bin/bash
set -uxo pipefail

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

RUBY_ARGS=""
if [[ -n "$BENCHMARK_RUBY_PATH" && -x "$BENCHMARK_RUBY_PATH" ]]; then
    if [[ -z "$BENCHMARK_DATE" ]]; then
        echo "ERROR: BENCHMARK_DATE required when BENCHMARK_RUBY_PATH is set" >&2
        exit 1
    fi
    RUBY_ARGS="--ruby $BENCHMARK_RUBY_PATH --date $BENCHMARK_DATE"
fi

# Run ruby-bench
benchmark/ruby-bench.rb \
    --results-root /home/ubuntu/rubybench-tmp \
    $RUBY_ARGS

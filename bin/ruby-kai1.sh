#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

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
bin/prepare-results.rb || exit 1

# Run ruby-bench
benchmark/ruby-bench.rb
bin/dashboard.rb

# Sync ruby-bench results
bin/sync-results.rb ruby-bench

# Ruby ruby/ruby
set +x
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  echo "+ benchmark/ruby.rb $bench"
  benchmark/ruby.rb "$bench"
done

# Sync ruby/ruby benchmark results
set -x
bin/sync-results.rb ruby || exit 1

# Run ruby-bench with modular GC and MMTk only after both result sets are uploaded.
benchmark/ruby-bench.rb --mmtk --results-root results/mmtk

# Sync MMTk ruby-bench results
bin/sync-results.rb mmtk

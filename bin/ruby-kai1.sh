#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

export RUBYBENCH_RESULTS_REPO="git@github-rubybench-data:rubybench/rubybench-data.git"
export RUBYBENCH_STATS_REPO="git@github-rubybench-stats:rubybench/rubybench-stats.git"
export RUBYBENCH_RESULTS_COMMIT_PREFIX="[ruby-kai1] "

# Ensure RUBYBENCH_RESULTS_REPO is set
if [[ -z "$RUBYBENCH_RESULTS_REPO" ]]; then
  echo "ERROR: RUBYBENCH_RESULTS_REPO environment variable is not set" >&2
  echo "This variable must be set to the git repository where results should be pushed" >&2
  exit 1
fi

# Prepare results repository (clean clone)
bin/prepare-results.rb

# Prepare stats repository
bin/prepare-stats.rb

# Run ruby-bench (with ZJIT stats collection)
stats_dir="${RUBYBENCH_STATS_DIR:-$(cd "$rubybench/.."; pwd)/rubybench-stats}"
benchmark/ruby-bench.rb --stats-dir "$stats_dir"
bin/dashboard.rb

# Sync ruby-bench results
bin/sync-results.rb ruby-bench

# Sync ZJIT stats
bin/sync-stats.rb

# Ruby ruby/ruby
set +x
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  echo "+ benchmark/ruby.rb $bench"
  benchmark/ruby.rb "$bench"
done

# Sync ruby/ruby benchmark results
bin/sync-results.rb ruby

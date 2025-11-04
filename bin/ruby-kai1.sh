#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

export RUBYBENCH_RESULTS_REPO="git@github-rubybench-data:rubybench/rubybench-data.git"
export RUBYBENCH_RESULTS_COMMIT_PREFIX="[ruby-kai1] "

# Run ruby-bench
benchmark/ruby-bench.rb
bin/dashboard.rb
bin/git-push.sh "ruby-kai1: Benchmark ruby-bench"

# Ruby ruby/ruby
set +x
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  echo "+ benchmark/ruby.rb $bench"
  benchmark/ruby.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark ruby/ruby"

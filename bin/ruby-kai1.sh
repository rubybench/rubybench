#!/bin/bash
set -euxo pipefail

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Run benchmarks
for bench in optcarrot railsbench; do
  bin/benchmark.rb "$bench"
  bin/git-push.sh "ruby-kai1: Benchmark ${bench}"
done

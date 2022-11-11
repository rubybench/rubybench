#!/bin/bash
set -euxo pipefail

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Run yjit-bench
for bench in activerecord hexapdf liquid-render mail psych-load railsbench \
             binarytrees chunky_png erubi erubi_rails etanni fannkuchredux lee nbody optcarrot ruby-lsp rubykon; do
  benchmark/yjit-bench.rb "$bench"
  bin/git-push.sh "ruby-kai1: Benchmark ${bench}"
done

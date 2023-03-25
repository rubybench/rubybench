#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Run yjit-bench
for bench in activerecord hexapdf liquid-render mail psych-load railsbench ruby-lsp sequel liquid-c \
             binarytrees chunky_png erubi erubi_rails etanni fannkuchredux ruby-json lee nbody optcarrot rubykon \
             30k_ifelse 30k_methods cfunc_itself fib getivar keyword_args respond_to setivar setivar_object setivar_young_object str_concat throw; do
  benchmark/yjit-bench.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark yjit-bench"

# Ruby ruby/ruby
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  benchmark/ruby.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark ruby/ruby"

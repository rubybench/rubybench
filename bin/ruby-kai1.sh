#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Run yjit-bench
for bench in activerecord erubi_rails hexapdf liquid-c liquid-render mail psych-load railsbench ruby-lsp sequel \
             binarytrees chunky_png erubi etanni fannkuchredux ruby-json lee nbody optcarrot rubykon \
             30k_ifelse 30k_methods cfunc_itself fib getivar keyword_args respond_to setivar setivar_object setivar_young str_concat throw; do
  benchmark/yjit-bench.rb "$bench"
done
bin/dashboard.rb
bin/git-push.sh "ruby-kai1: Benchmark yjit-bench"

# Ruby ruby/ruby
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  benchmark/ruby.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark ruby/ruby"

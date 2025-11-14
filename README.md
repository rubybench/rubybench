# Rubybench

Benchmark runner for [rubybench.github.io](https://rubybench.github.io)

## Apply recipes

```bash
# dry-run
bin/hocho apply -n ruby-kai1

# apply
bin/hocho apply ruby-kai1
```

## YJIT Stats Collection (New Feature)

Rubybench now supports collecting YJIT runtime statistics, similar to yjit-metrics. This provides detailed insights into JIT compilation effectiveness.

### Quick Start

```bash
# Run benchmarks with YJIT stats collection
./benchmark/ruby-bench.rb --collect-stats

# Or use the stats-enabled runner
./bin/ruby-kai1-with-stats.sh
```

For full documentation, see [docs/YJIT_STATS.md](docs/YJIT_STATS.md).

### Key Features
- Collects ratio_in_yjit (% of code executed by YJIT)
- Generates exit reports showing why YJIT exits to interpreter
- Creates HTML dashboard with compilation statistics
- Optimized storage (~113 MB/year vs 365 MB for full data)

## How it works

1. ruby/docker-images builds a Docker image nightly. Each image has a date in the image name, e.g. 20250908.
2. New Ruby versions are tracked in rubies.yml within the rubybench-data repository.
3. The ruby-kai1 server runs a [systemd timer](infra/recipes/files/lib/systemd/system/rubybench.timer).
4. That timer essentially just keeps executing [bin/ruby-kai1.sh](bin/ruby-kai1.sh) (or [bin/ruby-kai1-with-stats.sh](bin/ruby-kai1-with-stats.sh) for YJIT stats).
5. That script runs a benchmark, updates YAMLs, and pushes it to the rubybench-data repository with bin/sync-results.rb.
6. As soon as the YAML is pushed, https://github.com/rubybench/rubybench.github.io sees it through GitHub's raw bob.

## Useful commands

* Stopping the timer (to avoid interferences): `sudo systemctl stop rubybench.timer`

## License

MIT License

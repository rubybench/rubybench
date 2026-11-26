# Rubybench

Benchmark runner for [rubybench.github.io](https://rubybench.github.io)

## Apply recipes

Note: Currently, Ruby 4.0 seems to raise an exception. You might want to try Ruby 3.3 or something until it's fixed.

```bash
# dry-run
bin/hocho apply -n ruby-kai1

# apply
bin/hocho apply ruby-kai1
```

## How it works

1. ruby/docker-images builds a Docker image nightly. Each image has a date in the image name, e.g. 20250908.
2. New Ruby versions are tracked in rubies.yml within the rubybench-data repository.
3. The ruby-kai1 server runs a [systemd timer](infra/recipes/files/lib/systemd/system/rubybench.timer).
4. That timer essentially just keeps executing [bin/ruby-kai1.sh](bin/ruby-kai1.sh).
5. That script runs a benchmark, updates YAMLs, and pushes it to the rubybench-data repository with bin/sync-results.rb.
6. After the ruby-bench and ruby/ruby results are pushed, the script picks the newest of the last 7 dates in rubies.yml that has a published `ghcr.io/ruby/ruby:master-modular-gc-<sha>` image and no MMTk result. It runs ruby-bench in that image with `RUBY_GC_LIBRARY=mmtk`, writes YAMLs under `results/mmtk/`, and pushes them with `bin/sync-results.rb mmtk`.
7. As soon as the YAML is pushed, https://github.com/rubybench/rubybench.github.io sees it through GitHub's raw bob.

## Useful commands

* Stopping the timer (to avoid interferences): `sudo systemctl stop rubybench.timer`

## License

MIT License

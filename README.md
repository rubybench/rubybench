# Rubybench

Benchmark runner for [rubybench.github.io](https://rubybench.github.io)

## Apply recipes

```bash
# dry-run
bin/hocho apply -n ruby-kai1

# apply
bin/hocho apply ruby-kai1
```

## How it works

1. ruby/docker-images builds a Docker image nightly. Each image has a date in the image name, e.g. 20250908.
2. rubybench/rubybench's GitHub Actions tries to pull today's image. once it becomes ready, rubies.yml is updated in the repository.
3. The ruby-kai1 server runs a [systemd timer](infra/recipes/files/lib/systemd/system/rubybench.timer).
4. That timer essentially just keeps executing [bin/ruby-kai1.sh](bin/ruby-kai1.sh).
5. That script runs a benchmark, updates YAMLs, and pushes it to the rubybench-data repository with bin/sync-results.rb.
6. As soon as the YAML is pushed, https://github.com/rubybench/rubybench.github.io sees it through GitHub's raw bob.

## Useful commands

* Stopping the timer (to avoid interferences): `sudo systemctl stop rubybench.timer`

## License

MIT License

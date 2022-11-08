# Actions

Benchmark runner for [rubybench.github.io](https://rubybench.github.io)

## Development

To test bin/benchmark.rb locally without spending too much time, you can use:

```
YJIT_BENCH_ENV="WARMUP_ITRS=0 MIN_BENCH_ITRS=1 MIN_BENCH_TIME=0" bin/benchmark.rb railsbench
```

## License

MIT License
